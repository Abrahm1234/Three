extends Node
class_name ProgramBN

const DEBUG_VERIFY := true

const RandomCtx := preload("res://addons/res_layout3d/core/RandomCtx.gd")
const TrainingData := preload("res://addons/res_layout3d/data/TrainingData.gd")

## Bayesian Network Node
class BNNode:
	var name: String
	var domain: Array  # Possible values
	var parents: Array[String] = []
	var cpt: Dictionary = {}  # Conditional Probability Table
	
	func sample_given(parent_values: Dictionary, rng: RandomNumberGenerator) -> Variant:
		var key := _cpt_key(parent_values)
		if not cpt.has(key):
			# Uniform fallback
			return domain[rng.randi() % domain.size()] if domain.size() > 0 else null
		
		var probs: Array = cpt[key]
		var r := rng.randf()
		var cumsum := 0.0
		for i in range(probs.size()):
			cumsum += probs[i]
			if r <= cumsum:
				return domain[i]
		return domain[-1]
	
	func _cpt_key(parent_vals: Dictionary) -> String:
		if parents.is_empty():
			return "root"
		var parts: PackedStringArray = []
		for p in parents:
			parts.append("%s=%s" % [p, str(parent_vals.get(p, ""))])
		return "|".join(parts)

## Network structure
var nodes: Dictionary = {}  # name -> BNNode
var training_data: TrainingData
var rng_ctx: RandomCtx
var schema_edges: Dictionary = {}
var adj_node_pairs: Dictionary = {}

# Legacy fallback support
var P_beds := {
	"small": [2, 3],
	"med": [3, 4],
	"large": [4, 5],
}
var P_baths_given_beds := {2: 1, 3: 2, 4: 3, 5: 3}

func configure_rng(ctx: RandomCtx) -> void:
	rng_ctx = ctx

func configure_from_schema(s: Dictionary) -> void:
	schema_edges = s.duplicate(true)
	if DEBUG_VERIFY:
		print("[BN] configure_from_schema: schema_keys=%d" % s.keys().size())

func _rng() -> RandomNumberGenerator:
	return rng_ctx.rng if rng_ctx != null else RandomNumberGenerator.new()

func _randi() -> int:
	return rng_ctx.randi() if rng_ctx != null else randi()

func _bucket_sq_m2(m2: float) -> String:
	if m2 < 120.0:
		return "small"
	if m2 < 200.0:
		return "med"
	return "large"

## Train from data using simplified structure learning
func train(data: TrainingData, floors: int = 1, schema_in: Dictionary = {}) -> void:
	training_data = data
	var instances: Array

	match floors:
		1: instances = data.single_story
		2: instances = data.two_story
		3: instances = data.three_story
		_: instances = data.single_story

	if instances.is_empty():
		push_warning("No training data for %d floors" % floors)
		_build_default_structure()
		return

	if schema_in.is_empty():
		var binning := TrainingData.bin_corpus(instances)
		schema_edges = binning.get("schema", {})
	else:
		schema_edges = schema_in.duplicate(true)
		TrainingData.apply_binning(instances, schema_edges)

	_build_structure_from_data(instances)
	_learn_parameters(instances)

func train_binned(instances: Array, schema_in: Dictionary) -> void:
	schema_edges = schema_in.duplicate(true)
	_build_structure_from_data(instances)
	_learn_parameters(instances)
	if DEBUG_VERIFY:
		var row_count := 0
		for node_name in nodes.keys():
				row_count += nodes[node_name].cpt.size()
		print("[BN] trained: instances=%d cpt_rows=%d nodes=%d" % [instances.size(), row_count, nodes.size()])

## Build network structure (simplified)
func _build_structure_from_data(instances: Array) -> void:
	nodes.clear()
	adj_node_pairs.clear()

	var total_domain := _bin_domain(schema_edges.get("total_m2_edges", PackedFloat64Array()))
	if total_domain.is_empty():
		total_domain = [0, 1, 2]
	var sqft_node := BNNode.new()
	sqft_node.name = "total_m2_bin"
	sqft_node.domain = total_domain
	nodes[sqft_node.name] = sqft_node

	var footprint_domain := _footprint_domain(
		schema_edges.get("footprint_w_edges", PackedFloat64Array()),
		schema_edges.get("footprint_d_edges", PackedFloat64Array())
	)
	if footprint_domain.is_empty():
		footprint_domain = [0]
	var footprint_node := BNNode.new()
	footprint_node.name = "footprint_bin"
	footprint_node.domain = footprint_domain
	footprint_node.parents = [sqft_node.name]
	nodes[footprint_node.name] = footprint_node

	var bedroom_domain := _collect_unique_counts(instances, "Bedroom")
	if bedroom_domain.is_empty():
		bedroom_domain = [0, 1, 2, 3, 4, 5]
	var bed_node := BNNode.new()
	bed_node.name = "bedrooms"
	bed_node.domain = bedroom_domain
	bed_node.parents = [sqft_node.name]
	nodes[bed_node.name] = bed_node

	var bathroom_domain := _collect_unique_counts(instances, "Bathroom")
	if bathroom_domain.is_empty():
		bathroom_domain = [0, 1, 2, 3]
	var bath_node := BNNode.new()
	bath_node.name = "bathrooms"
	bath_node.domain = bathroom_domain
	bath_node.parents = ["bedrooms"]
	nodes[bath_node.name] = bath_node

	var room_types_variant := schema_edges.get("room_types", [])
	var room_types: Array
	if room_types_variant is Array:
		room_types = room_types_variant.duplicate()
	else:
		room_types = []
	if room_types.is_empty():
		room_types = _extract_unique_room_types(instances)
	var count_max_dict_variant := schema_edges.get("count_max_by_type", {})
	var count_max_dict: Dictionary = count_max_dict_variant if count_max_dict_variant is Dictionary else {}
	for room_type in room_types:
		var exists_node := BNNode.new()
		exists_node.name = "%s_exists" % room_type
		exists_node.domain = [0, 1]
		exists_node.parents = [sqft_node.name]
		nodes[exists_node.name] = exists_node

		var max_count := int(count_max_dict.get(room_type, 4))
		var count_domain: Array = []
		for i in range(max_count + 1):
				count_domain.append(i)
		if count_domain.is_empty():
				count_domain = [0]
		var count_node := BNNode.new()
		count_node.name = "count_%s" % room_type
		count_node.domain = count_domain
		count_node.parents = [exists_node.name]
		nodes[count_node.name] = count_node

		var area_map_variant := schema_edges.get("area_labels", {})
		var area_map: Dictionary = area_map_variant if area_map_variant is Dictionary else {}
		var area_labels_variant := area_map.get(room_type)
		var area_domain: Array = []
		if area_labels_variant is Array:
				area_domain = (area_labels_variant as Array).duplicate()
		else:
				area_domain = _bin_domain(schema_edges.get("room_area_edges", PackedFloat64Array()))
		var area_node := BNNode.new()
		area_node.name = "%s_area_bin" % room_type
		area_node.domain = area_domain
		area_node.parents = [exists_node.name]
		nodes[area_node.name] = area_node

		var aspect_map_variant := schema_edges.get("aspect_labels", {})
		var aspect_map: Dictionary = aspect_map_variant if aspect_map_variant is Dictionary else {}
		var aspect_labels_variant := aspect_map.get(room_type)
		var aspect_domain: Array = []
		if aspect_labels_variant is Array:
				aspect_domain = (aspect_labels_variant as Array).duplicate()
		else:
				aspect_domain = _bin_domain(schema_edges.get("aspect_edges", PackedFloat64Array()))
		var aspect_node := BNNode.new()
		aspect_node.name = "%s_aspect_bin" % room_type
		aspect_node.domain = aspect_domain
		aspect_node.parents = [exists_node.name]
		nodes[aspect_node.name] = aspect_node

	var pair_labels_variant := schema_edges.get("adj_pair_labels", schema_edges.get("adj_pairs", []))
	var pair_labels: Array
	if pair_labels_variant is Array:
		pair_labels = pair_labels_variant.duplicate()
	else:
		pair_labels = []
	if pair_labels.is_empty():
		pair_labels = _collect_unique_adj_pair_labels(instances)
	var type_labels_variant := schema_edges.get("adj_type_labels", [])
	var type_labels: Array = []
	if type_labels_variant is Array:
		type_labels = (type_labels_variant as Array).duplicate()
	var has_type_nodes := not type_labels.is_empty()
	for label in pair_labels:
		var exist_node := BNNode.new()
		exist_node.name = _adj_exist_key(label)
		exist_node.domain = [0, 1]
		var parents: Array[String] = []
		var parts: PackedStringArray = label.split("|", false)
		if parts.size() >= 2:
			var pa := "count_%s" % parts[0]
			var pb := "count_%s" % parts[1]
			if nodes.has(pa):
				parents.append(pa)
			if nodes.has(pb):
				parents.append(pb)
		if parents.is_empty():
			parents.append(sqft_node.name)
		exist_node.parents = parents
		nodes[exist_node.name] = exist_node

		if has_type_nodes:
			var type_node := BNNode.new()
			type_node.name = "adj_type:%s" % label
			type_node.domain = type_labels.duplicate()
			type_node.parents = [exist_node.name]
			nodes[type_node.name] = type_node
			adj_node_pairs[type_node.name] = label
	if DEBUG_VERIFY:
		var edge_count := 0
		for node_name in nodes.keys():
			var node_ref: BNNode = nodes[node_name]
			edge_count += node_ref.parents.size()
		print("[BN] prepared: nodes=%d edges=%d schema_loaded=%s" % [nodes.size(), edge_count, str(not schema_edges.is_empty())])
func _learn_parameters(instances: Array) -> void:
	for node_name in nodes.keys():
		var node: BNNode = nodes[node_name]
		var counts := {}

		for inst in instances:
				var dict_inst := _instance_to_dict(inst)
				if dict_inst.is_empty():
						continue

				var parent_vals := {}
				var missing_parent := false
				for parent in node.parents:
						if not dict_inst.has(parent):
								missing_parent = true
								break
						parent_vals[parent] = dict_inst[parent]
				if missing_parent:
						continue

				if not dict_inst.has(node_name):
						continue
				var key := node._cpt_key(parent_vals)
				if not counts.has(key):
						counts[key] = {}
				var value = dict_inst[node_name]
				counts[key][value] = int(counts[key].get(value, 0)) + 1

		if counts.is_empty():
				var uniform: Array = []
				if node.domain.is_empty():
						uniform = []
				else:
						var weight := 1.0 / node.domain.size()
						for _v in node.domain:
								uniform.append(weight)
				node.cpt["root"] = uniform
				continue

		for key in counts.keys():
				var probs: Array = []
				var total := 0.0
				for domain_val in node.domain:
						total += float(counts[key].get(domain_val, 0)) + 1.0
				for domain_val in node.domain:
						var count_val := float(counts[key].get(domain_val, 0)) + 1.0
						probs.append(count_val / total)
				node.cpt[key] = probs
	if DEBUG_VERIFY:
		var row_count := 0
		for node_name in nodes.keys():
			var node_ref: BNNode = nodes[node_name]
			row_count += node_ref.cpt.size()
		print("[BN] trained: instances=%d cpt_rows=%d nodes=%d" % [instances.size(), row_count, nodes.size()])
func debug_dump_node(name: String) -> void:
	if not DEBUG_VERIFY:
		return
	if not nodes.has(name):
		print("[BN] dump: missing node: %s" % name)
		return
	var node: BNNode = nodes[name]
	var keys := node.cpt.keys()
	var first_key: Variant = null
	if not keys.is_empty():
		first_key = keys[0]
	var sample := []
	if first_key != null and node.cpt.has(first_key):
		sample = node.cpt[first_key]
	print("[BN] node=%s rows=%d sample_row=%s" % [name, node.cpt.size(), str(sample)])

func _build_default_structure() -> void:
	# Fallback if no training data
	nodes.clear()
	print("WARNING: Using default BN structure (no training data)")

## Generate architectural program by sampling from network
func sample(req: Dictionary) -> ArchitecturalProgram:
	# Use BN if trained, otherwise fallback to legacy method
	if not nodes.is_empty():
		return _sample_from_bn(req)
	else:
		return _sample_legacy(req)

## Sample from trained Bayesian network
func _sample_from_bn(req: Dictionary) -> ArchitecturalProgram:
	var program := ArchitecturalProgram.new()
	program.footprint_m = req.get("footprint", Vector2i(16, 12))
	
	var rng := _rng()
	var sampled := {}  # feature -> value
	
	# 🔥 FIX: Dynamically build topological order from actual BN structure
	var order: Array[String] = _topological_sort()
	
	# Fix observed variables from requirements
        if req.has("bedrooms"):
                var forced_beds := int(req["bedrooms"])
                sampled["bedrooms"] = forced_beds
                sampled["count_Bedroom"] = forced_beds
                sampled["Bedroom_exists"] = 1 if forced_beds > 0 else 0
        if req.has("bathrooms"):
                var forced_baths := int(req["bathrooms"])
                sampled["bathrooms"] = forced_baths
                sampled["count_Bathroom"] = forced_baths
                sampled["Bathroom_exists"] = 1 if forced_baths > 0 else 0
	if req.has("sq_m2"):
		var sqft := float(req["sq_m2"])
		var area_edges: PackedFloat64Array = schema_edges.get("total_m2_edges", PackedFloat64Array())
		sampled["total_m2_bin"] = _bin_index_for_value(sqft, area_edges)

	# Sample ALL nodes in topological order
	for node_name in order:
		if sampled.has(node_name):
			continue

		if not nodes.has(node_name):
			continue

		var node: BNNode = nodes[node_name]
		var parent_vals := {}
		for p in node.parents:
			parent_vals[p] = sampled.get(p)

		sampled[node_name] = node.sample_given(parent_vals, rng)

	
	# Convert sampled values to architectural program
	return _sampled_to_program(sampled, req)

## Compute topological sort of BN nodes (Kahn's algorithm)
func _topological_sort() -> Array[String]:
	var in_degree := {}
	var adj_list := {}
	
	# Initialize
	for node_name in nodes.keys():
		in_degree[node_name] = 0
		adj_list[node_name] = []
	
	# Build adjacency list and count in-degrees
	for node_name in nodes.keys():
		var node: BNNode = nodes[node_name]
		for parent in node.parents:
			if not adj_list.has(parent):
				continue
			adj_list[parent].append(node_name)
			in_degree[node_name] += 1
	
	# Find all nodes with in-degree 0
	var queue: Array[String] = []
	for node_name in in_degree.keys():
		if in_degree[node_name] == 0:
			queue.append(node_name)
	
	# Process queue
	var result: Array[String] = []
	while not queue.is_empty():
		var current := queue.pop_front()
		result.append(current)
		
		for neighbor in adj_list.get(current, []):
			in_degree[neighbor] -= 1
			if in_degree[neighbor] == 0:
				queue.append(neighbor)
	
	return result

func _sampled_to_program(sampled: Dictionary, req: Dictionary) -> ArchitecturalProgram:
	var program := ArchitecturalProgram.new()
	program.footprint_m = req.get("footprint", Vector2i(16, 12))

	# 🔥 FIX: Define ALL variables at the START of the function
	var beds := int(sampled.get("count_Bedroom", sampled.get("bedrooms", 3)))
	var baths := int(sampled.get("count_Bathroom", sampled.get("bathrooms", 2)))
	var floors := int(req.get("floors", 1))  # ✅ MUST be defined HERE at the top
	var area_edges: PackedFloat64Array = schema_edges.get("total_m2_edges", PackedFloat64Array())
	var requested_sqft := float(req.get("sq_m2", -1.0))
	var sqft_bin := int(sampled.get("total_m2_bin", _bin_index_for_value(requested_sqft, area_edges) if requested_sqft >= 0.0 else 0))
	var sqft := requested_sqft if requested_sqft >= 0.0 else _bin_midpoint(sqft_bin, area_edges)
	if sqft <= 0.0:
		sqft = 160.0

	var rooms: Array[Dictionary] = []

	# Room type templates with area/aspect PDFs
	var room_templates := {
		"Entry": {"area_mean": 6.0, "area_sigma": 1.5, "aspect_mean": 1.2, "aspect_sigma": 0.2, "window": true},
		"Living": {"area_mean": 28.0, "area_sigma": 6.0, "aspect_mean": 1.5, "aspect_sigma": 0.4, "window": true},
		"Kitchen": {"area_mean": 16.0, "area_sigma": 3.0, "aspect_mean": 1.1, "aspect_sigma": 0.2, "window": true},
		"Bedroom": {"area_mean": 12.0, "area_sigma": 2.5, "aspect_mean": 1.4, "aspect_sigma": 0.3, "window": true},
		"Bathroom": {"area_mean": 5.0, "area_sigma": 1.2, "aspect_mean": 1.2, "aspect_sigma": 0.2, "window": true},
		"Dining": {"area_mean": 14.0, "area_sigma": 3.0, "aspect_mean": 1.3, "aspect_sigma": 0.3, "window": true},
		"Office": {"area_mean": 10.0, "area_sigma": 2.0, "aspect_mean": 1.3, "aspect_sigma": 0.2, "window": true},
		"Study": {"area_mean": 10.0, "area_sigma": 2.0, "aspect_mean": 1.3, "aspect_sigma": 0.2, "window": true},
		"Pantry": {"area_mean": 3.0, "area_sigma": 0.8, "aspect_mean": 1.0, "aspect_sigma": 0.1, "window": false},
		"Laundry": {"area_mean": 4.5, "area_sigma": 1.0, "aspect_mean": 1.1, "aspect_sigma": 0.2, "window": false},
		"Closet": {"area_mean": 2.5, "area_sigma": 0.6, "aspect_mean": 1.0, "aspect_sigma": 0.1, "window": false},
		"Hall": {"area_mean": 8.0, "area_sigma": 2.0, "aspect_mean": 3.0, "aspect_sigma": 1.0, "window": false},
		"Porch": {"area_mean": 7.0, "area_sigma": 1.5, "aspect_mean": 2.0, "aspect_sigma": 0.5, "window": false},
		"Garage": {"area_mean": 20.0, "area_sigma": 4.0, "aspect_mean": 1.8, "aspect_sigma": 0.3, "window": false},
		"Stair": {"area_mean": 4.0, "area_sigma": 1.0, "aspect_mean": 2.5, "aspect_sigma": 0.5, "window": false},
		"Utility": {"area_mean": 3.5, "area_sigma": 0.8, "aspect_mean": 1.0, "aspect_sigma": 0.1, "window": false}
	}
	
	# 🔥 FIX: Force Hall generation for multi-bedroom/multi-floor layouts
	var force_hall := beds >= 3 or floors > 1  # floors is defined above
	var hall_exists := _exists_flag(sampled, "Hall")
	if force_hall and not hall_exists:
		print("⚠️ Forcing Hall generation (beds=%d, floors=%d)" % [beds, floors])
		sampled["Hall_exists"] = 1
		hall_exists = true

	# Generate rooms based on BN decisions
	for node_name in nodes.keys():
		if node_name.ends_with("_exists"):
			var room_type: String = node_name.trim_suffix("_exists")
			if int(sampled.get(node_name, 0)) == 0:
				continue

			var tmpl := room_templates.get(room_type, {"area_mean": 8.0, "area_sigma": 2.0, "aspect_mean": 1.2, "aspect_sigma": 0.2, "window": true})

				if room_type == "Bedroom":
					for i in range(beds):
						var floor_num := 0
						if floors > 1 and i > 0:  # floors available
							floor_num = 1
						rooms.append({
							"id": "bed_%d" % (i + 1), "type": "Bedroom", "floor": floor_num, "needs_window": tmpl["window"],
							"area_pdf": {"mean": tmpl["area_mean"], "sigma": tmpl["area_sigma"]},
							"aspect_pdf": {"mean": tmpl["aspect_mean"], "sigma": tmpl["aspect_sigma"]}
						})
				elif room_type == "Bathroom":
					for i in range(baths):
						var floor_num := 0
						if floors > 1 and i > 0:  # floors available
							floor_num = 1
						rooms.append({
							"id": "bath_%d" % (i + 1), "type": "Bathroom", "floor": floor_num, "needs_window": tmpl["window"],
							"area_pdf": {"mean": tmpl["area_mean"], "sigma": tmpl["area_sigma"]},
							"aspect_pdf": {"mean": tmpl["aspect_mean"], "sigma": tmpl["aspect_sigma"]}
						})
				elif room_type == "Hall":
					# ✅ LINE 326 FIX: floors is now in scope
					var hall_floor := 0 if floors == 1 else 1  # Upper floor for multi-story
					rooms.append({
						"id": "hall", "type": "Hall", "floor": hall_floor, "needs_window": false,
						"area_pdf": {"mean": 8.0, "sigma": 2.0},
						"aspect_pdf": {"mean": 2.5, "sigma": 0.5}
					})
				elif room_type == "Stair":
					if floors > 1:  # floors available
						for f in range(floors):
							rooms.append({
								"id": "stair_%d" % f, "type": "Stair", "floor": f, "needs_window": false,
								"area_pdf": {"mean": 4.0, "sigma": 1.0},
								"aspect_pdf": {"mean": 2.5, "sigma": 0.5}
							})
				else:
					rooms.append({
						"id": room_type.to_lower(), "type": room_type, "floor": 0, "needs_window": tmpl["window"],
						"area_pdf": {"mean": tmpl["area_mean"], "sigma": tmpl["area_sigma"]},
						"aspect_pdf": {"mean": tmpl["aspect_mean"], "sigma": tmpl["aspect_sigma"]}
					})

	program.rooms = rooms

	# Edge generation with Hall support
	var edges: Array[Dictionary] = []
	var kitchen_living_exist := _adj_exist_value(sampled, "Kitchen|Living")
	if kitchen_living_exist > 0:
		edges.append({"a_id": "living", "b_id": "kitchen", "type": "open"})

	edges.append({"a_id": "entry", "b_id": "living", "type": "door"})
	
	var has_hall := rooms.any(func(r): return r["type"] == "Hall")
	
	if has_hall:
		for i in range(beds):
			if i == 0 and beds > 1:
				edges.append({"a_id": "living", "b_id": "bed_%d" % (i + 1), "type": "door"})
			else:
				edges.append({"a_id": "hall", "b_id": "bed_%d" % (i + 1), "type": "door"})
		
		if floors > 1:  # floors available
			edges.append({"a_id": "hall", "b_id": "stair_1", "type": "door"})
			edges.append({"a_id": "entry", "b_id": "stair_0", "type": "door"})
		else:
			edges.append({"a_id": "entry", "b_id": "hall", "type": "door"})
		
		for i in range(1, baths):
			edges.append({"a_id": "hall", "b_id": "bath_%d" % (i + 1), "type": "door"})
	else:
		for i in range(beds):
			edges.append({"a_id": "living", "b_id": "bed_%d" % (i + 1), "type": "door"})
	
	if baths > 0:
		edges.append({"a_id": "bed_1", "b_id": "bath_1", "type": "door"})
	
	if _exists_flag(sampled, "Dining"):
		edges.append({"a_id": "living", "b_id": "dining", "type": "open"})
		edges.append({"a_id": "dining", "b_id": "kitchen", "type": "open"})
	
	if _exists_flag(sampled, "Pantry"):
		edges.append({"a_id": "kitchen", "b_id": "pantry", "type": "door"})
	
	if _exists_flag(sampled, "Laundry"):
		edges.append({"a_id": "kitchen", "b_id": "laundry", "type": "door"})
	
	if _exists_flag(sampled, "Office") or _exists_flag(sampled, "Study"):
		edges.append({"a_id": "entry", "b_id": "office", "type": "door"})
	
	if _exists_flag(sampled, "Garage"):
		edges.append({"a_id": "entry", "b_id": "garage", "type": "door"})
	
	if _exists_flag(sampled, "Porch"):
		edges.append({"a_id": "living", "b_id": "porch", "type": "door"})

	program.edges = edges
	
	print("✓ Generated program: %d rooms, %d edges, %d floors" % [rooms.size(), edges.size(), floors])
	return program

## Legacy sampling method (fallback)
func _sample_legacy(req: Dictionary) -> ArchitecturalProgram:
	var program := ArchitecturalProgram.new()
	program.footprint_m = req.get("footprint", Vector2i(16, 12))
	var area := float(req.get("sq_m2", program.footprint_m.x * program.footprint_m.y))
	var bucket := _bucket_sq_m2(area)
	var bed_options: Array = P_beds.get(bucket, [3, 4])
	var beds := int(req.get("bedrooms", bed_options[_randi() % bed_options.size()]))
	var baths := int(req.get("bathrooms", P_baths_given_beds.get(beds, max(1, beds - 1))))
	var floors := int(req.get("floors", 1))

	var rooms: Array[Dictionary] = [
		{
			"id": "entry", "type": "Entry", "floor": 0, "needs_window": true,
			"area_pdf": {"mean": 6.0,  "sigma": 1.5},
			"aspect_pdf": {"mean": 1.2, "sigma": 0.2}
		},
		{
			"id": "living", "type": "Living", "floor": 0, "needs_window": true,
			"area_pdf": {"mean": 28.0, "sigma": 6.0},
			"aspect_pdf": {"mean": 1.5,  "sigma": 0.4}
		},
		{
			"id": "kitchen", "type": "Kitchen", "floor": 0, "needs_window": true,
			"area_pdf": {"mean": 16.0, "sigma": 3.0},
			"aspect_pdf": {"mean": 1.1,  "sigma": 0.2}
		},
	]

	for i in range(beds):
		rooms.append({
			"id": "bed_%d" % (i + 1),
			"type": "Bedroom",
			"floor": 0,
			"needs_window": true,
			"area_pdf": {"mean": 12.0, "sigma": 2.5},
			"aspect_pdf": {"mean": 1.4, "sigma": 0.3},
		})

	for i in range(baths):
		rooms.append({
			"id": "bath_%d" % (i + 1),
			"type": "Bathroom",
			"floor": 0,
			"needs_window": true,
			"area_pdf": {"mean": 5.0, "sigma": 1.2},
			"aspect_pdf": {"mean": 1.2, "sigma": 0.2},
		})

	if floors > 1:
		var moved := 0
		for i in range(rooms.size()):
			if moved * 2 >= beds:
				break
			var info: Dictionary = rooms[i]
			if info.get("type", "") == "Bedroom":
				info["floor"] = 1
				rooms[i] = info
				moved += 1

	var edges: Array[Dictionary] = [
		{"a_id": "entry",  "b_id": "living",  "type": "door"},
		{"a_id": "living", "b_id": "kitchen", "type": "open"},
	]
	for i in range(beds):
		edges.append({"a_id": "living", "b_id": "bed_%d" % (i + 1), "type": "door"})

	program.rooms = rooms
	program.edges = edges
	return program

func logp_size(label: String, area: float, aspect: float) -> float:
	var params := _size_params(label)
	var p_area := _gauss_logpdf(area, params["area_mean"], params["area_sigma"])
	var p_aspect := _gauss_logpdf(aspect, params["aspect_mean"], params["aspect_sigma"])
	return p_area + p_aspect

func _size_params(label: String) -> Dictionary:
	match label:
		"Living":
			return {"area_mean": 28.0, "area_sigma": 6.0, "aspect_mean": 1.5, "aspect_sigma": 0.4}
		"Kitchen":
			return {"area_mean": 16.0, "area_sigma": 3.0, "aspect_mean": 1.1, "aspect_sigma": 0.2}
		"Bedroom":
			return {"area_mean": 12.0, "area_sigma": 2.5, "aspect_mean": 1.4, "aspect_sigma": 0.3}
		"Bathroom":
			return {"area_mean": 5.0, "area_sigma": 1.2, "aspect_mean": 1.2, "aspect_sigma": 0.2}
		"Entry":
			return {"area_mean": 6.0, "area_sigma": 1.5, "aspect_mean": 1.2, "aspect_sigma": 0.2}
		"Dining":
			return {"area_mean": 14.0, "area_sigma": 3.0, "aspect_mean": 1.3, "aspect_sigma": 0.3}
		"Office", "Study":
			return {"area_mean": 10.0, "area_sigma": 2.0, "aspect_mean": 1.3, "aspect_sigma": 0.2}
		"Hall":
			return {"area_mean": 8.0, "area_sigma": 2.0, "aspect_mean": 2.5, "aspect_sigma": 0.5}
		_:
			return {"area_mean": 10.0, "area_sigma": 4.0, "aspect_mean": 1.3, "aspect_sigma": 0.3}

func _gauss_logpdf(x: float, mu: float, sigma: float) -> float:
	sigma = max(0.001, sigma)
	var diff := x - mu
	return -0.5 * ((diff * diff) / (sigma * sigma) + log(2.0 * PI * sigma * sigma))

# Adjacency prior: probability that two room types should be adjacent
func p_adj(a: String, b: String) -> float:
        var sorted := [a.to_lower(), b.to_lower()]
        sorted.sort()
        var k := "%s|%s" % [sorted[0], sorted[1]]
        var priors := {
		"entry|living": 0.95,
		"kitchen|living": 0.9,
		"living|living": 0.1,
		"bedroom|bathroom": 0.8,
		"bedroom|living": 0.7,
		"bathroom|bathroom": 0.1,
		"entry|kitchen": 0.3,
		"entry|bedroom": 0.1,
		"kitchen|bedroom": 0.2,
		"bedroom|hall": 0.9,  # 🔥 NEW
		"hall|bathroom": 0.8,  # 🔥 NEW
		"hall|stair": 0.95,    # 🔥 NEW
		"kitchen|pantry": 0.8, # 🔥 NEW
		"kitchen|laundry": 0.7,# 🔥 NEW
        }
        return float(priors.get(k, 0.2))

func _adj_exist_key(label: String) -> String:
	return "adj_exist:%s" % label

func _adj_exist_value(sampled: Dictionary, label: String) -> int:
	var key := _adj_exist_key(label)
	if sampled.has(key):
		return int(sampled.get(key, 0))
	var legacy_key := "adj_%s_exist" % label
	return int(sampled.get(legacy_key, 0))

func _exists_flag(sampled: Dictionary, room_type: String) -> bool:
	var key := "%s_exists" % room_type
	return int(sampled.get(key, 0)) == 1

static func _bin_domain(edges: PackedFloat64Array) -> Array:
	var count := edges.size() + 1
	var domain: Array = []
	for i in range(count):
		domain.append(i)
	return domain

static func _footprint_domain(w_edges: PackedFloat64Array, d_edges: PackedFloat64Array) -> Array:
	var w_bins := w_edges.size() + 1
	var d_bins := d_edges.size() + 1
	var domain: Array = []
	for w in range(w_bins):
		for d in range(d_bins):
			domain.append(w * d_bins + d)
	return domain

static func _count_bin_domain() -> Array:
	return [0, 1, 2, 3]

static func _collect_unique_counts(instances: Array, room_type: String) -> Array:
	var values := {}
	for inst in instances:
		var dict_inst := _instance_to_dict(inst)
		if dict_inst.is_empty():
				continue
		var counts_variant := dict_inst.get("room_counts", {})
		var count := 0
		if counts_variant is Dictionary and (counts_variant as Dictionary).has(room_type):
				count = int((counts_variant as Dictionary)[room_type])
		else:
				count = int(dict_inst.get("count_%s" % room_type, 0))
		values[count] = true
	var result: Array = []
	for k in values.keys():
		result.append(int(k))
	result.sort()
	return result

static func _collect_unique_adj_pair_labels(instances: Array) -> Array[String]:
	var labels := {}
	for inst in instances:
		var dict_inst := _instance_to_dict(inst)
		if dict_inst.is_empty():
				continue
		var summary_variant := dict_inst.get("adj_summary", {})
		if summary_variant is Dictionary:
				for label in (summary_variant as Dictionary).keys():
						if String(label) != "":
								labels[String(label)] = true
				continue
		for pair in dict_inst.get("adj_pairs", []):
				if not (pair is Dictionary):
						continue
				var label := String(pair.get("pair", ""))
				if label == "":
						continue
				labels[label] = true
	var out: Array[String] = []
	for label in labels.keys():
		out.append(label)
	out.sort()
	return out

static func _instance_to_dict(inst) -> Dictionary:
	if inst is TrainingData.ProgramInstance:
		return TrainingData._program_to_dict(inst)
	if typeof(inst) == TYPE_DICTIONARY:
		return inst
	return {}

static func _bin_index_for_value(value: float, edges: PackedFloat64Array) -> int:
	for i in range(edges.size()):
		if value < edges[i]:
			return i
	return edges.size()

static func _bin_midpoint(bin_idx: int, edges: PackedFloat64Array) -> float:
	if edges.is_empty():
		return 0.0
	var lower := 0.0
	if bin_idx > 0:
		lower = edges[min(bin_idx - 1, edges.size() - 1)]
	var upper := edges[min(bin_idx, edges.size() - 1)] if bin_idx < edges.size() else edges[-1] + 40.0
	if upper <= lower:
		upper = lower + 1.0
	return (lower + upper) * 0.5
## Extract all unique room types from training data
func _extract_unique_room_types(instances: Array) -> Array[String]:
	var room_types := {}
	for inst in instances:
		if not (inst is TrainingData.ProgramInstance):
			continue
		var prog: TrainingData.ProgramInstance = inst
		for rm in prog.rooms:
			room_types[rm.type] = true
	var result: Array[String] = []
	for rt in room_types.keys():
		result.append(rt)
	result.sort()
	return result
