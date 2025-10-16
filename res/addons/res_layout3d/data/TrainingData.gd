extends Resource
class_name TrainingData

## Represents a single training example for the Bayesian network
class ProgramInstance:
    extends RefCounted

    var total_m2: float = 0.0
    var footprint: Vector2i = Vector2i.ZERO
    var floors: int = 1
    var bedrooms: int = 0
    var bathrooms: int = 0
    var rooms: Array[Dictionary] = []
    var adjacencies: Array[Dictionary] = []

    var total_sqft_bin: int = -1
    var total_m2_bin: int = -1
    var footprint_w_bin: int = -1
    var footprint_d_bin: int = -1
    var footprint_bin: int = -1
    var room_counts: Dictionary = {}
    var room_exists: Dictionary = {}
    var room_count_bins: Dictionary = {}
    var adj_pairs: Array[Dictionary] = []

var single_story: Array[ProgramInstance] = []
var two_story: Array[ProgramInstance] = []
var three_story: Array[ProgramInstance] = []

static func create_default() -> TrainingData:
    var data := TrainingData.new()

    data.single_story.append(_make_program({
        "floors": 1,
        "bedrooms": 3,
        "bathrooms": 2,
        "total_m2": 140.0,
        "footprint": Vector2i(14, 10),
        "rooms": [
            {"type": "Entry", "area": 6.0, "aspect": 1.2, "floor": 0},
            {"type": "Living", "area": 32.0, "aspect": 1.5, "floor": 0},
            {"type": "Kitchen", "area": 14.0, "aspect": 1.2, "floor": 0},
            {"type": "Dining", "area": 12.0, "aspect": 1.4, "floor": 0},
            {"type": "Bedroom", "area": 13.0, "aspect": 1.3, "floor": 0},
            {"type": "Bedroom", "area": 11.5, "aspect": 1.2, "floor": 0},
            {"type": "Bedroom", "area": 11.0, "aspect": 1.3, "floor": 0},
            {"type": "Bathroom", "area": 5.5, "aspect": 1.2, "floor": 0},
            {"type": "Bathroom", "area": 4.5, "aspect": 1.1, "floor": 0},
            {"type": "Laundry", "area": 4.0, "aspect": 1.1, "floor": 0},
            {"type": "Hall", "area": 10.0, "aspect": 2.2, "floor": 0},
        ],
        "adjacencies": [
            {"a": "Entry", "b": "Living", "type": "door"},
            {"a": "Living", "b": "Dining", "type": "open"},
            {"a": "Dining", "b": "Kitchen", "type": "open"},
            {"a": "Living", "b": "Hall", "type": "door"},
            {"a": "Hall", "b": "Bedroom", "type": "door"},
            {"a": "Hall", "b": "Bathroom", "type": "door"},
            {"a": "Kitchen", "b": "Laundry", "type": "door"},
        ]
    }))

    data.single_story.append(_make_program({
        "floors": 1,
        "bedrooms": 2,
        "bathrooms": 2,
        "total_m2": 115.0,
        "footprint": Vector2i(12, 9),
        "rooms": [
            {"type": "Entry", "area": 5.0, "aspect": 1.1, "floor": 0},
            {"type": "Living", "area": 28.0, "aspect": 1.4, "floor": 0},
            {"type": "Kitchen", "area": 13.5, "aspect": 1.3, "floor": 0},
            {"type": "Bedroom", "area": 12.5, "aspect": 1.2, "floor": 0},
            {"type": "Bedroom", "area": 11.0, "aspect": 1.2, "floor": 0},
            {"type": "Bathroom", "area": 5.0, "aspect": 1.1, "floor": 0},
            {"type": "Bathroom", "area": 4.0, "aspect": 1.0, "floor": 0},
            {"type": "Hall", "area": 8.0, "aspect": 2.0, "floor": 0},
            {"type": "Patio", "area": 10.0, "aspect": 1.6, "floor": 0},
        ],
        "adjacencies": [
            {"a": "Entry", "b": "Living", "type": "door"},
            {"a": "Living", "b": "Kitchen", "type": "open"},
            {"a": "Living", "b": "Hall", "type": "door"},
            {"a": "Hall", "b": "Bedroom", "type": "door"},
            {"a": "Hall", "b": "Bathroom", "type": "door"},
            {"a": "Living", "b": "Patio", "type": "open"},
        ]
    }))

    data.two_story.append(_make_program({
        "floors": 2,
        "bedrooms": 4,
        "bathrooms": 3,
        "total_m2": 195.0,
        "footprint": Vector2i(12, 12),
        "rooms": [
            {"type": "Entry", "area": 6.0, "aspect": 1.1, "floor": 0},
            {"type": "Living", "area": 34.0, "aspect": 1.5, "floor": 0},
            {"type": "Kitchen", "area": 15.0, "aspect": 1.2, "floor": 0},
            {"type": "Dining", "area": 13.0, "aspect": 1.4, "floor": 0},
            {"type": "Bathroom", "area": 4.5, "aspect": 1.2, "floor": 0},
            {"type": "Stair", "area": 7.5, "aspect": 2.0, "floor": 0},
            {"type": "Garage", "area": 36.0, "aspect": 1.3, "floor": 0},
            {"type": "Hall", "area": 12.0, "aspect": 2.4, "floor": 1},
            {"type": "Bedroom", "area": 15.0, "aspect": 1.3, "floor": 1},
            {"type": "Bedroom", "area": 14.0, "aspect": 1.2, "floor": 1},
            {"type": "Bedroom", "area": 13.0, "aspect": 1.2, "floor": 1},
            {"type": "Bedroom", "area": 12.0, "aspect": 1.2, "floor": 1},
            {"type": "Bathroom", "area": 5.5, "aspect": 1.3, "floor": 1},
            {"type": "Bathroom", "area": 4.8, "aspect": 1.2, "floor": 1},
            {"type": "Laundry", "area": 5.0, "aspect": 1.1, "floor": 1},
        ],
        "adjacencies": [
            {"a": "Entry", "b": "Living", "type": "door"},
            {"a": "Living", "b": "Dining", "type": "open"},
            {"a": "Dining", "b": "Kitchen", "type": "open"},
            {"a": "Kitchen", "b": "Garage", "type": "door"},
            {"a": "Living", "b": "Stair", "type": "door"},
            {"a": "Stair", "b": "Hall", "type": "open"},
            {"a": "Hall", "b": "Bedroom", "type": "door"},
            {"a": "Hall", "b": "Bathroom", "type": "door"},
        ]
    }))

    data.three_story.append(_make_program({
        "floors": 3,
        "bedrooms": 5,
        "bathrooms": 4,
        "total_m2": 260.0,
        "footprint": Vector2i(13, 14),
        "rooms": [
            {"type": "Entry", "area": 7.0, "aspect": 1.2, "floor": 0},
            {"type": "Living", "area": 36.0, "aspect": 1.5, "floor": 0},
            {"type": "Kitchen", "area": 16.0, "aspect": 1.3, "floor": 0},
            {"type": "Dining", "area": 14.0, "aspect": 1.4, "floor": 0},
            {"type": "Office", "area": 12.0, "aspect": 1.2, "floor": 0},
            {"type": "Bathroom", "area": 5.0, "aspect": 1.1, "floor": 0},
            {"type": "Stair", "area": 8.0, "aspect": 2.1, "floor": 0},
            {"type": "Hall", "area": 10.0, "aspect": 2.3, "floor": 1},
            {"type": "Bedroom", "area": 15.0, "aspect": 1.3, "floor": 1},
            {"type": "Bedroom", "area": 14.5, "aspect": 1.2, "floor": 1},
            {"type": "Bedroom", "area": 13.5, "aspect": 1.2, "floor": 1},
            {"type": "Bathroom", "area": 5.2, "aspect": 1.3, "floor": 1},
            {"type": "Bathroom", "area": 4.6, "aspect": 1.2, "floor": 1},
            {"type": "Laundry", "area": 5.0, "aspect": 1.1, "floor": 1},
            {"type": "Hall", "area": 8.0, "aspect": 2.0, "floor": 2},
            {"type": "Bedroom", "area": 13.0, "aspect": 1.2, "floor": 2},
            {"type": "Bedroom", "area": 12.5, "aspect": 1.1, "floor": 2},
            {"type": "Bathroom", "area": 4.5, "aspect": 1.1, "floor": 2},
            {"type": "Loft", "area": 18.0, "aspect": 1.6, "floor": 2},
        ],
        "adjacencies": [
            {"a": "Entry", "b": "Living", "type": "door"},
            {"a": "Living", "b": "Dining", "type": "open"},
            {"a": "Dining", "b": "Kitchen", "type": "open"},
            {"a": "Living", "b": "Office", "type": "door"},
            {"a": "Living", "b": "Stair", "type": "door"},
            {"a": "Stair", "b": "Hall", "type": "open"},
            {"a": "Hall", "b": "Bedroom", "type": "door"},
            {"a": "Hall", "b": "Bathroom", "type": "door"},
            {"a": "Loft", "b": "Bedroom", "type": "open"},
        ]
    }))

    return data

static func _make_program(desc: Dictionary) -> ProgramInstance:
    var prog := ProgramInstance.new()
    prog.floors = int(desc.get("floors", 1))
    prog.bedrooms = int(desc.get("bedrooms", 0))
    prog.bathrooms = int(desc.get("bathrooms", 0))
    prog.total_m2 = float(desc.get("total_m2", 0.0))
    prog.footprint = desc.get("footprint", Vector2i.ZERO)
    prog.rooms = []
    for room in desc.get("rooms", []):
        if room is Dictionary:
            prog.rooms.append(room.duplicate(true))
    prog.adjacencies = []
    for edge in desc.get("adjacencies", []):
        if edge is Dictionary:
            prog.adjacencies.append(edge.duplicate(true))
    return prog

enum AdjType { OPEN = 0, DOOR = 1 }

static func default_binning_config() -> Dictionary:
    return {
        "method": "fixed",
        "sqft_edges": PackedFloat64Array([80.0, 120.0, 160.0, 220.0, 300.0]),
        "foot_w_edges": PackedFloat64Array([6.0, 8.0, 10.0, 12.0, 14.0, 18.0]),
        "foot_d_edges": PackedFloat64Array([6.0, 8.0, 10.0, 12.0, 14.0, 18.0]),
        "room_area_edges": PackedFloat64Array([6.0, 9.0, 12.0, 16.0, 21.0, 27.0, 36.0]),
        "aspect_edges": PackedFloat64Array([1.0, 1.25, 1.5, 2.0, 3.0, 5.0]),
        "n_bins_sqft": 5,
        "n_bins_foot_w": 6,
        "n_bins_foot_d": 6,
        "n_bins_room_area": 7,
        "n_bins_aspect": 6,
    }

static func bin_corpus(instances: Array, cfg: Dictionary = default_binning_config()) -> Dictionary:
    var edges := _prepare_edges(instances, cfg)
    apply_binning(instances, edges)
    return edges

static func apply_binning(instances: Array, edges: Dictionary) -> void:
    for prog in instances:
        _bin_program(prog, edges)

static func _prepare_edges(instances: Array, cfg: Dictionary) -> Dictionary:
    var edges: Dictionary = {}
    var method := String(cfg.get("method", "fixed"))
    if method == "fixed":
        edges["total_m2_edges"] = cfg.get("sqft_edges", PackedFloat64Array())
        edges["footprint_w_edges"] = cfg.get("foot_w_edges", PackedFloat64Array())
        edges["footprint_d_edges"] = cfg.get("foot_d_edges", PackedFloat64Array())
        edges["room_area_edges"] = cfg.get("room_area_edges", PackedFloat64Array())
        edges["aspect_edges"] = cfg.get("aspect_edges", PackedFloat64Array())
        return edges

    edges["total_m2_edges"] = _quantile_edges(_collect_total_m2(instances), int(cfg.get("n_bins_sqft", 5)))
    edges["footprint_w_edges"] = _quantile_edges(_collect_foot_dim(instances, "w"), int(cfg.get("n_bins_foot_w", 6)))
    edges["footprint_d_edges"] = _quantile_edges(_collect_foot_dim(instances, "d"), int(cfg.get("n_bins_foot_d", 6)))
    edges["room_area_edges"] = _quantile_edges(_collect_room_area(instances), int(cfg.get("n_bins_room_area", 7)))
    edges["aspect_edges"] = _quantile_edges(_collect_room_aspect(instances), int(cfg.get("n_bins_aspect", 6)))
    return edges

static func _bin_program(prog, edges: Dictionary) -> void:
    if prog == null:
        return

    var total_m2 := _prog_total_m2(prog)
    var footprint := _prog_footprint(prog)
    var foot_w := float(footprint.x)
    var foot_d := float(footprint.y)

    var sqft_edges: PackedFloat64Array = edges.get("total_m2_edges", PackedFloat64Array())
    var w_edges: PackedFloat64Array = edges.get("footprint_w_edges", PackedFloat64Array())
    var d_edges: PackedFloat64Array = edges.get("footprint_d_edges", PackedFloat64Array())

    var total_bin := _bin_index(total_m2, sqft_edges)
    var w_bin := _bin_index(foot_w, w_edges)
    var d_bin := _bin_index(foot_d, d_edges)

    _set_field(prog, "total_sqft_bin", total_bin)
    _set_field(prog, "total_m2_bin", total_bin)
    _set_field(prog, "footprint_w_bin", w_bin)
    _set_field(prog, "footprint_d_bin", d_bin)
    var n_d_bins := d_edges.size() + 1
    _set_field(prog, "footprint_bin", w_bin * n_d_bins + d_bin)

    var rooms: Array = []
    if prog is ProgramInstance:
        rooms = prog.rooms
    elif typeof(prog) == TYPE_DICTIONARY:
        var dict_prog: Dictionary = prog
        var raw_rooms = dict_prog.get("rooms")
        if raw_rooms is Array:
            rooms = raw_rooms

    var room_area_edges: PackedFloat64Array = edges.get("room_area_edges", PackedFloat64Array())
    var aspect_edges: PackedFloat64Array = edges.get("aspect_edges", PackedFloat64Array())

    var id_to_idx := {}
    var label_to_indices := {}
    var label_cycle := {}
    var label_counts := {}

    for i in range(rooms.size()):
        var room: Dictionary = rooms[i]
        var room_type := String(room.get("type", "Room"))
        var count := int(label_counts.get(room_type, 0))
        label_counts[room_type] = count + 1
        var base_id := String(room.get("id", room_type))
        var rid := base_id
        if rid == room_type and count > 0:
            rid = "%s_%d" % [room_type, count]
        room["id"] = rid
        rooms[i] = room
        id_to_idx[rid] = i

        if not label_to_indices.has(room_type):
            label_to_indices[room_type] = []
        var list_by_type: Array = label_to_indices[room_type]
        list_by_type.append(i)
        label_to_indices[room_type] = list_by_type

        var area := _room_area_m2(room)
        var aspect := _room_aspect(room)
        room["area_bin"] = _bin_index(area, room_area_edges)
        room["aspect_bin"] = _bin_index(aspect, aspect_edges)
        rooms[i] = room

    _set_field(prog, "rooms", rooms)

    var adj_pairs: Array = []
    var edges_src: Array = []
    if prog is ProgramInstance:
        var inst: ProgramInstance = prog
        if inst.adjacencies.size() > 0:
            edges_src = inst.adjacencies
    elif typeof(prog) == TYPE_DICTIONARY:
        var dict_prog2: Dictionary = prog
        var raw_adj = dict_prog2.get("adjacencies")
        if raw_adj is Array:
            edges_src = raw_adj
    if edges_src.is_empty():
        var legacy_edges = prog.get("edges") if prog is ProgramInstance else (prog as Dictionary).get("edges") if typeof(prog) == TYPE_DICTIONARY else null
        if legacy_edges is Array:
            edges_src = legacy_edges

    var adj_lookup := {}
    for edge in edges_src:
        var a_idx := _resolve_room_index(edge, "a", id_to_idx, label_to_indices, label_cycle)
        var b_idx := _resolve_room_index(edge, "b", id_to_idx, label_to_indices, label_cycle)
        if a_idx < 0 or b_idx < 0:
            continue
        var ai := min(a_idx, b_idx)
        var bi := max(a_idx, b_idx)
        var key := "%d|%d" % [ai, bi]
        adj_lookup[key] = String(edge.get("type", "door")).to_lower()

    for i in range(rooms.size()):
        for j in range(i + 1, rooms.size()):
            var key := "%d|%d" % [i, j]
            var type_a := String(rooms[i].get("type", "Room"))
            var type_b := String(rooms[j].get("type", "Room"))
            var pair_label := _room_pair_label(type_a, type_b)
            if adj_lookup.has(key):
                var kind := String(adj_lookup[key])
                var adj_type := "door" if kind == "door" else "open"
                adj_pairs.append({"a": i, "b": j, "pair": pair_label, "exist": 1, "type": adj_type})
            else:
                adj_pairs.append({"a": i, "b": j, "pair": pair_label, "exist": 0, "type": "none"})

    _set_field(prog, "adj_pairs", adj_pairs)

    var counts := {}
    var exists := {}
    var count_bins := {}
    for room_type in label_counts.keys():
        var count := int(label_counts[room_type])
        counts[room_type] = count
        exists["%s_exists" % room_type] = count > 0
        count_bins["%s_count_bin" % room_type] = _count_to_bin(count)

    _set_field(prog, "room_counts", counts)
    _set_field(prog, "room_exists", exists)
    _set_field(prog, "room_count_bins", count_bins)
static func _resolve_room_index(edge: Dictionary, field: String, id_to_idx: Dictionary, label_to_indices: Dictionary, label_cycle: Dictionary) -> int:
    var label := String(edge.get(field, ""))
    if label == "":
        return -1
    if id_to_idx.has(label):
        return int(id_to_idx[label])
    if label_to_indices.has(label):
        var arr: Array = label_to_indices[label]
        if arr.is_empty():
            return -1
        var idx := int(label_cycle.get(label, 0)) % arr.size()
        label_cycle[label] = (idx + 1) % arr.size()
        return int(arr[idx])
    return -1

static func _set_field(target, name: String, value) -> void:
    if typeof(target) == TYPE_DICTIONARY:
        target[name] = value
    else:
        target.set(name, value)

static func _count_to_bin(count: int) -> int:
    if count <= 0:
        return 0
    if count == 1:
        return 1
    if count == 2:
        return 2
    return 3

static func _room_pair_label(a: String, b: String) -> String:
    var ordered := [a, b]
    ordered.sort()
    return "%s|%s" % [ordered[0], ordered[1]]

static func _program_to_dict(prog) -> Dictionary:
    var result := {}
    if prog == null:
        return result
    if prog is ProgramInstance:
        var inst: ProgramInstance = prog
        result["floors"] = inst.floors
        result["bedrooms"] = inst.bedrooms
        result["bathrooms"] = inst.bathrooms
        result["total_m2"] = _prog_total_m2(inst)
        var bin_val := inst.total_m2_bin if inst.total_m2_bin != -1 else inst.total_sqft_bin
        result["total_m2_bin"] = bin_val
        var fp := _prog_footprint(inst)
        result["footprint"] = {"w": fp.x, "d": fp.y}
        result["footprint_w_bin"] = inst.footprint_w_bin
        result["footprint_d_bin"] = inst.footprint_d_bin
        result["footprint_bin"] = inst.footprint_bin
        result["room_counts"] = inst.room_counts.duplicate()
        result["room_exists"] = inst.room_exists.duplicate()
        result["room_count_bins"] = inst.room_count_bins.duplicate()
        var rooms_out: Array = []
        for room in inst.rooms:
            if room is Dictionary:
                rooms_out.append(room.duplicate(true))
            else:
                rooms_out.append(room)
        result["rooms"] = rooms_out
        var adj_out: Array = []
        for adj in inst.adj_pairs:
            if adj is Dictionary:
                adj_out.append(adj.duplicate(true))
            else:
                adj_out.append(adj)
        result["adj_pairs"] = adj_out
        return result
    if typeof(prog) == TYPE_DICTIONARY:
        var dict_prog: Dictionary = prog
        result["floors"] = dict_prog.get("floors", 1)
        result["bedrooms"] = dict_prog.get("bedrooms", dict_prog.get("room_counts", {}).get("Bedroom", 0))
        result["bathrooms"] = dict_prog.get("bathrooms", dict_prog.get("room_counts", {}).get("Bathroom", 0))
        result["total_m2"] = float(dict_prog.get("total_m2", dict_prog.get("total_sqft", 0.0)))
        result["total_m2_bin"] = dict_prog.get("total_m2_bin", dict_prog.get("total_sqft_bin", -1))
        var fp_dict := dict_prog.get("footprint", {})
        if fp_dict is Dictionary:
            result["footprint"] = {"w": float(fp_dict.get("w", 0.0)), "d": float(fp_dict.get("d", 0.0))}
        else:
            result["footprint"] = {"w": 0.0, "d": 0.0}
        result["footprint_w_bin"] = dict_prog.get("footprint_w_bin", -1)
        result["footprint_d_bin"] = dict_prog.get("footprint_d_bin", -1)
        result["footprint_bin"] = dict_prog.get("footprint_bin", -1)
        result["room_counts"] = dict_prog.get("room_counts", {})
        result["room_exists"] = dict_prog.get("room_exists", {})
        result["room_count_bins"] = dict_prog.get("room_count_bins", {})
        var rooms_out_dict: Array = []
        for room in dict_prog.get("rooms", []):
            if room is Dictionary:
                rooms_out_dict.append(room.duplicate(true))
            else:
                rooms_out_dict.append(room)
        result["rooms"] = rooms_out_dict
        var adj_out_dict: Array = []
        for adj in dict_prog.get("adj_pairs", []):
            if adj is Dictionary:
                adj_out_dict.append(adj.duplicate(true))
            else:
                adj_out_dict.append(adj)
        result["adj_pairs"] = adj_out_dict
        return result
    return result

static func save_binned_corpus(path: String, instances: Array) -> void:
    var payload := {"instances": []}
    for prog in instances:
        payload["instances"].append(_program_to_dict(prog))
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file:
        file.store_string(JSON.stringify(payload, "    "))
        file.close()

static func _prog_total_m2(prog) -> float:
    if prog == null:
        return 0.0
    var v: Variant = null
    if typeof(prog) == TYPE_DICTIONARY:
        var dict_prog: Dictionary = prog
        v = dict_prog.get("total_m2")
        if v == null:
            v = dict_prog.get("total_sqft")
    else:
        v = prog.get("total_m2")
        if v == null:
            v = prog.get("total_sqft")
    if v == null:
        v = 0.0
    return float(v)

static func _prog_footprint(prog) -> Vector2:
    if prog == null:
        return Vector2.ZERO
    var fp_val: Variant = null
    if typeof(prog) == TYPE_DICTIONARY:
        var dict_prog: Dictionary = prog
        fp_val = dict_prog.get("footprint")
    else:
        fp_val = prog.get("footprint")
    if fp_val is Vector2i:
        var vi: Vector2i = fp_val
        return Vector2(float(vi.x), float(vi.y))
    if fp_val is Vector2:
        return fp_val
    var width := 0.0
    var depth := 0.0
    if typeof(prog) == TYPE_DICTIONARY:
        var dw := (prog as Dictionary).get("footprint_w")
        var dd := (prog as Dictionary).get("footprint_d")
        if dw != null:
            width = float(dw)
        if dd != null:
            depth = float(dd)
    else:
        var w_val: float = 0.0
        var w_variant: Variant = prog.get("footprint_w")
        if w_variant != null:
            w_val = float(w_variant)
        elif prog.footprint is Vector2i:
            w_val = float((prog.footprint as Vector2i).x)
        elif prog.footprint is Vector2:
            w_val = (prog.footprint as Vector2).x

        var d_val: float = 0.0
        var d_variant: Variant = prog.get("footprint_d")
        if d_variant != null:
            d_val = float(d_variant)
        elif prog.footprint is Vector2i:
            d_val = float((prog.footprint as Vector2i).y)
        elif prog.footprint is Vector2:
            d_val = (prog.footprint as Vector2).y

        width = w_val
        depth = d_val
    return Vector2(width, depth)


static func _prog_rooms_list(prog) -> Array:
    if prog is ProgramInstance:
        return prog.rooms
    if typeof(prog) == TYPE_DICTIONARY:
        var dict_prog: Dictionary = prog
        var arr = dict_prog.get("rooms")
        if arr is Array:
            return arr
        return []
    return []

static func _prog_adj_pairs_list(prog) -> Array:
    if prog is ProgramInstance:
        return prog.adj_pairs
    if typeof(prog) == TYPE_DICTIONARY:
        var dict_prog: Dictionary = prog
        var arr = dict_prog.get("adj_pairs")
        if arr is Array:
            return arr
        return []
    return []
static func _room_area_m2(room: Dictionary) -> float:
    if room.has("area_m2"):
        return float(room["area_m2"])
    if room.has("area"):
        return float(room["area"])
    if room.has("rect"):
        var rect_val = room["rect"]
        if rect_val is Rect2:
            var rect: Rect2 = rect_val
            return max(0.0, rect.size.x * rect.size.y)
        if rect_val is Dictionary:
            var w := float(rect_val.get("w", rect_val.get("size", Vector2.ZERO).x))
            var h := float(rect_val.get("h", rect_val.get("size", Vector2.ZERO).y))
            return max(0.0, w * h)
    if room.has("size"):
        var size_val = room["size"]
        if size_val is Vector2:
            var sz: Vector2 = size_val
            return max(0.0, sz.x * sz.y)
        if size_val is Vector2i:
            var szi: Vector2i = size_val
            return max(0.0, float(szi.x) * float(szi.y))
    return 0.0

static func _room_aspect(room: Dictionary) -> float:
    if room.has("aspect"):
        return max(1.0, float(room["aspect"]))
    var w := 0.0
    var h := 0.0
    if room.has("rect"):
        var rect_val = room["rect"]
        if rect_val is Rect2:
            var rect: Rect2 = rect_val
            w = rect.size.x
            h = rect.size.y
        elif rect_val is Dictionary:
            w = float(rect_val.get("w", rect_val.get("size", Vector2.ZERO).x))
            h = float(rect_val.get("h", rect_val.get("size", Vector2.ZERO).y))
    elif room.has("size"):
        var size_val = room["size"]
        if size_val is Vector2:
            var sz: Vector2 = size_val
            w = sz.x
            h = sz.y
        elif size_val is Vector2i:
            var szi: Vector2i = size_val
            w = float(szi.x)
            h = float(szi.y)
    w = max(w, 0.0001)
    h = max(h, 0.0001)
    var major := max(w, h)
    var minor := min(w, h)
    return max(1.0, major / minor)

static func _collect_total_m2(instances: Array) -> Array:
    var out: Array = []
    for prog in instances:
        out.append(_prog_total_m2(prog))
    return out

static func _collect_foot_dim(instances: Array, axis: String) -> Array:
    var out: Array = []
    for prog in instances:
        var fp := _prog_footprint(prog)
        out.append(fp.x if axis == "w" else fp.y)
    return out

static func _collect_room_area(instances: Array) -> Array:
    var out: Array = []
    for prog in instances:
        var rooms := _prog_rooms_list(prog)
        for room in rooms:
            if room is Dictionary:
                out.append(_room_area_m2(room))
    return out

static func _collect_room_aspect(instances: Array) -> Array:
    var out: Array = []
    for prog in instances:
        var rooms := _prog_rooms_list(prog)
        for room in rooms:
            if room is Dictionary:
                out.append(_room_aspect(room))
    return out

static func _bin_index(value: float, edges: PackedFloat64Array) -> int:
    for i in range(edges.size()):
        if value < edges[i]:
            return i
    return edges.size()

static func _quantile_edges(values: Array, bins: int) -> PackedFloat64Array:
    var result := PackedFloat64Array()
    if values.is_empty() or bins <= 1:
        return result
    var sorted_vals := values.duplicate()
    sorted_vals.sort()
    for b in range(1, bins):
        var q := float(b) / float(bins)
        var idx := clamp(int(round(q * (sorted_vals.size() - 1))), 0, sorted_vals.size() - 1)
        result.append(float(sorted_vals[idx]))
    return result
