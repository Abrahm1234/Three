extends Node
class_name ProgramBN

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

var P_beds := {
	"small": [2, 3],
	"med": [3, 4],
	"large": [4, 5],
}
var P_baths_given_beds := {2: 1, 3: 2, 4: 3, 5: 3}

func _has_node(name: String) -> bool:
	return nodes.has(name)

func _value_truthy(v: Variant) -> bool:
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return int(v) != 0
		TYPE_STRING:
			var s := String(v)
			return s != "" and s.to_lower() != "false"
		_:
			return v != null

func _enforce_bridge_constraints(sampled: Dictionary) -> void:
	if not _has_node("Hall_exists"):
		return
	if _value_truthy(sampled.get("Entry_exists", false)) or _value_truthy(sampled.get("Living_exists", false)):
		sampled["Hall_exists"] = true

func _edge_cache_key(a_id: String, b_id: String, typ: String) -> String:
	if a_id <= b_id:
		return "%s|%s|%s" % [a_id, b_id, typ]
	return "%s|%s|%s" % [b_id, a_id, typ]

func _append_edge(edges: Array[Dictionary], cache: Dictionary, a_id: String, b_id: String, typ: String) -> void:
	if a_id == "" or b_id == "":
		return
	var key := _edge_cache_key(a_id, b_id, typ)
	if cache.has(key):
		return
	edges.append({"a_id": a_id, "b_id": b_id, "type": typ})
	cache[key] = true

func configure_rng(ctx: RandomCtx) -> void:
	rng_ctx = ctx

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
func train(data: TrainingData, floors: int = 1) -> void:
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
	
	_build_structure_from_data(instances)
	_learn_parameters(instances)

## Build network structure (simplified)
func _build_structure_from_data(instances: Array) -> void:
	nodes.clear()

	# Root: Total Square Footage
	var sqft_node := BNNode.new()
	sqft_node.name = "total_sqft"
	sqft_node.domain = ["small", "medium", "large"]  # Discretized
	nodes["total_sqft"] = sqft_node

	# Bedrooms depends on sqft
	var bed_node := BNNode.new()
	bed_node.name = "bedrooms"
	bed_node.domain = [2, 3, 4, 5]
	bed_node.parents = ["total_sqft"]
	nodes["bedrooms"] = bed_node

	# Bathrooms depends on bedrooms
	var bath_node := BNNode.new()
	bath_node.name = "bathrooms"
	bath_node.domain = [1, 2, 3, 4]
	bath_node.parents = ["bedrooms"]
	nodes["bathrooms"] = bath_node

	# Room existence nodes - dynamically discover all room types from training data
	var discovered_room_types := _extract_unique_room_types(instances)
	print("✓ Discovered %d room types: %s" % [discovered_room_types.size(), discovered_room_types])

	for room_type in discovered_room_types:
		var exists_node := BNNode.new()
		exists_node.name = "%s_exists" % room_type
		exists_node.domain = [true, false]
		exists_node.parents = ["bedrooms", "total_sqft"]  # Both influence existence
		nodes[exists_node.name] = exists_node

	# Adjacency nodes (example: Living-Kitchen)
	var adj_lk := BNNode.new()
	adj_lk.name = "adj_Living_Kitchen"
	adj_lk.domain = ["none", "door", "open"]
	adj_lk.parents = ["Living_exists", "Kitchen_exists"]
	nodes[adj_lk.name] = adj_lk

## Learn CPT parameters from data
func _learn_parameters(instances: Array) -> void:
	for node_name in nodes.keys():
		var node: BNNode = nodes[node_name]
		var counts := {}  # key -> {value -> count}
		
		for inst in instances:
			if not (inst is TrainingData.ProgramInstance):
				continue
			var prog: TrainingData.ProgramInstance = inst
			
			# Extract parent values
			var parent_vals := {}
			for parent in node.parents:
				parent_vals[parent] = _extract_feature(prog, parent)
			
			var key := node._cpt_key(parent_vals)
			if not counts.has(key):
				counts[key] = {}
			
			var value = _extract_feature(prog, node_name)
			if not counts[key].has(value):
				counts[key][value] = 0
			counts[key][value] += 1
		
		# Convert counts to probabilities
		for key in counts.keys():
			var total := 0
			for v in counts[key].keys():
				total += counts[key][v]
			
			var probs: Array = []
			for domain_val in node.domain:
				var count: int = counts[key].get(domain_val, 0)
				probs.append(float(count) / max(1, total))
			
			node.cpt[key] = probs

func _extract_feature(prog: TrainingData.ProgramInstance, feature: String) -> Variant:
	match feature:
		"total_sqft":
			if prog.total_sqft < 120: return "small"
			elif prog.total_sqft < 200: return "medium"
			else: return "large"
		"bedrooms": return prog.bedrooms
		"bathrooms": return prog.bathrooms
		_:
			if feature.ends_with("_exists"):
				var room_type := feature.replace("_exists", "")
				for r in prog.rooms:
					if r.get("type") == room_type:
						return true
				return false
	return null

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
		sampled["bedrooms"] = int(req["bedrooms"])
	if req.has("bathrooms"):
		sampled["bathrooms"] = int(req["bathrooms"])
	if req.has("sq_m2"):
		var sqft := float(req["sq_m2"])
		if sqft < 120: sampled["total_sqft"] = "small"
		elif sqft < 200: sampled["total_sqft"] = "medium"
		else: sampled["total_sqft"] = "large"
	
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
	_enforce_bridge_constraints(sampled)
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
	var beds := int(sampled.get("bedrooms", 3))
	var baths := int(sampled.get("bathrooms", 2))
	var floors := int(req.get("floors", 1))  # ✅ MUST be defined HERE at the top
	var sqft := float(req.get("sq_m2", 160.0))

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
	var force_hall := beds >= 3 or floors > 1  # ✅ floors is now defined above
	if force_hall and not sampled.get("Hall_exists", false):
		print("⚠️ Forcing Hall generation (beds=%d, floors=%d)" % [beds, floors])
		sampled["Hall_exists"] = true

	# Generate rooms based on BN decisions
	for node_name in nodes.keys():
		if node_name.ends_with("_exists"):
			var room_type: String = node_name.trim_suffix("_exists")
			if sampled.get(node_name, false):
				var tmpl := room_templates.get(room_type, {"area_mean": 8.0, "area_sigma": 2.0, "aspect_mean": 1.2, "aspect_sigma": 0.2, "window": true})

				if room_type == "Bedroom":
					for i in range(beds):
						var floor_num := 0
						if floors > 1 and i > 0:  # ✅ floors is available
							floor_num = 1
						rooms.append({
							"id": "bed_%d" % (i + 1), "type": "Bedroom", "floor": floor_num, "needs_window": tmpl["window"],
							"area_pdf": {"mean": tmpl["area_mean"], "sigma": tmpl["area_sigma"]},
							"aspect_pdf": {"mean": tmpl["aspect_mean"], "sigma": tmpl["aspect_sigma"]}
						})
				elif room_type == "Bathroom":
					for i in range(baths):
						var floor_num := 0
						if floors > 1 and i > 0:  # ✅ floors is available
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
					if floors > 1:  # ✅ floors is available
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
	var edge_cache := {}


	var type_to_ids := {}
	for info in rooms:
		var typ := String(info.get("type", ""))
		if typ == "":
			continue
		if not type_to_ids.has(typ):
			type_to_ids[typ] = []
		type_to_ids[typ].append(String(info.get("id", "")))


	var entry_ids: Array = type_to_ids.get("Entry", [])
	var hall_ids: Array = type_to_ids.get("Hall", [])
	var living_ids: Array = type_to_ids.get("Living", [])
	var kitchen_ids: Array = type_to_ids.get("Kitchen", [])
	var bedroom_ids: Array = type_to_ids.get("Bedroom", [])
	var bath_ids: Array = type_to_ids.get("Bathroom", [])
	var stair_ids: Array = type_to_ids.get("Stair", [])
	var dining_ids: Array = type_to_ids.get("Dining", [])
	var pantry_ids: Array = type_to_ids.get("Pantry", [])
	var laundry_ids: Array = type_to_ids.get("Laundry", [])
	var office_ids: Array = type_to_ids.get("Office", [])
	var study_ids: Array = type_to_ids.get("Study", [])
	var garage_ids: Array = type_to_ids.get("Garage", [])
	var porch_ids: Array = type_to_ids.get("Porch", [])


	var entry_id := entry_ids.size() > 0 ? String(entry_ids[0]) : ""
	var hall_id := hall_ids.size() > 0 ? String(hall_ids[0]) : ""
	var living_id := living_ids.size() > 0 ? String(living_ids[0]) : ""
	var kitchen_id := kitchen_ids.size() > 0 ? String(kitchen_ids[0]) : ""


	if entry_id != "" and living_id != "":
		_append_edge(edges, edge_cache, entry_id, living_id, "door")
	if entry_id != "" and hall_id != "":
		_append_edge(edges, edge_cache, entry_id, hall_id, "door")
	if hall_id != "" and living_id != "":
		_append_edge(edges, edge_cache, hall_id, living_id, "door")


	var adj_type := String(sampled.get("adj_Living_Kitchen", "open"))
	if living_id != "" and kitchen_id != "" and adj_type != "none":
		_append_edge(edges, edge_cache, living_id, kitchen_id, adj_type)


	if hall_id != "":
		for id in bedroom_ids:
			_append_edge(edges, edge_cache, hall_id, String(id), "door")
	elif living_id != "":
		for id in bedroom_ids:
			_append_edge(edges, edge_cache, living_id, String(id), "door")
	elif entry_id != "":
		for id in bedroom_ids:
			_append_edge(edges, edge_cache, entry_id, String(id), "door")


	if floors > 1 and entry_id != "" and stair_ids.size() > 0:
		_append_edge(edges, edge_cache, entry_id, String(stair_ids[0]), "door")
	if floors > 1 and hall_id != "" and stair_ids.size() > 1:
		_append_edge(edges, edge_cache, hall_id, String(stair_ids[1]), "door")
	elif floors > 1 and hall_id != "" and stair_ids.size() > 0:
		_append_edge(edges, edge_cache, hall_id, String(stair_ids[0]), "door")


	if bedroom_ids.size() > 0 and bath_ids.size() > 0:
		_append_edge(edges, edge_cache, String(bedroom_ids[0]), String(bath_ids[0]), "door")
	if hall_id != "":
		for id in bath_ids:
			_append_edge(edges, edge_cache, hall_id, String(id), "door")
	else:
		var anchor := living_id
		if anchor == "" and bedroom_ids.size() > 0:
			anchor = String(bedroom_ids[0])
		elif anchor == "" and entry_id != "":
			anchor = entry_id
		if anchor != "":
			for id in bath_ids:
				_append_edge(edges, edge_cache, anchor, String(id), "door")


	if dining_ids.size() > 0:
		var dining_id := String(dining_ids[0])
		if living_id != "":
			_append_edge(edges, edge_cache, living_id, dining_id, "open")
		if kitchen_id != "":
			_append_edge(edges, edge_cache, dining_id, kitchen_id, "open")


	if pantry_ids.size() > 0 and kitchen_id != "":
		_append_edge(edges, edge_cache, kitchen_id, String(pantry_ids[0]), "door")
	if laundry_ids.size() > 0 and kitchen_id != "":
		_append_edge(edges, edge_cache, kitchen_id, String(laundry_ids[0]), "door")


	var study_anchor_ids: Array = office_ids.size() > 0 ? office_ids : study_ids
	if entry_id != "" and study_anchor_ids.size() > 0:
		_append_edge(edges, edge_cache, entry_id, String(study_anchor_ids[0]), "door")


	if garage_ids.size() > 0 and entry_id != "":
		_append_edge(edges, edge_cache, entry_id, String(garage_ids[0]), "door")
	if porch_ids.size() > 0 and living_id != "":
		_append_edge(edges, edge_cache, living_id, String(porch_ids[0]), "door")

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
