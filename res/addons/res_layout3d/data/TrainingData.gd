extends Resource
class_name TrainingData

## Represents a single training example for the Bayesian network
class ProgramInstance:
	var total_sqft: float
	var footprint: Vector2i
	var floors: int
	var bedrooms: int
	var bathrooms: int
	var rooms: Array[Dictionary] = []  # {type:String, area:float, aspect:float, floor:int}
	var adjacencies: Array[Dictionary] = []  # {a:String, b:String, type:String}

## Collection of training instances
var single_story: Array = []
var two_story: Array = []
var three_story: Array = []
var schema_labels: PackedStringArray = PackedStringArray()
var schema_adj_pairs: PackedStringArray = PackedStringArray()

const MIN_TYPE_FREQ := 50
const MIN_PAIR_FREQ := 25

static func _path_join(base: String, rel: String) -> String:
	if rel.is_absolute_path():
		return rel
	var clean_base := base.rstrip('/')
	var clean_rel := rel.lstrip('./')
	return "%s/%s" % [clean_base, clean_rel]

static func _load_manifest_lines(manifest_path: String) -> Array[String]:
	var lines: Array[String] = []
	if not FileAccess.file_exists(manifest_path):
		return lines
	var fa := FileAccess.open(manifest_path, FileAccess.READ)
	if fa == null:
		return lines
	while not fa.eof_reached():
		var line := fa.get_line().strip_edges()
		if line.is_empty():
			continue
		lines.append(line)
	fa.close()
	return lines

static func _resolve_manifest(dir_path: String) -> String:
	var candidates := [
		_path_join(dir_path, "manifest.jsonl"),
		_path_join(dir_path, "manifest.json"),
		_path_join(dir_path, "manifest.jsonl.txt"),
	]
	for p in candidates:
		if FileAccess.file_exists(p):
			return p
	return ""

static func _pair_key(a: String, b: String) -> String:
	var aa := a.strip_edges()
	var bb := b.strip_edges()
	if aa <= bb:
		return "%s|%s" % [aa, bb]
	return "%s|%s" % [bb, aa]

static func _room_label(entry: Dictionary) -> String:
	var label := String(entry.get("label", entry.get("type", "")))
	if label == "" and entry.has("category"):
		label = String(entry["category"])
	return label.capitalize()

static func _room_area(entry: Dictionary) -> float:
	var area := float(entry.get("area_m2", entry.get("area", 0.0)))
	if area <= 0.0 and entry.has("size"):
		var size := entry["size"]
		if typeof(size) == TYPE_DICTIONARY:
			var w := float(size.get("w", size.get("width", 0.0)))
			var h := float(size.get("h", size.get("height", 0.0)))
			if w > 0.0 and h > 0.0:
				area = w * h
	return area

static func _room_aspect(entry: Dictionary) -> float:
	var aspect := float(entry.get("aspect", entry.get("aspect_ratio", 0.0)))
	if aspect <= 0.0 and entry.has("size"):
		var size := entry["size"]
		if typeof(size) == TYPE_DICTIONARY:
			var w := float(size.get("w", size.get("width", 0.0)))
			var h := float(size.get("h", size.get("height", 0.0)))
			if w > 0.0 and h > 0.0:
				aspect = max(w, h) / max(0.001, min(w, h))
	if aspect <= 0.0:
		aspect = 1.0
	return aspect

static func _room_floor(entry: Dictionary, fallback: int = 0) -> int:
	if entry.has("floor"):
		return int(entry["floor"])
	if entry.has("level"):
		return int(entry["level"])
	return fallback

static func _collect_room_map(rooms: Array) -> Dictionary:
	var out := {}
	var idx := 0
	for r in rooms:
		if typeof(r) != TYPE_DICTIONARY:
			idx += 1
			continue
		var rid := String(r.get("id", r.get("room_id", idx)))
		if rid == "":
			rid = str(idx)
		out[rid] = r
		idx += 1
	return out

static func _edge_type(rec: Dictionary) -> String:
	var kind := String(rec.get("type", rec.get("relation", rec.get("edge_type", "door"))))
	if kind == "":
		kind = "door"
	return kind
static func load_resplan(dir_path: String) -> TrainingData:
	var data := TrainingData.new()
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_warning("[RESPLAN] Directory not found: %s" % dir_path)
		return data
	var manifest_path := _resolve_manifest(dir_path)
	if manifest_path == "":
		push_warning("[RESPLAN] Manifest not found under %s" % dir_path)
		return data
	var lines := _load_manifest_lines(manifest_path)
	if lines.is_empty():
		push_warning("[RESPLAN] Manifest empty: %s" % manifest_path)
		return data

	var plan_paths: Array[Dictionary] = []
	for line in lines:
		var parsed := JSON.parse_string(line)
		if typeof(parsed) != TYPE_DICTIONARY:
			continue
		var meta: Dictionary = parsed
		var rel := String(meta.get("file", meta.get("json", "")))
		if rel == "":
			continue
		rel = rel.replace("\\", "/")
		var plan_path := _path_join(dir_path, rel)
		if not FileAccess.file_exists(plan_path):
			continue
		plan_paths.append({"path": plan_path, "meta": meta})

	if plan_paths.is_empty():
		push_warning("[RESPLAN] No plan files resolved from manifest")
		return data

	print("[RESPLAN] loaded=%d manifest=%s" % [plan_paths.size(), manifest_path])

	var type_counts := {}
	var pair_counts := {}
	var instances: Array = []
	for rec in plan_paths:
		var plan_text := FileAccess.get_file_as_string(rec["path"])
		if plan_text == "":
			continue
		var plan_variant := JSON.parse_string(plan_text)
		if typeof(plan_variant) != TYPE_DICTIONARY:
			continue
		var plan_dict: Dictionary = plan_variant
		var inst := ProgramInstance.new()
		var meta: Dictionary = rec.get("meta", {})
		inst.total_sqft = float(meta.get("area_m2", meta.get("area", 0.0)))
		var fp_w := int(meta.get("w", meta.get("width", 0)))
		var fp_h := int(meta.get("h", meta.get("height", 0)))
		inst.footprint = Vector2i(fp_w, fp_h)
		inst.floors = int(meta.get("floors", plan_dict.get("floors", 1)))
		inst.bedrooms = 0
		inst.bathrooms = 0

		var rooms_array := plan_dict.get("rooms", plan_dict.get("room_list", []))
		if typeof(rooms_array) != TYPE_ARRAY:
			rooms_array = []
		var room_map := _collect_room_map(rooms_array)
		for rid in room_map.keys():
			var entry: Dictionary = room_map[rid]
			var label := _room_label(entry)
			if label == "":
				continue
			var area := _room_area(entry)
			var aspect := _room_aspect(entry)
			var floor_idx := _room_floor(entry)
			inst.rooms.append({
				"id": String(entry.get("id", rid)),
				"type": label,
				"area": area,
				"aspect": aspect,
				"floor": floor_idx,
			})
			var lower := label.to_lower()
			if lower.begins_with("bed"):
				inst.bedrooms += 1
			elif lower.begins_with("bath"):
				inst.bathrooms += 1
			type_counts[label] = type_counts.get(label, 0) + 1

		var adjacencies := plan_dict.get("adjacency", plan_dict.get("edges", plan_dict.get("connections", [])))
		if typeof(adjacencies) != TYPE_ARRAY:
			adjacencies = []
		for edge in adjacencies:
			if typeof(edge) != TYPE_DICTIONARY:
				continue
			var a_id := String(edge.get("a", edge.get("source", edge.get("from", ""))))
			var b_id := String(edge.get("b", edge.get("target", edge.get("to", ""))))
			if a_id == "" and edge.has("rooms"):
				var pair := edge["rooms"]
				if typeof(pair) == TYPE_ARRAY and pair.size() >= 2:
					a_id = String(pair[0])
					b_id = String(pair[1])
			if a_id == "" or b_id == "":
				continue
			if not room_map.has(a_id) or not room_map.has(b_id):
				continue
			var a_label := _room_label(room_map[a_id])
			var b_label := _room_label(room_map[b_id])
			if a_label == "" or b_label == "":
				continue
			var edge_type := _edge_type(edge)
			inst.adjacencies.append({
				"a": a_label,
				"b": b_label,
				"type": edge_type,
			})
			var pk := _pair_key(a_label, b_label)
			pair_counts[pk] = pair_counts.get(pk, 0) + 1

		if inst.rooms.is_empty():
			continue
		if inst.total_sqft <= 0.0:
			for rm in inst.rooms:
				inst.total_sqft += float(rm.get("area", 0.0))
		instances.append(inst)
		match inst.floors:
			1:
				data.single_story.append(inst)
			2:
				data.two_story.append(inst)
			3:
				data.three_story.append(inst)
			_:
				data.single_story.append(inst)

	var allowed_types := {}
	for label in type_counts.keys():
		if type_counts[label] >= MIN_TYPE_FREQ:
			allowed_types[String(label)] = true

	var allowed_pairs := {}
	for pk in pair_counts.keys():
		if pair_counts[pk] >= MIN_PAIR_FREQ:
			allowed_pairs[String(pk)] = true

	var after_type := 0
	var after_pair := 0
	for inst in instances:
		var has_type := false
		for rm in inst.rooms:
			if allowed_types.has(String(rm.get("type", ""))):
				has_type = true
				break
		if has_type:
			after_type += 1
			var has_pair := false
			for edge in inst.adjacencies:
				var pk := _pair_key(String(edge.get("a", "")), String(edge.get("b", "")))
				if allowed_pairs.has(pk):
					has_pair = true
					break
			if has_pair:
				after_pair += 1

	var label_list: Array[String] = []
	for label in allowed_types.keys():
		label_list.append(String(label))
	label_list.sort()
	data.schema_labels = PackedStringArray(label_list)

	var pair_list: Array[String] = []
	for pk in allowed_pairs.keys():
		pair_list.append(String(pk))
	pair_list.sort()
	data.schema_adj_pairs = PackedStringArray(pair_list)

	print("[RESPLAN] raw=%d after_min_type=%d after_min_pair=%d" % [instances.size(), after_type, after_pair])
	return data

## Create dataset based on real-world architectural programs
## Data inspired by "Essential House Plan Collection" by Home Planners (cited in paper)
static func create_default() -> TrainingData:
	var data := TrainingData.new()
	
	# ========================================
	# SINGLE-STORY PROGRAMS (40 INSTANCE
	# ========================================
	
	# Small cottage (900-1200 sqft)
	for i in range(10):
		var prog := ProgramInstance.new()
		prog.floors = 1
		prog.bedrooms = 2
		prog.bathrooms = 1
		prog.total_sqft = randf_range(90, 120)
		prog.footprint = Vector2i(randi_range(10, 14), randi_range(8, 12))
		
		prog.rooms = [
			{"type": "Entry", "area": randf_range(4, 6), "aspect": randf_range(1.0, 1.3), "floor": 0},
			{"type": "Living", "area": randf_range(18, 25), "aspect": randf_range(1.3, 1.7), "floor": 0},
			{"type": "Kitchen", "area": randf_range(10, 14), "aspect": randf_range(1.0, 1.3), "floor": 0},
			{"type": "Bedroom", "area": randf_range(10, 13), "aspect": randf_range(1.2, 1.5), "floor": 0},
			{"type": "Bedroom", "area": randf_range(9, 12), "aspect": randf_range(1.2, 1.5), "floor": 0},
			{"type": "Bathroom", "area": randf_range(4, 6), "aspect": randf_range(1.0, 1.4), "floor": 0},
		]
		
		prog.adjacencies = [
			{"a": "Entry", "b": "Living", "type": "door"},
			{"a": "Living", "b": "Kitchen", "type": "open"},
			{"a": "Living", "b": "Bedroom", "type": "door"},
			{"a": "Kitchen", "b": "Bathroom", "type": "door"},
		]
		
		data.single_story.append(prog)
	
	# Medium ranch (1200-1600 sqft)
	for i in range(15):
		var prog := ProgramInstance.new()
		prog.floors = 1
		prog.bedrooms = 3
		prog.bathrooms = 2
		prog.total_sqft = randf_range(120, 160)
		prog.footprint = Vector2i(randi_range(14, 18), randi_range(10, 14))
		
		prog.rooms = [
			{"type": "Entry", "area": randf_range(5, 8), "aspect": randf_range(1.0, 1.4), "floor": 0},
			{"type": "Living", "area": randf_range(22, 30), "aspect": randf_range(1.4, 1.8), "floor": 0},
			{"type": "Dining", "area": randf_range(10, 14), "aspect": randf_range(1.1, 1.5), "floor": 0},
			{"type": "Kitchen", "area": randf_range(12, 16), "aspect": randf_range(1.0, 1.3), "floor": 0},
			{"type": "Bedroom", "area": randf_range(11, 14), "aspect": randf_range(1.2, 1.6), "floor": 0},
			{"type": "Bedroom", "area": randf_range(10, 13), "aspect": randf_range(1.2, 1.5), "floor": 0},
			{"type": "Bedroom", "area": randf_range(9, 12), "aspect": randf_range(1.2, 1.5), "floor": 0},
			{"type": "Bathroom", "area": randf_range(5, 7), "aspect": randf_range(1.0, 1.4), "floor": 0},
			{"type": "Bathroom", "area": randf_range(4, 6), "aspect": randf_range(1.0, 1.3), "floor": 0},
		]
		
		prog.adjacencies = [
			{"a": "Entry", "b": "Living", "type": "door"},
			{"a": "Living", "b": "Dining", "type": "open"},
			{"a": "Dining", "b": "Kitchen", "type": "open"},
			{"a": "Living", "b": "Bedroom", "type": "door"},
			{"a": "Bedroom", "b": "Bathroom", "type": "door"},
			{"a": "Kitchen", "b": "Bathroom", "type": "door"},
		]
		
		data.single_story.append(prog)
	
	# Large bungalow (1600-2200 sqft)
	for i in range(15):
		var prog := ProgramInstance.new()
		prog.floors = 1
		prog.bedrooms = 4
		prog.bathrooms = 3
		prog.total_sqft = randf_range(160, 220)
		prog.footprint = Vector2i(randi_range(16, 22), randi_range(12, 18))
		
		prog.rooms = [
			{"type": "Entry", "area": randf_range(6, 10), "aspect": randf_range(1.0, 1.5), "floor": 0},
			{"type": "Living", "area": randf_range(28, 38), "aspect": randf_range(1.4, 1.9), "floor": 0},
			{"type": "Dining", "area": randf_range(12, 18), "aspect": randf_range(1.2, 1.6), "floor": 0},
			{"type": "Kitchen", "area": randf_range(14, 20), "aspect": randf_range(1.0, 1.4), "floor": 0},
			{"type": "Bedroom", "area": randf_range(13, 17), "aspect": randf_range(1.3, 1.7), "floor": 0},
			{"type": "Bedroom", "area": randf_range(11, 15), "aspect": randf_range(1.2, 1.6), "floor": 0},
			{"type": "Bedroom", "area": randf_range(10, 14), "aspect": randf_range(1.2, 1.5), "floor": 0},
			{"type": "Bedroom", "area": randf_range(9, 13), "aspect": randf_range(1.2, 1.5), "floor": 0},
			{"type": "Bathroom", "area": randf_range(6, 9), "aspect": randf_range(1.1, 1.5), "floor": 0},
			{"type": "Bathroom", "area": randf_range(5, 7), "aspect": randf_range(1.0, 1.4), "floor": 0},
			{"type": "Bathroom", "area": randf_range(4, 6), "aspect": randf_range(1.0, 1.3), "floor": 0},
			{"type": "Laundry", "area": randf_range(4, 7), "aspect": randf_range(1.0, 1.5), "floor": 0},
		]
		
		prog.adjacencies = [
			{"a": "Entry", "b": "Living", "type": "door"},
			{"a": "Living", "b": "Dining", "type": "open"},
			{"a": "Dining", "b": "Kitchen", "type": "open"},
			{"a": "Living", "b": "Bedroom", "type": "door"},
			{"a": "Bedroom", "b": "Bathroom", "type": "door"},
			{"a": "Kitchen", "b": "Laundry", "type": "door"},
			{"a": "Laundry", "b": "Bathroom", "type": "door"},
		]
		
		data.single_story.append(prog)
	
	# ========================================
	# TWO-STORY PROGRAMS (50 instances)
	# ========================================
	
	# Compact two-story (1400-1800 sqft)
	for i in range(15):
		var prog := ProgramInstance.new()
		prog.floors = 2
		prog.bedrooms = 3
		prog.bathrooms = 2
		prog.total_sqft = randf_range(140, 180)
		prog.footprint = Vector2i(randi_range(12, 16), randi_range(10, 14))
		
		prog.rooms = [
			{"type": "Entry", "area": randf_range(5, 8), "aspect": randf_range(1.0, 1.4), "floor": 0},
			{"type": "Living", "area": randf_range(24, 32), "aspect": randf_range(1.4, 1.8), "floor": 0},
			{"type": "Dining", "area": randf_range(10, 14), "aspect": randf_range(1.1, 1.5), "floor": 0},
			{"type": "Kitchen", "area": randf_range(12, 16), "aspect": randf_range(1.0, 1.3), "floor": 0},
			{"type": "Bathroom", "area": randf_range(4, 6), "aspect": randf_range(1.0, 1.3), "floor": 0},
			{"type": "Stair", "area": randf_range(6, 10), "aspect": randf_range(1.5, 2.5), "floor": 0},
			{"type": "Hall", "area": randf_range(8, 12), "aspect": randf_range(2.0, 4.0), "floor": 1},
			{"type": "Bedroom", "area": randf_range(12, 16), "aspect": randf_range(1.3, 1.7), "floor": 1},
			{"type": "Bedroom", "area": randf_range(10, 14), "aspect": randf_range(1.2, 1.6), "floor": 1},
			{"type": "Bedroom", "area": randf_range(9, 13), "aspect": randf_range(1.2, 1.5), "floor": 1},
			{"type": "Bathroom", "area": randf_range(5, 8), "aspect": randf_range(1.1, 1.4), "floor": 1},
			{"type": "Stair", "area": randf_range(6, 10), "aspect": randf_range(1.5, 2.5), "floor": 1},
		]
		
		prog.adjacencies = [
			{"a": "Entry", "b": "Living", "type": "door"},
			{"a": "Living", "b": "Dining", "type": "open"},
			{"a": "Dining", "b": "Kitchen", "type": "open"},
			{"a": "Entry", "b": "Stair", "type": "door"},
			{"a": "Hall", "b": "Bedroom", "type": "door"},
			{"a": "Hall", "b": "Bathroom", "type": "door"},
			{"a": "Hall", "b": "Stair", "type": "door"},
		]
		
		data.two_story.append(prog)
	
	# Standard two-story (1800-2400 sqft)
	for i in range(20):
		var prog := ProgramInstance.new()
		prog.floors = 2
		prog.bedrooms = 4
		prog.bathrooms = 3
		prog.total_sqft = randf_range(180, 240)
		prog.footprint = Vector2i(randi_range(14, 18), randi_range(12, 16))
		
		prog.rooms = [
			{"type": "Entry", "area": randf_range(6, 10), "aspect": randf_range(1.0, 1.5), "floor": 0},
			{"type": "Living", "area": randf_range(28, 38), "aspect": randf_range(1.5, 2.0), "floor": 0},
			{"type": "Dining", "area": randf_range(12, 18), "aspect": randf_range(1.2, 1.6), "floor": 0},
			{"type": "Kitchen", "area": randf_range(14, 20), "aspect": randf_range(1.0, 1.4), "floor": 0},
			{"type": "Bathroom", "area": randf_range(4, 6), "aspect": randf_range(1.0, 1.3), "floor": 0},
			{"type": "Laundry", "area": randf_range(4, 7), "aspect": randf_range(1.0, 1.5), "floor": 0},
			{"type": "Stair", "area": randf_range(7, 11), "aspect": randf_range(1.5, 2.5), "floor": 0},
			{"type": "Hall", "area": randf_range(10, 15), "aspect": randf_range(2.0, 4.0), "floor": 1},
			{"type": "Bedroom", "area": randf_range(14, 19), "aspect": randf_range(1.3, 1.7), "floor": 1},
			{"type": "Bedroom", "area": randf_range(11, 15), "aspect": randf_range(1.2, 1.6), "floor": 1},
			{"type": "Bedroom", "area": randf_range(10, 14), "aspect": randf_range(1.2, 1.5), "floor": 1},
			{"type": "Bedroom", "area": randf_range(9, 13), "aspect": randf_range(1.2, 1.5), "floor": 1},
			{"type": "Bathroom", "area": randf_range(6, 9), "aspect": randf_range(1.1, 1.5), "floor": 1},
			{"type": "Bathroom", "area": randf_range(5, 7), "aspect": randf_range(1.0, 1.4), "floor": 1},
			{"type": "Stair", "area": randf_range(7, 11), "aspect": randf_range(1.5, 2.5), "floor": 1},
		]
		
		prog.adjacencies = [
			{"a": "Entry", "b": "Living", "type": "door"},
			{"a": "Living", "b": "Dining", "type": "open"},
			{"a": "Dining", "b": "Kitchen", "type": "open"},
			{"a": "Entry", "b": "Stair", "type": "door"},
			{"a": "Kitchen", "b": "Laundry", "type": "door"},
			{"a": "Hall", "b": "Bedroom", "type": "door"},
			{"a": "Hall", "b": "Bathroom", "type": "door"},
			{"a": "Hall", "b": "Stair", "type": "door"},
			{"a": "Bedroom", "b": "Bathroom", "type": "door"},
		]
		
		data.two_story.append(prog)
	
	# Large two-story (2400-3200 sqft)
	for i in range(15):
		var prog := ProgramInstance.new()
		prog.floors = 2
		prog.bedrooms = 5
		prog.bathrooms = 4
		prog.total_sqft = randf_range(240, 320)
		prog.footprint = Vector2i(randi_range(16, 22), randi_range(14, 18))
		
		prog.rooms = [
			{"type": "Entry", "area": randf_range(8, 12), "aspect": randf_range(1.0, 1.6), "floor": 0},
			{"type": "Living", "area": randf_range(32, 45), "aspect": randf_range(1.5, 2.1), "floor": 0},
			{"type": "Dining", "area": randf_range(14, 20), "aspect": randf_range(1.2, 1.7), "floor": 0},
			{"type": "Kitchen", "area": randf_range(16, 24), "aspect": randf_range(1.1, 1.5), "floor": 0},
			{"type": "Study", "area": randf_range(10, 15), "aspect": randf_range(1.2, 1.6), "floor": 0},
			{"type": "Bathroom", "area": randf_range(5, 7), "aspect": randf_range(1.0, 1.4), "floor": 0},
			{"type": "Laundry", "area": randf_range(5, 8), "aspect": randf_range(1.0, 1.5), "floor": 0},
			{"type": "Stair", "area": randf_range(8, 13), "aspect": randf_range(1.5, 2.5), "floor": 0},
			{"type": "Hall", "area": randf_range(12, 18), "aspect": randf_range(2.0, 4.5), "floor": 1},
			{"type": "Bedroom", "area": randf_range(16, 22), "aspect": randf_range(1.3, 1.8), "floor": 1},
			{"type": "Bedroom", "area": randf_range(13, 17), "aspect": randf_range(1.2, 1.6), "floor": 1},
			{"type": "Bedroom", "area": randf_range(11, 15), "aspect": randf_range(1.2, 1.6), "floor": 1},
			{"type": "Bedroom", "area": randf_range(10, 14), "aspect": randf_range(1.2, 1.5), "floor": 1},
			{"type": "Bathroom", "area": randf_range(7, 10), "aspect": randf_range(1.1, 1.5), "floor": 1},
			{"type": "Bathroom", "area": randf_range(6, 8), "aspect": randf_range(1.0, 1.4), "floor": 1},
			{"type": "Bathroom", "area": randf_range(5, 7), "aspect": randf_range(1.0, 1.3), "floor": 1},
			{"type": "Stair", "area": randf_range(8, 13), "aspect": randf_range(1.5, 2.5), "floor": 1},
		]
		
		prog.adjacencies = [
			{"a": "Entry", "b": "Living", "type": "door"},
			{"a": "Living", "b": "Dining", "type": "open"},
			{"a": "Dining", "b": "Kitchen", "type": "open"},
			{"a": "Entry", "b": "Stair", "type": "door"},
			{"a": "Kitchen", "b": "Laundry", "type": "door"},
			{"a": "Hall", "b": "Bedroom", "type": "door"},
			{"a": "Hall", "b": "Bathroom", "type": "door"},
			{"a": "Hall", "b": "Stair", "type": "door"},
			{"a": "Bedroom", "b": "Bathroom", "type": "door"},
		]
		
		data.two_story.append(prog)
	
	# ========================================
	# THREE-STORY PROGRAMS (30 instances)
	# ========================================
	
	# Hillside three-story (2200-2800 sqft)
	for i in range(15):
		var prog := ProgramInstance.new()
		prog.floors = 3
		prog.bedrooms = 4
		prog.bathrooms = 3
		prog.total_sqft = randf_range(220, 280)
		prog.footprint = Vector2i(randi_range(14, 18), randi_range(12, 16))
		
		prog.rooms = [
			# Ground floor (entry level)
			{"type": "Entry", "area": randf_range(6, 10), "aspect": randf_range(1.0, 1.5), "floor": 0},
			{"type": "Living", "area": randf_range(28, 38), "aspect": randf_range(1.5, 2.0), "floor": 0},
			{"type": "Dining", "area": randf_range(12, 18), "aspect": randf_range(1.2, 1.6), "floor": 0},
			{"type": "Kitchen", "area": randf_range(14, 20), "aspect": randf_range(1.0, 1.4), "floor": 0},
			{"type": "Bathroom", "area": randf_range(4, 6), "aspect": randf_range(1.0, 1.3), "floor": 0},
			{"type": "Stair", "area": randf_range(7, 11), "aspect": randf_range(1.5, 2.5), "floor": 0},
			# Upper floor (bedrooms)
			{"type": "Hall", "area": randf_range(10, 15), "aspect": randf_range(2.0, 4.0), "floor": 1},
			{"type": "Bedroom", "area": randf_range(14, 19), "aspect": randf_range(1.3, 1.7), "floor": 1},
			{"type": "Bedroom", "area": randf_range(11, 15), "aspect": randf_range(1.2, 1.6), "floor": 1},
			{"type": "Bedroom", "area": randf_range(10, 14), "aspect": randf_range(1.2, 1.5), "floor": 1},
			{"type": "Bathroom", "area": randf_range(6, 9), "aspect": randf_range(1.1, 1.5), "floor": 1},
			{"type": "Bathroom", "area": randf_range(5, 7), "aspect": randf_range(1.0, 1.4), "floor": 1},
			{"type": "Stair", "area": randf_range(7, 11), "aspect": randf_range(1.5, 2.5), "floor": 1},
			# Lower floor (walkout basement)
			{"type": "Entry", "area": randf_range(5, 8), "aspect": randf_range(1.0, 1.4), "floor": -1},
			{"type": "Bedroom", "area": randf_range(12, 16), "aspect": randf_range(1.2, 1.6), "floor": -1},
			{"type": "Bathroom", "area": randf_range(5, 7), "aspect": randf_range(1.0, 1.4), "floor": -1},
			{"type": "Utility", "area": randf_range(8, 12), "aspect": randf_range(1.0, 1.5), "floor": -1},
			{"type": "Stair", "area": randf_range(7, 11), "aspect": randf_range(1.5, 2.5), "floor": -1},
		]
		
		prog.adjacencies = [
			{"a": "Entry", "b": "Living", "type": "door"},
			{"a": "Living", "b": "Dining", "type": "open"},
			{"a": "Dining", "b": "Kitchen", "type": "open"},
			{"a": "Entry", "b": "Stair", "type": "door"},
			{"a": "Hall", "b": "Bedroom", "type": "door"},
			{"a": "Hall", "b": "Bathroom", "type": "door"},
			{"a": "Hall", "b": "Stair", "type": "door"},
		]
		
		data.three_story.append(prog)
	
	# Large three-story (2800-3800 sqft)
	for i in range(15):
		var prog := ProgramInstance.new()
		prog.floors = 3
		prog.bedrooms = 6
		prog.bathrooms = 5
		prog.total_sqft = randf_range(280, 380)
		prog.footprint = Vector2i(randi_range(16, 22), randi_range(14, 20))
		
		prog.rooms = [
			# Ground floor
			{"type": "Entry", "area": randf_range(8, 12), "aspect": randf_range(1.0, 1.6), "floor": 0},
			{"type": "Living", "area": randf_range(35, 48), "aspect": randf_range(1.5, 2.2), "floor": 0},
			{"type": "Dining", "area": randf_range(16, 22), "aspect": randf_range(1.2, 1.7), "floor": 0},
			{"type": "Kitchen", "area": randf_range(18, 26), "aspect": randf_range(1.1, 1.5), "floor": 0},
			{"type": "Study", "area": randf_range(12, 17), "aspect": randf_range(1.2, 1.6), "floor": 0},
			{"type": "Bathroom", "area": randf_range(5, 7), "aspect": randf_range(1.0, 1.4), "floor": 0},
			{"type": "Laundry", "area": randf_range(5, 8), "aspect": randf_range(1.0, 1.5), "floor": 0},
			{"type": "Stair", "area": randf_range(9, 14), "aspect": randf_range(1.5, 2.5), "floor": 0},
			# Upper floor
			{"type": "Hall", "area": randf_range(14, 20), "aspect": randf_range(2.0, 4.5), "floor": 1},
			{"type": "Bedroom", "area": randf_range(18, 24), "aspect": randf_range(1.3, 1.8), "floor": 1},
			{"type": "Bedroom", "area": randf_range(14, 18), "aspect": randf_range(1.2, 1.6), "floor": 1},
			{"type": "Bedroom", "area": randf_range(12, 16), "aspect": randf_range(1.2, 1.6), "floor": 1},
			{"type": "Bedroom", "area": randf_range(11, 15), "aspect": randf_range(1.2, 1.5), "floor": 1},
			{"type": "Bathroom", "area": randf_range(8, 11), "aspect": randf_range(1.1, 1.5), "floor": 1},
			{"type": "Bathroom", "area": randf_range(6, 9), "aspect": randf_range(1.0, 1.4), "floor": 1},
			{"type": "Stair", "area": randf_range(9, 14), "aspect": randf_range(1.5, 2.5), "floor": 1},
			# Lower floor
			{"type": "Entry", "area": randf_range(6, 10), "aspect": randf_range(1.0, 1.5), "floor": -1},
			{"type": "Bedroom", "area": randf_range(14, 18), "aspect": randf_range(1.2, 1.6), "floor": -1},
			{"type": "Bedroom", "area": randf_range(12, 16), "aspect": randf_range(1.2, 1.6), "floor": -1},
			{"type": "Bathroom", "area": randf_range(6, 8), "aspect": randf_range(1.0, 1.4), "floor": -1},
			{"type": "Bathroom", "area": randf_range(5, 7), "aspect": randf_range(1.0, 1.3), "floor": -1},
			{"type": "Utility", "area": randf_range(10, 15), "aspect": randf_range(1.0, 1.6), "floor": -1},
			{"type": "Stair", "area": randf_range(9, 14), "aspect": randf_range(1.5, 2.5), "floor": -1},
		]
		
		prog.adjacencies = [
			{"a": "Entry", "b": "Living", "type": "door"},
			{"a": "Living", "b": "Dining", "type": "open"},
			{"a": "Dining", "b": "Kitchen", "type": "open"},
			{"a": "Entry", "b": "Stair", "type": "door"},
			{"a": "Kitchen", "b": "Laundry", "type": "door"},
			{"a": "Hall", "b": "Bedroom", "type": "door"},
			{"a": "Hall", "b": "Bathroom", "type": "door"},
			{"a": "Hall", "b": "Stair", "type": "door"},
			{"a": "Bedroom", "b": "Bathroom", "type": "door"},
		]
		
		data.three_story.append(prog)
	
	# ========================================
	# REAL-WORLD FLOOR PLAN: Plan #142-1221
	# Source: Architectural Designs
	# ========================================

	var prog_142_1221 := ProgramInstance.new()
	prog_142_1221.total_sqft = 120.0
	prog_142_1221.footprint = Vector2i(9, 18)
	prog_142_1221.floors = 1
	prog_142_1221.bedrooms = 3
	prog_142_1221.bathrooms = 2

	prog_142_1221.rooms = [
		{"type": "Entry", "area": 3.15, "aspect": 1.12, "floor": 0},
		{"type": "Living", "area": 21.95, "aspect": 1.18, "floor": 0},
		{"type": "Kitchen", "area": 14.49, "aspect": 1.35, "floor": 0},
		{"type": "Bedroom", "area": 15.23, "aspect": 1.14, "floor": 0},
		{"type": "Bedroom", "area": 11.24, "aspect": 1.0, "floor": 0},
		{"type": "Bedroom", "area": 11.24, "aspect": 1.0, "floor": 0},
		{"type": "Bathroom", "area": 8.55, "aspect": 1.44, "floor": 0},
		{"type": "Bathroom", "area": 5.57, "aspect": 2.4, "floor": 0},
		{"type": "Hall", "area": 5.57, "aspect": 6.67, "floor": 0},
		{"type": "Laundry", "area": 1.53, "aspect": 1.83, "floor": 0},
		{"type": "Pantry", "area": 2.17, "aspect": 1.15, "floor": 0},
		{"type": "Closet", "area": 4.55, "aspect": 1.36, "floor": 0},
	]

	prog_142_1221.adjacencies = [
		{"a": "Entry", "b": "Living", "type": "open"},
		{"a": "Living", "b": "Kitchen", "type": "open"},
		{"a": "Kitchen", "b": "Pantry", "type": "door"},
		{"a": "Kitchen", "b": "Hall", "type": "open"},
		{"a": "Hall", "b": "Bedroom", "type": "door"},
		{"a": "Hall", "b": "Bedroom", "type": "door"},
		{"a": "Hall", "b": "Bedroom", "type": "door"},
		{"a": "Hall", "b": "Bathroom", "type": "door"},
		{"a": "Hall", "b": "Laundry", "type": "door"},
		{"a": "Bedroom", "b": "Bathroom", "type": "door"},
		{"a": "Bedroom", "b": "Closet", "type": "door"},
	]

	data.single_story.append(prog_142_1221)
	
	# ========================================
	# PLAN #2: Modern Farmhouse Ranch
	# ========================================

	var plan_2 := ProgramInstance.new()
	plan_2.total_sqft = 260.0
	plan_2.footprint = Vector2i(16, 21)
	plan_2.floors = 1
	plan_2.bedrooms = 4
	plan_2.bathrooms = 3

	plan_2.rooms = [
		{"type": "Entry", "area": 9.5, "aspect": 1.41, "floor": 0},
		{"type": "Living", "area": 34.1, "aspect": 1.05, "floor": 0},
		{"type": "Dining", "area": 11.1, "aspect": 1.2, "floor": 0},
		{"type": "Kitchen", "area": 20.5, "aspect": 1.54, "floor": 0},
		{"type": "Office", "area": 9.5, "aspect": 1.41, "floor": 0},
		{"type": "Bedroom", "area": 23.7, "aspect": 1.13, "floor": 0},
		{"type": "Bathroom", "area": 16.7, "aspect": 1.25, "floor": 0},
		{"type": "Closet", "area": 5.6, "aspect": 2.4, "floor": 0},
		{"type": "Bedroom", "area": 11.6, "aspect": 1.0, "floor": 0},
		{"type": "Bedroom", "area": 11.5, "aspect": 1.02, "floor": 0},
		{"type": "Bedroom", "area": 12.7, "aspect": 1.05, "floor": 0},
		{"type": "Bathroom", "area": 3.7, "aspect": 1.6, "floor": 0},
		{"type": "Bathroom", "area": 4.6, "aspect": 2.0, "floor": 0},
		{"type": "Bathroom", "area": 2.8, "aspect": 1.2, "floor": 0},
		{"type": "Laundry", "area": 5.9, "aspect": 1.0, "floor": 0},
		{"type": "Pantry", "area": 3.0, "aspect": 2.0, "floor": 0},
		{"type": "Garage", "area": 83.2, "aspect": 1.56, "floor": 0},
		{"type": "Porch", "area": 24.6, "aspect": 7.35, "floor": 0},
		{"type": "Porch", "area": 37.8, "aspect": 2.83, "floor": 0},
		{"type": "Kitchen", "area": 8.9, "aspect": 1.5, "floor": 0},
	]

	plan_2.adjacencies = [
		{"a": "Entry", "b": "Dining", "type": "door"},
		{"a": "Entry", "b": "Office", "type": "door"},
		{"a": "Entry", "b": "Living", "type": "open"},
		{"a": "Living", "b": "Kitchen", "type": "open"},
		{"a": "Kitchen", "b": "Dining", "type": "open"},
		{"a": "Kitchen", "b": "Laundry", "type": "door"},
		{"a": "Kitchen", "b": "Pantry", "type": "door"},
		{"a": "Kitchen", "b": "Bathroom", "type": "door"},
		{"a": "Kitchen", "b": "Porch", "type": "door"},
		{"a": "Living", "b": "Bedroom", "type": "door"},
		{"a": "Bedroom", "b": "Bathroom", "type": "door"},
		{"a": "Bedroom", "b": "Closet", "type": "door"},
		{"a": "Living", "b": "Bedroom", "type": "door"},
		{"a": "Living", "b": "Bedroom", "type": "door"},
		{"a": "Bedroom", "b": "Bathroom", "type": "door"},
		{"a": "Bedroom", "b": "Bathroom", "type": "door"},
		{"a": "Bedroom", "b": "Bathroom", "type": "door"},
		{"a": "Garage", "b": "Kitchen", "type": "door"},
	]

	data.single_story.append(plan_2)
	
	# ========================================
	# PLAN #3: Two-Story Traditional/Country
	# 3BR/2.5BA, 2400 sqft (223 m²), 52' × 46'
	# Features: 2-car garage, vaulted living, study, porches
	# ========================================

	var plan_3 := ProgramInstance.new()

	# Global features
	plan_3.total_sqft = 223.0  # 2400 sqft = 223 m²
	plan_3.footprint = Vector2i(16, 14)  # 52' × 46' ≈ 15.8m × 14.0m
	plan_3.floors = 2
	plan_3.bedrooms = 3
	plan_3.bathrooms = 3  # 2 full + 1 powder (count as 3 for simplicity)

	# Rooms with measurements from floor plan
	plan_3.rooms = [
		# ===== FLOOR 1 (Ground Floor) =====
		
		# Entry/Circulation
		{"type": "Entry", "area": 6.7, "aspect": 1.13, "floor": 0},  # Foyer: 9' × 8'
		
		# Living Spaces
		{"type": "Living", "area": 33.2, "aspect": 1.4, "floor": 0},   # Living Room: 22'-4" × 16'
		{"type": "Dining", "area": 12.6, "aspect": 1.12, "floor": 0},  # Dining: 12'-4" × 11'
		{"type": "Kitchen", "area": 10.3, "aspect": 1.37, "floor": 0}, # Kitchen: 12'-4" × 9'
		
		# Study
		{"type": "Office", "area": 5.7, "aspect": 1.24, "floor": 0},   # Study: 8'-8" × 7'
		
		# Master Suite (on ground floor)
		{"type": "Bedroom", "area": 17.2, "aspect": 1.22, "floor": 0}, # Master: 12'-4" × 15'
		{"type": "Bathroom", "area": 5.1, "aspect": 1.37, "floor": 0}, # Master Bath: 8'-8" × 6'-4"
		
		# Additional Ground Floor Spaces
		{"type": "Bathroom", "area": 2.3, "aspect": 1.0, "floor": 0},  # Powder: 5' × 5'
		{"type": "Pantry", "area": 1.3, "aspect": 1.56, "floor": 0},   # Pantry: 3' × 4'-8"
		{"type": "Utility", "area": 2.2, "aspect": 1.5, "floor": 0},   # Storage: 4' × 6'
		
		# Garage
		{"type": "Garage", "area": 40.9, "aspect": 1.1, "floor": 0},   # 2-car: 20' × 22'
		
		# Porches
		{"type": "Porch", "area": 4.1, "aspect": 2.75, "floor": 0},    # Front: 11' × 4'
		{"type": "Porch", "area": 8.2, "aspect": 5.5, "floor": 0},     # Rear: 22' × 4'
		
		# ===== FLOOR 2 (Upper Floor) =====
		
		# Circulation
		{"type": "Hall", "area": 6.7, "aspect": 2.0, "floor": 1},      # Hall/Landing: 12' × 6'
		
		# Bedrooms
		{"type": "Bedroom", "area": 12.6, "aspect": 1.12, "floor": 1}, # Bed #2: 12'-4" × 11'
		{"type": "Bedroom", "area": 11.6, "aspect": 1.03, "floor": 1}, # Bed #3: 11' × 11'-4"
		
		# Bathroom
		{"type": "Bathroom", "area": 5.1, "aspect": 1.37, "floor": 1}, # Bath: 8'-8" × 6'-4"
	]

	# Adjacencies from floor plan
	plan_3.adjacencies = [
		# ===== Floor 1 Adjacencies =====
		
		# Main circulation
		{"a": "Entry", "b": "Living", "type": "open"},   # Foyer to Living
		{"a": "Entry", "b": "Garage", "type": "door"},
		{"a": "Entry", "b": "Bathroom", "type": "door"}, # Powder room
		{"a": "Entry", "b": "Porch", "type": "door"},    # Front porch
		
		# Open concept living
		{"a": "Living", "b": "Dining", "type": "open"},
		{"a": "Living", "b": "Kitchen", "type": "open"},  # Vaulted ceiling connection
		{"a": "Kitchen", "b": "Dining", "type": "open"},
		
		# Living room connections
		{"a": "Living", "b": "Office", "type": "door"},   # Study
		{"a": "Living", "b": "Bedroom", "type": "door"},  # Master bedroom
		
		# Kitchen connections
		{"a": "Kitchen", "b": "Pantry", "type": "door"},
		{"a": "Kitchen", "b": "Porch", "type": "door"},   # Rear porch
		
		# Master suite
		{"a": "Bedroom", "b": "Bathroom", "type": "door"}, # Master to master bath
		
		# ===== Floor 2 Adjacencies =====
		
		# Upper floor circulation
		{"a": "Hall", "b": "Bedroom", "type": "door"},    # Hall to Bed #2
		{"a": "Hall", "b": "Bedroom", "type": "door"},    # Hall to Bed #3
		{"a": "Hall", "b": "Bathroom", "type": "door"},   # Hall to shared bath
		
		# Bedroom-Bathroom connections (Jack-and-Jill style)
		{"a": "Bedroom", "b": "Bathroom", "type": "door"}, # Bed #2 to bath
		{"a": "Bedroom", "b": "Bathroom", "type": "door"}, # Bed #3 to bath
	]

	# Add to dataset
	data.two_story.append(plan_3)
	
	# ========================================
	# PLAN #4: Large Two-Story Craftsman
	# 4-5BR/3.5-4.5BA, 3800 sqft (353 m²), 57' × 56'
	# Features: Optional main-floor master, bonus room, lanai, veranda
	# ========================================

	var plan_4 := ProgramInstance.new()

	# Global features
	plan_4.total_sqft = 353.0  # 3800 sqft = 353 m²
	plan_4.footprint = Vector2i(17, 17)  # 57' × 56' ≈ 17.4m × 17.1m
	plan_4.floors = 2
	plan_4.bedrooms = 4  # 3 standard + 1 game room (can be 5 with optional master)
	plan_4.bathrooms = 4  # 3 full + 1 powder (can be 5 with optional master bath)

	# Rooms with measurements from floor plan
	plan_4.rooms = [
		# ===== FLOOR 1 (Ground Floor) =====
		
		# Entry/Circulation
		{"type": "Entry", "area": 11.1, "aspect": 1.2, "floor": 0},  # Foyer: 10' × 12'
		{"type": "Hall", "area": 11.1, "aspect": 1.88, "floor": 0},  # Hall: 8' × 15'
		
		# Living Spaces
		{"type": "Dining", "area": 15.2, "aspect": 1.14, "floor": 0},  # Dining: 12' × 13'-8"
		{"type": "Living", "area": 32.8, "aspect": 1.13, "floor": 0},  # Family: 20' × 17'-8"
		{"type": "Kitchen", "area": 18.9, "aspect": 2.03, "floor": 0}, # Kitchen: 10' × 20'-4"
		
		# Study/Office
		{"type": "Office", "area": 11.1, "aspect": 1.2, "floor": 0},   # Study: 12' × 10'
		
		# Utility Spaces
		{"type": "Pantry", "area": 9.3, "aspect": 1.0, "floor": 0},    # Pantry: 10' × 10'
		{"type": "Laundry", "area": 5.5, "aspect": 1.38, "floor": 0},  # Laundry: 9' × 6'-6"
		{"type": "Bathroom", "area": 2.8, "aspect": 1.2, "floor": 0},  # Powder: 5' × 6'
		
		# Optional Main-Floor Master Suite
		{"type": "Bedroom", "area": 20.8, "aspect": 1.14, "floor": 0}, # Master: 14' × 16'
		{"type": "Bathroom", "area": 14.5, "aspect": 1.08, "floor": 0}, # Master Bath: 13' × 12'
		{"type": "Closet", "area": 2.8, "aspect": 1.2, "floor": 0},    # WIC 1: 5' × 6'
		{"type": "Closet", "area": 6.7, "aspect": 2.0, "floor": 0},    # WIC 2: 6' × 12'
		
		# Garage
		{"type": "Garage", "area": 45.2, "aspect": 1.03, "floor": 0},  # 2-car: 22'-5" × 21'-8"
		
		# Outdoor Spaces
		{"type": "Porch", "area": 30.7, "aspect": 3.3, "floor": 0},    # Lanai: 33' × 10'
		{"type": "Porch", "area": 24.5, "aspect": 4.13, "floor": 0},   # Veranda: 33' × 8'
		
		# ===== FLOOR 2 (Upper Floor) =====
		
		# Circulation
		{"type": "Hall", "area": 7.4, "aspect": 1.25, "floor": 1},     # Mezzanine: 8' × 10'
		
		# Vaulted Space
		{"type": "Living", "area": 23.2, "aspect": 1.5, "floor": 1},   # Open to Family (2-story)
		
		# Bedrooms
		{"type": "Bedroom", "area": 12.0, "aspect": 1.07, "floor": 1}, # Bed #2: 11' × 11'-9"
		{"type": "Bedroom", "area": 11.0, "aspect": 1.18, "floor": 1}, # Bed #3: 11'-9" × 10'
		{"type": "Bedroom", "area": 20.7, "aspect": 1.45, "floor": 1}, # Game/BR: 12'-5" × 18'
		
		# Bathrooms
		{"type": "Bathroom", "area": 7.2, "aspect": 1.57, "floor": 1}, # Bath #2: 7' × 11'
		{"type": "Bathroom", "area": 5.4, "aspect": 2.3, "floor": 1},  # Bath #3: 11'-6" × 5'
		
		# Closets
		{"type": "Closet", "area": 1.9, "aspect": 1.25, "floor": 1},   # Bed 2 closet: 4' × 5'
		{"type": "Closet", "area": 1.9, "aspect": 1.25, "floor": 1},   # Bed 3 closet: 4' × 5'
		
		# Bonus Room
		{"type": "Bedroom", "area": 33.9, "aspect": 2.05, "floor": 1}, # Bonus: 13'-4" × 27'-4"
		{"type": "Utility", "area": 4.0, "aspect": 1.7, "floor": 1},   # Storage: 8'-6" × 5'
		
		# Balcony
		{"type": "Porch", "area": 8.9, "aspect": 1.5, "floor": 1},     # Balcony: 12' × 8'
	]

	# Adjacencies from floor plan
	plan_4.adjacencies = [
		# ===== Floor 1 Adjacencies =====
		
		# Main circulation
		{"a": "Entry", "b": "Dining", "type": "open"},
		{"a": "Entry", "b": "Office", "type": "door"},   # Study
		{"a": "Entry", "b": "Living", "type": "open"},   # Family room
		{"a": "Entry", "b": "Hall", "type": "door"},
		
		# Open concept living
		{"a": "Living", "b": "Kitchen", "type": "open"},
		{"a": "Kitchen", "b": "Dining", "type": "open"},
		{"a": "Living", "b": "Porch", "type": "door"},   # Lanai
		
		# Kitchen connections
		{"a": "Kitchen", "b": "Pantry", "type": "door"},
		
		# Hall connections
		{"a": "Hall", "b": "Laundry", "type": "door"},
		{"a": "Hall", "b": "Bathroom", "type": "door"}, # Powder
		{"a": "Hall", "b": "Bedroom", "type": "door"},  # Master suite
		{"a": "Hall", "b": "Garage", "type": "door"},
		
		# Master suite (optional)
		{"a": "Bedroom", "b": "Bathroom", "type": "door"}, # Master bath
		{"a": "Bedroom", "b": "Closet", "type": "door"},   # WIC 1
		{"a": "Bathroom", "b": "Closet", "type": "door"},  # WIC 2
		
		# Veranda access
		{"a": "Dining", "b": "Porch", "type": "door"},
		
		# ===== Floor 2 Adjacencies =====
		
		# Upper circulation
		{"a": "Hall", "b": "Bedroom", "type": "open"},    # Game room
		{"a": "Hall", "b": "Porch", "type": "door"},      # Balcony
		{"a": "Hall", "b": "Bedroom", "type": "door"},    # Bed #2
		{"a": "Hall", "b": "Bedroom", "type": "door"},    # Bed #3
		{"a": "Hall", "b": "Bathroom", "type": "door"},   # Bath #3
		{"a": "Hall", "b": "Bedroom", "type": "door"},    # Bonus room
		
		# Bedroom-bathroom connections
		{"a": "Bedroom", "b": "Bathroom", "type": "door"}, # Bed #2 to Bath #2
		{"a": "Bedroom", "b": "Closet", "type": "door"},   # Bed #2 closet
		{"a": "Bedroom", "b": "Closet", "type": "door"},   # Bed #3 closet
		{"a": "Bedroom", "b": "Bathroom", "type": "door"}, # Bed #3 to Bath #3
		
		# Bonus room connections
		{"a": "Bedroom", "b": "Utility", "type": "door"},  # Bonus to Storage
	]

	# Add to dataset
	data.two_story.append(plan_4)
	
	# ========================================
	# PLAN #5: Luxury 3-Level Mountain/Lakefront
	# 5BR/5.5BA, 5200 sqft (483 m²), 62' × 58'
	# Features: Walkout basement, wine cellar, wet bar, multiple decks
	# ========================================

	var plan_5 := ProgramInstance.new()

	# Global features
	plan_5.total_sqft = 483.0  # 5200 sqft = 483 m²
	plan_5.footprint = Vector2i(19, 18)  # 62' × 58' ≈ 18.9m × 17.7m
	plan_5.floors = 3  # Basement (-1) + Main (0) + Upper (1)
	plan_5.bedrooms = 5  # 1 main + 2 upper + 2 basement
	plan_5.bathrooms = 6  # 3 full + 3 partial (simplified to 6)

	# Rooms with measurements from floor plan
	plan_5.rooms = [
		# ===== FLOOR 0 (Main Floor) =====
		
		# Entry/Circulation
		{"type": "Entry", "area": 7.2, "aspect": 1.57, "floor": 0},  # Foyer: 7' × 11'
		
		# Living Spaces
		{"type": "Living", "area": 33.4, "aspect": 1.11, "floor": 0},   # Great Room: 20' × 18'
		{"type": "Dining", "area": 20.1, "aspect": 1.5, "floor": 0},    # Dining: 12' × 18'
		{"type": "Kitchen", "area": 20.4, "aspect": 1.82, "floor": 0},  # Kitchen: 11' × 20'
		{"type": "Living", "area": 18.1, "aspect": 1.15, "floor": 0},   # Hearth: 15' × 13'
		
		# Master Suite (Main Floor)
		{"type": "Bedroom", "area": 23.8, "aspect": 1.0, "floor": 0},   # Master: 16' × 16'
		{"type": "Bathroom", "area": 10.2, "aspect": 1.5, "floor": 0},  # Master Bath: 9'×6' + 8'×7'
		{"type": "Closet", "area": 7.8, "aspect": 2.33, "floor": 0},    # Master Closet: 6' × 14'
		
		# Utility Spaces
		{"type": "Pantry", "area": 1.9, "aspect": 1.25, "floor": 0},    # Pantry: 4' × 5'
		{"type": "Laundry", "area": 6.1, "aspect": 1.83, "floor": 0},   # Mud Room: 11' × 6'
		
		# Garage
		{"type": "Garage", "area": 60.6, "aspect": 1.5, "floor": 0},    # 2.5-car: 13'×28' + 12'×24'
		
		# Outdoor Spaces (Main)
		{"type": "Porch", "area": 15.8, "aspect": 1.7, "floor": 0},     # Covered Deck: 10' × 17'
		{"type": "Porch", "area": 10.4, "aspect": 2.29, "floor": 0},    # Deck (Master): 16' × 7'
		{"type": "Porch", "area": 10.6, "aspect": 3.17, "floor": 0},    # Deck (Dining): 19' × 6'
		{"type": "Porch", "area": 10.0, "aspect": 1.33, "floor": 0},    # Screened: 9' × 12'
		{"type": "Porch", "area": 8.4, "aspect": 1.11, "floor": 0},     # Covered Entry: 9' × 10'
		{"type": "Porch", "area": 28.4, "aspect": 1.06, "floor": 0},    # Main Porch: 18' × 17'
		
		# Stairs (Main Floor)
		{"type": "Stair", "area": 6.5, "aspect": 2.0, "floor": 0},
		
		# ===== FLOOR 1 (Upper Floor) =====
		
		# Open Space
		{"type": "Living", "area": 19.5, "aspect": 1.07, "floor": 1},   # Open to Below: 15' × 14'
		
		# Circulation
		{"type": "Hall", "area": 8.0, "aspect": 2.5, "floor": 1},       # Upper Hall
		
		# Bedrooms
		{"type": "Bedroom", "area": 13.3, "aspect": 1.18, "floor": 1},  # Bed #2: 13' × 11'
		{"type": "Bedroom", "area": 12.3, "aspect": 1.09, "floor": 1},  # Bed #3: 12' × 11'
		
		# Bathroom
		{"type": "Bathroom", "area": 9.7, "aspect": 1.63, "floor": 1},  # Bath: 13' × 8'
		
		# Closets
		{"type": "Closet", "area": 2.2, "aspect": 1.5, "floor": 1},     # Br 2 Closet: 4' × 6'
		{"type": "Closet", "area": 2.2, "aspect": 1.5, "floor": 1},     # Br 3 Closet: 4' × 6'
		
		# Outdoor Space (Upper)
		{"type": "Porch", "area": 23.7, "aspect": 1.13, "floor": 1},    # Covered Deck: 15' × 17'
		
		# Stairs (Upper Floor)
		{"type": "Stair", "area": 6.5, "aspect": 2.0, "floor": 1},
		
		# ===== FLOOR -1 (Lower Level/Basement) =====
		
		# Entertainment Spaces
		{"type": "Living", "area": 20.8, "aspect": 1.14, "floor": -1},  # Recreation: 16' × 14'
		{"type": "Living", "area": 28.4, "aspect": 1.06, "floor": -1},  # Family: 18' × 17'
		{"type": "Kitchen", "area": 16.7, "aspect": 1.25, "floor": -1}, # Wet Bar: 15' × 12'
		{"type": "Living", "area": 14.3, "aspect": 1.27, "floor": -1},  # Tasting: 11' × 14'
		{"type": "Utility", "area": 6.5, "aspect": 2.8, "floor": -1},   # Wine Cellar: 5' × 14'
		
		# Bedrooms (Lower)
		{"type": "Bedroom", "area": 10.2, "aspect": 1.1, "floor": -1},  # Bed #4: 10' × 11'
		{"type": "Bedroom", "area": 10.2, "aspect": 1.1, "floor": -1},  # Bed #5: 10' × 11'
		
		# Bathroom (Lower)
		{"type": "Bathroom", "area": 6.7, "aspect": 2.0, "floor": -1},  # Bath: 6' × 12'
		
		# Utility Spaces (Lower)
		{"type": "Utility", "area": 15.7, "aspect": 1.0, "floor": -1},  # Storage: 13' × 13'
		{"type": "Utility", "area": 21.4, "aspect": 2.3, "floor": -1},  # Mechanical: 23' × 10'
		{"type": "Living", "area": 23.8, "aspect": 1.0, "floor": -1},   # Exercise: 16' × 16'
		{"type": "Laundry", "area": 6.7, "aspect": 1.13, "floor": -1},  # Mud Room: 8' × 9'
		{"type": "Laundry", "area": 6.7, "aspect": 1.13, "floor": -1},  # Laundry: 8' × 9'
		
		# Outdoor Space (Lower)
		{"type": "Porch", "area": 89.9, "aspect": 3.0, "floor": -1},    # Covered Patio: multiple sections
		
		# Stairs (Lower Level)
		{"type": "Stair", "area": 6.5, "aspect": 2.0, "floor": -1},
	]

	# Adjacencies from floor plan
	plan_5.adjacencies = [
		# ===== Floor 0 (Main) Adjacencies =====
		
		# Main circulation
		{"a": "Entry", "b": "Living", "type": "open"},   # Entry to Great Room
		{"a": "Entry", "b": "Porch", "type": "door"},    # Entry to Front Porch
		{"a": "Entry", "b": "Stair", "type": "door"},    # Entry to Stairs
		
		# Open concept living
		{"a": "Living", "b": "Dining", "type": "open"},  # Great Room to Dining
		{"a": "Living", "b": "Living", "type": "open"},  # Great Room to Hearth
		{"a": "Living", "b": "Kitchen", "type": "open"},
		{"a": "Dining", "b": "Kitchen", "type": "open"},
		
		# Kitchen connections
		{"a": "Kitchen", "b": "Pantry", "type": "door"},
		{"a": "Kitchen", "b": "Laundry", "type": "door"},  # Mud Room
		{"a": "Kitchen", "b": "Porch", "type": "door"},    # Covered Deck
		
		# Master suite
		{"a": "Living", "b": "Bedroom", "type": "door"},   # Hearth to Master
		{"a": "Bedroom", "b": "Bathroom", "type": "door"},
		{"a": "Bedroom", "b": "Closet", "type": "door"},
		{"a": "Bedroom", "b": "Porch", "type": "door"},    # Master to Deck
		
		# Garage access
		{"a": "Laundry", "b": "Garage", "type": "door"},   # Mud Room to Garage
		
		# ===== Floor 1 (Upper) Adjacencies =====
	
		# Upper circulation
		{"a": "Hall", "b": "Bedroom", "type": "door"},     # Hall to Bed #2
		{"a": "Hall", "b": "Bedroom", "type": "door"},     # Hall to Bed #3
		{"a": "Hall", "b": "Bathroom", "type": "door"},
		{"a": "Hall", "b": "Stair", "type": "door"},
		{"a": "Hall", "b": "Porch", "type": "door"},       # Upper Deck
	
		# Bedroom connections
		{"a": "Bedroom", "b": "Closet", "type": "door"},   # Bed #2
		{"a": "Bedroom", "b": "Closet", "type": "door"},   # Bed #3
	
		# ===== Floor -1 (Lower) Adjacencies =====
	
		# Entertainment zone
		{"a": "Stair", "b": "Living", "type": "open"},     # Stairs to Recreation
		{"a": "Living", "b": "Living", "type": "open"},    # Recreation to Family
		{"a": "Living", "b": "Kitchen", "type": "open"},   # Recreation to Wet Bar
		{"a": "Living", "b": "Living", "type": "door"},    # Recreation to Tasting
		{"a": "Living", "b": "Utility", "type": "door"},   # Tasting to Wine Cellar
	
		# Bedroom connections (Lower)
		{"a": "Living", "b": "Bedroom", "type": "door"},   # Family to Bed #4
		{"a": "Living", "b": "Bedroom", "type": "door"},   # Family to Bed #5
		{"a": "Living", "b": "Bathroom", "type": "door"},
	
		# Utility connections
		{"a": "Living", "b": "Laundry", "type": "door"},   # Recreation to Mud Room
		{"a": "Laundry", "b": "Laundry", "type": "door"},  # Mud Room to Laundry
		{"a": "Laundry", "b": "Living", "type": "door"},   # Mud Room to Exercise
		{"a": "Living", "b": "Utility", "type": "door"},   # Exercise to Storage
	
		# Outdoor access
		{"a": "Living", "b": "Porch", "type": "door"},     # Family to Covered Patio
	]

	# Add to dataset
	data.three_story.append(plan_5)
	
	# ========================================
	# PLAN #6: Luxury Single-Story with Bonus Room
	# 3BR/3.5BA, 3400 sqft (316 m²), 68' × 62'
	# Features: Open concept, bonus room over garage, extensive covered decks
	# ========================================

	var plan_6 := ProgramInstance.new()

	# Global features
	plan_6.total_sqft = 316.0  # 3400 sqft = 316 m²
	plan_6.footprint = Vector2i(21, 19)  # 68' × 62' ≈ 20.7m × 18.9m
	plan_6.floors = 1  # Single-story main floor (bonus room not counted as full 2nd floor)
	plan_6.bedrooms = 3  # 2 main floor + 1 bonus
	plan_6.bathrooms = 4  # 2 full + 1 master bath + 1 powder (simplified to 4)

	# Rooms with measurements from floor plan
	plan_6.rooms = [
		# ===== FLOOR 0 (Main Floor) =====
		
		# Entry/Circulation
		{"type": "Entry", "area": 12.4, "aspect": 2.71, "floor": 0},  # Entry: 19' × 7'
		
		# Living Spaces
		{"type": "Living", "area": 20.1, "aspect": 1.5, "floor": 0},   # Living: 18' × 12'
		{"type": "Living", "area": 31.8, "aspect": 1.06, "floor": 0},  # Great Room: 19' × 18'
		{"type": "Dining", "area": 23.7, "aspect": 1.13, "floor": 0},  # Dining: 17' × 15'
		{"type": "Kitchen", "area": 28.4, "aspect": 1.06, "floor": 0}, # Kitchen: 17' × 18'
		
		# Master Suite
		{"type": "Bedroom", "area": 25.3, "aspect": 1.06, "floor": 0}, # Master: 17' × 16'
		{"type": "Bathroom", "area": 13.0, "aspect": 1.4, "floor": 0}, # Master Bath: 14' × 10'
		{"type": "Closet", "area": 5.6, "aspect": 2.4, "floor": 0},    # Master Closet: 12' × 5'
		
		# Secondary Bedroom
		{"type": "Bedroom", "area": 14.5, "aspect": 1.08, "floor": 0}, # Bed #2: 12' × 13'
		{"type": "Closet", "area": 2.2, "aspect": 1.5, "floor": 0},    # Bed #2 Closet: 4' × 6'
		{"type": "Bathroom", "area": 6.7, "aspect": 1.13, "floor": 0}, # Bath #2: 8' × 9'
	
		# Utility Spaces
		{"type": "Bathroom", "area": 3.9, "aspect": 1.17, "floor": 0}, # Powder: 6' × 7'
		{"type": "Pantry", "area": 3.9, "aspect": 1.17, "floor": 0},   # Pantry: 6' × 7'
		{"type": "Laundry", "area": 3.9, "aspect": 1.17, "floor": 0},  # Mud Room: 6' × 7'
	
		# Garage
		{"type": "Garage", "area": 49.1, "aspect": 1.09, "floor": 0},  # 2-car: 22' × 24'
	
		# Bonus Room (over garage, accessed by stairs)
		{"type": "Bedroom", "area": 24.5, "aspect": 1.83, "floor": 1}, # Bonus: 22' × 12'
	
		# Outdoor Spaces
		{"type": "Porch", "area": 92.4, "aspect": 5.07, "floor": 0},   # Covered Deck (front): 71' × 14'
		{"type": "Porch", "area": 85.8, "aspect": 5.46, "floor": 0},   # Covered Deck (rear): 71' × 13'
		{"type": "Porch", "area": 30.6, "aspect": 6.71, "floor": 0},   # Covered Deck (side): 7' × 47'
		{"type": "Porch", "area": 11.1, "aspect": 1.88, "floor": 0},   # Pergola Deck: 8' × 15'
	]

	# Adjacencies from floor plan
	plan_6.adjacencies = [
		# ===== Main Floor Adjacencies =====
		
		# Entry connections (cathedral ceiling open space)
		{"a": "Entry", "b": "Living", "type": "open"},    # Entry to Living
		{"a": "Entry", "b": "Living", "type": "open"},    # Entry to Great Room (2nd Living node)
		{"a": "Entry", "b": "Dining", "type": "open"},    # Entry to Dining
		{"a": "Entry", "b": "Bathroom", "type": "door"},  # Entry to Powder Room
		
		# Open concept living
		{"a": "Living", "b": "Living", "type": "open"},   # Living to Great Room
		{"a": "Living", "b": "Kitchen", "type": "open"},  # Great Room to Kitchen
		{"a": "Living", "b": "Dining", "type": "open"},   # Great Room to Dining
		{"a": "Kitchen", "b": "Dining", "type": "open"},  # Kitchen to Dining
		
		# Kitchen connections
		{"a": "Kitchen", "b": "Pantry", "type": "door"},
		{"a": "Kitchen", "b": "Laundry", "type": "door"},  # Mud Room
		{"a": "Kitchen", "b": "Porch", "type": "door"},    # To covered deck
		
		# Living room connections
		{"a": "Living", "b": "Porch", "type": "door"},     # Living to covered deck
		{"a": "Living", "b": "Porch", "type": "door"},     # Great Room to covered deck
		
		# Master suite
		{"a": "Dining", "b": "Bedroom", "type": "door"},   # Dining to Master
		{"a": "Bedroom", "b": "Bathroom", "type": "door"},
		{"a": "Bedroom", "b": "Closet", "type": "door"},
		{"a": "Bedroom", "b": "Porch", "type": "door"},    # Master to Deck
		
		# Secondary bedroom
		{"a": "Living", "b": "Bedroom", "type": "door"},   # Great Room to Bed #2
		{"a": "Bedroom", "b": "Bathroom", "type": "door"}, # Bed #2 to Bath #2
		{"a": "Bedroom", "b": "Closet", "type": "door"},   # Bed #2 to Closet
	
		# Garage access
		{"a": "Laundry", "b": "Garage", "type": "door"},   # Mud Room to Garage
	
		# Bonus room (accessed via garage stairs)
		{"a": "Garage", "b": "Bedroom", "type": "door"},   # Garage to Bonus Room (via stairs)
	
		# Outdoor access
		{"a": "Dining", "b": "Porch", "type": "door"},     # Dining to deck
		{"a": "Garage", "b": "Porch", "type": "door"},     # Garage to pergola deck
	]

	# Add to dataset
	data.single_story.append(plan_6)
	
	# ========================================
	# PLAN #7: Large Single-Story + Bonus Room
	# 4BR/3.5BA, 3200 sqft (297 m²), 75' × 65'
	# Features: Kids' space, study, rear porch, bonus room over garage
	# ========================================

	var plan_7 := ProgramInstance.new()

	# Global features
	plan_7.total_sqft = 297.0  # 3200 sqft main floor = 297 m² (heated area)
	plan_7.footprint = Vector2i(23, 20)  # 75' × 65' ≈ 22.9m × 19.8m
	plan_7.floors = 1  # Single-story main floor (bonus room not counted as full 2nd floor)
	plan_7.bedrooms = 4  # 3 main floor + 1 bonus
	plan_7.bathrooms = 4  # 2 full + 1 master bath + 1 half bath (simplified to 4)

	# Rooms with measurements from floor plan
	plan_7.rooms = [
		# ===== FLOOR 0 (Main Floor) =====
		
		# Entry/Circulation
		{"type": "Entry", "area": 7.1, "aspect": 1.14, "floor": 0},  # Foyer: 9'-4" × 8'-2"
		{"type": "Entry", "area": 7.8, "aspect": 1.16, "floor": 0},  # Entry: 8'-6" × 9'-10"
		{"type": "Entry", "area": 8.8, "aspect": 1.36, "floor": 0},  # Stoop: 11'-4" × 8'-4"
	
		# Living Spaces
		{"type": "Living", "area": 38.1, "aspect": 1.04, "floor": 0},  # Great Room: 20'-8" × 19'-10"
		{"type": "Dining", "area": 15.7, "aspect": 1.18, "floor": 0},  # Dining: 12'-0" × 14'-1"
		{"type": "Kitchen", "area": 19.0, "aspect": 1.43, "floor": 0}, # Kitchen: 12'-0" × 17'-1"
		{"type": "Pantry", "area": 8.4, "aspect": 1.6, "floor": 0},    # Pantry: 12'-0" × 7'-6"
		{"type": "Office", "area": 10.4, "aspect": 1.29, "floor": 0},  # Study: 12'-0" × 9'-4"
	
		# Master Suite
		{"type": "Bedroom", "area": 24.4, "aspect": 1.17, "floor": 0}, # Master: 15'-0" × 17'-6"
		{"type": "Bathroom", "area": 11.3, "aspect": 1.90, "floor": 0}, # Master Bath: 15'-2" × 8'-0"
		{"type": "Closet", "area": 12.3, "aspect": 1.75, "floor": 0},  # Master Closet: 15'-2" × 8'-8"
	
		# Secondary Bedrooms
		{"type": "Bedroom", "area": 17.7, "aspect": 1.18, "floor": 0}, # Bed #2: 15'-0" × 12'-9"
		{"type": "Bedroom", "area": 17.5, "aspect": 1.20, "floor": 0}, # Bed #3: 15'-0" × 12'-6"
	
		# Bathrooms
		{"type": "Bathroom", "area": 8.5, "aspect": 1.33, "floor": 0}, # Bath #2: 11'-0" × 8'-3"
		{"type": "Bathroom", "area": 4.2, "aspect": 1.8, "floor": 0},  # Bath #3: 5'-0" × 9'-0"
		{"type": "Bathroom", "area": 2.8, "aspect": 1.2, "floor": 0},  # Half Bath: 5' × 6'
	
		# Utility Spaces
		{"type": "Laundry", "area": 7.4, "aspect": 1.25, "floor": 0},  # Laundry: 10'-0" × 8'-0"
		{"type": "Hall", "area": 12.4, "aspect": 1.33, "floor": 0},    # Kids' Space: 10'-0" × 13'-4"
	
		# Garage
		{"type": "Garage", "area": 58.4, "aspect": 1.10, "floor": 0},  # 2-car: 23'-10" × 26'-4"
		{"type": "Utility", "area": 8.5, "aspect": 1.04, "floor": 0},  # Storage (above garage): 9'-4" × 9'-9"
	
		# Outdoor Spaces
		{"type": "Porch", "area": 31.2, "aspect": 1.31, "floor": 0},   # Rear Porch: 21'-0" × 16'-0"
	
		# ===== FLOOR 1 (Bonus Room Level) =====
	
		# Bonus Room (over garage, accessed by stairs)
		{"type": "Bedroom", "area": 40.2, "aspect": 2.01, "floor": 1}, # Bonus: 14'-8" × 29'-6"
		{"type": "Bathroom", "area": 6.7, "aspect": 1.13, "floor": 1}, # Bath #4: 8'-0" × 9'-0"
		{"type": "Utility", "area": 8.5, "aspect": 1.04, "floor": 1},  # Attic Storage: 9'-4" × 9'-9"
	]

	# Adjacencies from floor plan
	plan_7.adjacencies = [
		# ===== Main Floor Adjacencies =====
		
		# Entry connections
		{"a": "Entry", "b": "Living", "type": "open"},    # Foyer to Great Room
		{"a": "Entry", "b": "Office", "type": "door"},    # Foyer to Study
		{"a": "Entry", "b": "Entry", "type": "open"},     # Entry to Foyer (connected spaces)
		{"a": "Entry", "b": "Laundry", "type": "door"},   # Entry to Laundry
		{"a": "Entry", "b": "Bedroom", "type": "door"},   # Entry to Master Bedroom
	
		# Open concept living
		{"a": "Living", "b": "Dining", "type": "open"},   # Great Room to Dining
		{"a": "Living", "b": "Kitchen", "type": "open"},  # Great Room to Kitchen
		{"a": "Kitchen", "b": "Dining", "type": "open"},  # Kitchen to Dining
	
		# Kitchen connections
		{"a": "Kitchen", "b": "Pantry", "type": "door"},
		{"a": "Kitchen", "b": "Laundry", "type": "door"},
	
		# Living room connections
		{"a": "Living", "b": "Porch", "type": "door"},    # Great Room to Rear Porch
		{"a": "Dining", "b": "Porch", "type": "door"},    # Dining to Rear Porch
	
		# Master suite
		{"a": "Bedroom", "b": "Bathroom", "type": "door"}, # Master to Master Bath
		{"a": "Bedroom", "b": "Closet", "type": "door"},   # Master to Master Closet
		{"a": "Bathroom", "b": "Closet", "type": "door"},  # Master Bath to Master Closet
	
		# Kids' wing
		{"a": "Hall", "b": "Bedroom", "type": "door"},     # Kids' Space to Bed #2
		{"a": "Hall", "b": "Bedroom", "type": "door"},     # Kids' Space to Bed #3
		{"a": "Hall", "b": "Bathroom", "type": "door"},    # Kids' Space to Bath #2
		{"a": "Bedroom", "b": "Bathroom", "type": "door"}, # Bed #2 to Bath #3
		{"a": "Bedroom", "b": "Porch", "type": "door"},    # Bed #3 to Rear Porch
	
		# Garage access
		{"a": "Garage", "b": "Utility", "type": "door"},   # Garage to Storage (stairs)
	
		# Front entry
		{"a": "Entry", "b": "Entry", "type": "door"},      # Foyer to Stoop
	
		# ===== Bonus Level Adjacencies =====
	
		# Bonus room (accessed via garage stairs)
		{"a": "Bedroom", "b": "Bathroom", "type": "door"}, # Bonus to Bath #4
		{"a": "Bedroom", "b": "Utility", "type": "door"},  # Bonus to Attic Storage
	]

	# Add to dataset
	data.single_story.append(plan_7)
	
	print("✓ Training data created: %d single-story, %d two-story, %d three-story" % [
		data.single_story.size(),
		data.two_story.size(),
		data.three_story.size()
	])
	
	return data