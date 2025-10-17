extends Resource
class_name TrainingData

const DEBUG_VERIFY := true

const RESPLAN_TYPES := {
    "living": "Living",
    "living room": "Living",
    "great room": "Living",
    "kitchen": "Kitchen",
    "dining": "Dining",
    "bed": "Bedroom",
    "bedroom": "Bedroom",
    "primary bedroom": "Bedroom",
    "bath": "Bathroom",
    "bathroom": "Bathroom",
    "wc": "Bathroom",
    "toilet": "Bathroom",
    "powder": "Bathroom",
    "entry": "Entry",
    "foyer": "Entry",
    "hall": "Hall",
    "corridor": "Hall",
    "laundry": "Laundry",
    "utility": "Laundry",
    "mud": "Mudroom",
    "mudroom": "Mudroom",
    "office": "Office",
    "study": "Office",
    "den": "Office",
    "patio": "Patio",
    "balcony": "Patio",
    "terrace": "Patio",
    "porch": "Porch",
    "garage": "Garage",
    "stair": "Stair",
    "stairs": "Stair",
}

static func _norm_label(source: String) -> String:
    var key := source.strip_edges().to_lower()
    for pattern in RESPLAN_TYPES.keys():
        if key.find(pattern) >= 0:
            return RESPLAN_TYPES[pattern]
    return source.capitalize()

static func _poly_area(poly: PackedVector2Array) -> float:
    var n := poly.size()
    if n < 3:
        return 0.0
    var twice_area := 0.0
    for i in n:
        var j := (i + 1) % n
        twice_area += poly[i].x * poly[j].y - poly[j].x * poly[i].y
    return abs(twice_area) * 0.5

static func _poly_aabb(poly: PackedVector2Array) -> Rect2:
    if poly.is_empty():
        return Rect2(Vector2.ZERO, Vector2.ZERO)
    var rect := Rect2(poly[0], Vector2.ZERO)
    for p in poly:
        rect = rect.expand(p)
    return rect

static func _poly_aspect(poly: PackedVector2Array) -> float:
    var aabb := _poly_aabb(poly)
    var w := max(aabb.size.x, 1e-6)
    var h := max(aabb.size.y, 1e-6)
    return max(w, h) / max(min(w, h), 1e-6)

static func _shared_edge_length(a: PackedVector2Array, b: PackedVector2Array, tol: float = 1.0) -> float:
    var total := 0.0
    for i in a.size():
        var a0 := a[i]
        var a1 := a[(i + 1) % a.size()]
        var seg_a := Rect2(a0, Vector2.ZERO).expand(a1).grow(tol)
        var dir_a := a1 - a0
        for j in b.size():
            var b0 := b[j]
            var b1 := b[(j + 1) % b.size()]
            var seg_b := Rect2(b0, Vector2.ZERO).expand(b1).grow(tol)
            if not seg_a.intersects(seg_b):
                continue
            var dir_b := b1 - b0
            var cross := abs(dir_a.x * dir_b.y - dir_a.y * dir_b.x)
            if cross > 1e-3:
                continue
            var axis := dir_a
            if axis.length() <= 1e-5:
                continue
            axis = axis.normalized()
            var a_proj_0 := axis.dot(a0)
            var a_proj_1 := axis.dot(a1)
            if a_proj_1 < a_proj_0:
                var tmp := a_proj_0
                a_proj_0 = a_proj_1
                a_proj_1 = tmp
            var b_proj_0 := axis.dot(b0)
            var b_proj_1 := axis.dot(b1)
            if b_proj_1 < b_proj_0:
                var tmp2 := b_proj_0
                b_proj_0 = b_proj_1
                b_proj_1 = tmp2
            var overlap := min(a_proj_1, b_proj_1) - max(a_proj_0, b_proj_0)
            if overlap > -tol:
                total += max(0.0, overlap)
    return total

static func _segment_distance_sq(p: Vector2, a: Vector2, b: Vector2) -> float:
    var ab := b - a
    var t := 0.0
    var denom := ab.length_squared()
    if denom > 0.0:
        t = clamp((p - a).dot(ab) / denom, 0.0, 1.0)
    var closest := a + ab * t
    return p.distance_squared_to(closest)

static func _min_gap(a: PackedVector2Array, b: PackedVector2Array) -> float:
    var min_sq := INF
    for i in a.size():
        var a0 := a[i]
        var a1 := a[(i + 1) % a.size()]
        for j in b.size():
            var b0 := b[j]
            var b1 := b[(j + 1) % b.size()]
            var seg_inter := Geometry2D.segment_intersects_segment(a0, a1, b0, b1)
            if seg_inter != null:
                return 0.0
            min_sq = min(min_sq, _segment_distance_sq(a0, b0, b1))
            min_sq = min(min_sq, _segment_distance_sq(a1, b0, b1))
            min_sq = min(min_sq, _segment_distance_sq(b0, a0, a1))
            min_sq = min(min_sq, _segment_distance_sq(b1, a0, a1))
    return sqrt(min_sq)

static func _infer_adjacency_from_polys(rooms: Array, edge_min: float = 8.0, gap_tol: float = 2.0) -> Array:
    var pairs: Array = []
    for i in rooms.size():
        var pi: PackedVector2Array = rooms[i].get("poly", PackedVector2Array())
        if pi.size() < 3:
            continue
        for j in range(i + 1, rooms.size()):
            var pj: PackedVector2Array = rooms[j].get("poly", PackedVector2Array())
            if pj.size() < 3:
                continue
            var bb_i := _poly_aabb(pi).grow(gap_tol)
            var bb_j := _poly_aabb(pj).grow(gap_tol)
            if not bb_i.intersects(bb_j):
                continue
            var shared := _shared_edge_length(pi, pj, gap_tol)
            if shared >= edge_min or _min_gap(pi, pj) <= gap_tol:
                pairs.append(Vector2i(i, j))
    return pairs

static func load_resplan_as_programs(dir_path: String) -> Array:
    var manifest_path := dir_path.path_join("plans_manifest.jsonl")
    var result: Array = []
    if not FileAccess.file_exists(manifest_path):
        push_warning("ResPlan manifest not found: %s" % manifest_path)
        return result
    var manifest := FileAccess.open(manifest_path, FileAccess.READ)
    if manifest == null:
        push_warning("Unable to open ResPlan manifest: %s" % manifest_path)
        return result
    while not manifest.eof_reached():
        var line := manifest.get_line().strip_edges()
        if line.is_empty():
            continue
        var parsed := JSON.parse_string(line)
        if typeof(parsed) != TYPE_DICTIONARY:
            continue
        var meta: Dictionary = parsed
        var json_rel := String(meta.get("json", ""))
        if json_rel.is_empty():
            continue
        var plan_path := dir_path.path_join(json_rel)
        if not FileAccess.file_exists(plan_path):
            continue
        var file := FileAccess.open(plan_path, FileAccess.READ)
        if file == null:
            continue
        var plan_data := JSON.parse_string(file.get_as_text())
        file.close()
        if typeof(plan_data) != TYPE_DICTIONARY:
            continue
        var plan_dict: Dictionary = plan_data
        var rooms_raw := plan_dict.get("rooms", [])
        if rooms_raw is not Array or (rooms_raw as Array).is_empty():
            continue
        var rooms: Array = []
        for entry in rooms_raw:
            if typeof(entry) != TYPE_DICTIONARY:
                continue
            var entry_dict: Dictionary = entry
            var points_raw := entry_dict.get("polygon", [])
            if points_raw is not Array:
                continue
            var poly := PackedVector2Array()
            for point in points_raw:
                if point is Array and point.size() >= 2:
                    poly.push_back(Vector2(float(point[0]), float(point[1])))
            if poly.size() < 3:
                continue
            var label := _norm_label(String(entry_dict.get("label", "Room")))
            rooms.append({
                "type": label,
                "poly": poly,
                "area": _poly_area(poly),
                "aspect": _poly_aspect(poly),
            })
        if rooms.is_empty():
            continue
        var bbox := _poly_aabb(rooms[0]["poly"])
        var total_area := float(rooms[0]["area"])
        for idx in range(1, rooms.size()):
            bbox = bbox.merge(_poly_aabb(rooms[idx]["poly"]))
            total_area += float(rooms[idx]["area"])
        var adj_pairs := _infer_adjacency_from_polys(rooms)
        var program := {
            "id": meta.get("id", ""),
            "total_m2": total_area,
            "footprint_w": bbox.size.x,
            "footprint_d": bbox.size.y,
            "footprint": Vector2(bbox.size.x, bbox.size.y),
            "rooms": [],
            "adj_pairs": adj_pairs,
        }
        for i in range(rooms.size()):
            var room_data: Dictionary = rooms[i]
            program["rooms"].append({
                "id": "room_%d" % i,
                "type": room_data.get("type", "Room"),
                "area": room_data.get("area", 0.0),
                "aspect": room_data.get("aspect", 1.0),
                "poly": room_data.get("poly", PackedVector2Array()),
            })
        result.append(program)
    manifest.close()
    if DEBUG_VERIFY:
        print("[RESPLAN] loaded=%d" % result.size())
    return result

static func _adj_key(a: String, b: String) -> String:
    var a_low := a
    var b_low := b
    if a_low > b_low:
        var tmp := a_low
        a_low = b_low
        b_low = tmp
    return "%s|%s" % [a_low, b_low]

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
    var adj_summary: Dictionary = {}

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

    var exported: Array = []
    for prog in instances:
        exported.append(_program_to_dict(prog))

    var schema := _build_schema(exported, edges)
    var adj_pairs_variant := schema.get("adj_pairs", [])
    var adj_pairs: Array = []
    if adj_pairs_variant is Array:
        adj_pairs = adj_pairs_variant.duplicate()
    for inst in exported:
        if typeof(inst) != TYPE_DICTIONARY:
            continue
        var dict_inst: Dictionary = inst
        for label in adj_pairs:
            var exist_key := "adj_%s_exist" % label
            if not dict_inst.has(exist_key):
                dict_inst[exist_key] = 0

    var result := {
        "schema": schema,
        "instances": exported,
    }
    if DEBUG_VERIFY:
        _dbg_bins(schema, exported)
    return result

static func _dbg_bins(schema: Dictionary, insts: Array) -> void:
    if insts.is_empty():
        print("[BIN] empty corpus")
        return
    var room_types_count := 0
    var room_types_var := schema.get("room_types")
    if room_types_var is Array:
        room_types_count = (room_types_var as Array).size()
    var edges_dict_variant := schema.get("bin_edges", {})
    var total_bins := 0
    var footprint_bins := 0
    var area_bins := 0
    var aspect_bins := 0
    if edges_dict_variant is Dictionary:
        var edges_dict: Dictionary = edges_dict_variant
        total_bins = _edge_count(edges_dict.get("total_sqft"))
        var width_bins := _edge_count(edges_dict.get("width")) + 1
        var depth_bins := _edge_count(edges_dict.get("depth")) + 1
        footprint_bins = max(1, width_bins * depth_bins)
        area_bins = _edge_count(edges_dict.get("area"))
        aspect_bins = _edge_count(edges_dict.get("aspect"))
    else:
        total_bins = _edge_count(schema.get("total_m2_edges"))
        var footprint_w_bins := _edge_count(schema.get("footprint_w_edges")) + 1
        var footprint_d_bins := _edge_count(schema.get("footprint_d_edges")) + 1
        footprint_bins = max(1, footprint_w_bins * footprint_d_bins)
        area_bins = _edge_count(schema.get("room_area_edges"))
        aspect_bins = _edge_count(schema.get("aspect_edges"))
    var adj_pairs_count := int(schema.get("adj_pairs_count", 0))
    print("[BIN] instances=%d room_types=%d adj_pairs=%d" % [
        insts.size(),
        room_types_count,
        adj_pairs_count
    ])
    print("[BIN] bins: total_sqft=%d footprint=%d area=%d aspect=%d" % [
        total_bins,
        footprint_bins,
        area_bins,
        aspect_bins
    ])
    var first_variant = insts[0]
    var first_dict: Dictionary = {}
    if typeof(first_variant) == TYPE_DICTIONARY:
        first_dict = first_variant
    else:
        first_dict = _program_to_dict(first_variant)
    var sample_rooms := 0
    var sample_rooms_variant := first_dict.get("rooms", [])
    if sample_rooms_variant is Array:
        sample_rooms = (sample_rooms_variant as Array).size()
    print("[BIN] sample: total_sqft_bin=%s footprint_bin=%s rooms=%d footprint_pair=%s" % [
        str(first_dict.get("total_m2_bin", first_dict.get("total_sqft_bin", -1))),
        str(first_dict.get("footprint_bin", -1)),
        sample_rooms,
        str(first_dict.get("footprint_bin_pair", Vector2i.ZERO))
    ])
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
    var w_bin_count := w_edges.size() + 1
    var d_bin_count := d_edges.size() + 1
    var footprint_id := w_bin * d_bin_count + d_bin

    _set_field(prog, "total_sqft_bin", total_bin)
    _set_field(prog, "total_m2_bin", total_bin)
    _set_field(prog, "footprint_w_bin", w_bin)
    _set_field(prog, "footprint_d_bin", d_bin)
    _set_field(prog, "footprint_bin", footprint_id)
    _set_field(prog, "footprint_bin_pair", Vector2i(w_bin, d_bin))

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
    var pair_summary: Dictionary = {}
    var pair_lookup := {}

    var precomputed_pairs := _prog_adj_pairs_list(prog)
    if not precomputed_pairs.is_empty():
        for entry in precomputed_pairs:
            var a_idx := -1
            var b_idx := -1
            var exist_flag := true
            var pair_label := ""
            if entry is Vector2i:
                var pair_vec: Vector2i = entry
                a_idx = pair_vec.x
                b_idx = pair_vec.y
            elif typeof(entry) == TYPE_DICTIONARY:
                var entry_dict: Dictionary = entry
                a_idx = int(entry_dict.get("a", entry_dict.get("x", -1)))
                b_idx = int(entry_dict.get("b", entry_dict.get("y", -1)))
                exist_flag = int(entry_dict.get("exist", 1)) > 0
                pair_label = String(entry_dict.get("pair", pair_label))
            if a_idx < 0 or b_idx < 0 or a_idx >= rooms.size() or b_idx >= rooms.size():
                continue
            var ai := min(a_idx, b_idx)
            var bi := max(a_idx, b_idx)
            var key := "%d|%d" % [ai, bi]
            if pair_label == "":
                var type_a := String(rooms[ai].get("type", "Room"))
                var type_b := String(rooms[bi].get("type", "Room"))
                pair_label = _room_pair_label(type_a, type_b)
            if exist_flag:
                pair_lookup[key] = pair_label
                pair_summary[pair_label] = true
            elif not pair_summary.has(pair_label):
                pair_summary[pair_label] = false
    else:
        var edges_src: Array = []
        if prog is ProgramInstance:
            var inst: ProgramInstance = prog
            if inst.adjacencies.size() > 0:
                edges_src = inst.adjacencies
            elif inst.adj_pairs.size() > 0:
                edges_src = inst.adj_pairs
        elif typeof(prog) == TYPE_DICTIONARY:
            var dict_prog2: Dictionary = prog
            var raw_adj = dict_prog2.get("adjacencies")
            if raw_adj is Array:
                edges_src = raw_adj
            elif dict_prog2.has("adj_pairs"):
                edges_src = dict_prog2.get("adj_pairs")
        if edges_src.is_empty():
            var legacy_edges: Variant = null
            if prog is ProgramInstance:
                legacy_edges = prog.get("edges")
            elif typeof(prog) == TYPE_DICTIONARY:
                legacy_edges = (prog as Dictionary).get("edges")
            if legacy_edges is Array:
                edges_src = legacy_edges
        for edge in edges_src:
            var a_idx := -1
            var b_idx := -1
            if typeof(edge) == TYPE_DICTIONARY:
                a_idx = _resolve_room_index(edge, "a", id_to_idx, label_to_indices, label_cycle)
                if a_idx < 0:
                    a_idx = _resolve_room_index(edge, "a_id", id_to_idx, label_to_indices, label_cycle)
                b_idx = _resolve_room_index(edge, "b", id_to_idx, label_to_indices, label_cycle)
                if b_idx < 0:
                    b_idx = _resolve_room_index(edge, "b_id", id_to_idx, label_to_indices, label_cycle)
            elif edge is Vector2i:
                var edge_vec: Vector2i = edge
                a_idx = edge_vec.x
                b_idx = edge_vec.y
            if a_idx < 0 or b_idx < 0 or a_idx >= rooms.size() or b_idx >= rooms.size():
                continue
            var ai := min(a_idx, b_idx)
            var bi := max(a_idx, b_idx)
            var key := "%d|%d" % [ai, bi]
            var type_a := String(rooms[ai].get("type", "Room"))
            var type_b := String(rooms[bi].get("type", "Room"))
            var pair_label := _room_pair_label(type_a, type_b)
            pair_lookup[key] = pair_label
            pair_summary[pair_label] = true

    for i in range(rooms.size()):
        for j in range(i + 1, rooms.size()):
            var type_a := String(rooms[i].get("type", "Room"))
            var type_b := String(rooms[j].get("type", "Room"))
            var pair_label := _room_pair_label(type_a, type_b)
            var key := "%d|%d" % [i, j]
            var exists := pair_lookup.has(key)
            var exist_flag := 1 if exists else 0
            adj_pairs.append({
                "a": i,
                "b": j,
                "pair": pair_label,
                "exist": exist_flag
            })
            if not pair_summary.has(pair_label):
                pair_summary[pair_label] = exists
            elif exists:
                pair_summary[pair_label] = true

    _set_field(prog, "adj_pairs", adj_pairs)
    var summary_out := {}
    for label in pair_summary.keys():
        summary_out[label] = {"exist": bool(pair_summary[label])}
        _set_field(prog, "adj_%s_exist" % label, 1 if pair_summary[label] else 0)
    _set_field(prog, "adj_summary", summary_out)

    var counts: Dictionary = {}
    var exists: Dictionary = {}
    var count_bins: Dictionary = {}
    for room_type in label_counts.keys():
        var count := int(label_counts[room_type])
        counts[room_type] = count
        var exists_key := "%s_exists" % room_type
        var count_key := "%s_count" % room_type
        var exist_flag := count > 0
        exists[exists_key] = 1 if exist_flag else 0
        count_bins["%s_count_bin" % room_type] = _count_to_bin(count)
        _set_field(prog, exists_key, 1 if exist_flag else 0)
        _set_field(prog, count_key, count)

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
        result["footprint_bin_pair"] = Vector2i(inst.footprint_w_bin, inst.footprint_d_bin)
        result["room_counts"] = inst.room_counts.duplicate()
        result["room_exists"] = inst.room_exists.duplicate()
        result["room_count_bins"] = inst.room_count_bins.duplicate()
        for room_type in inst.room_counts.keys():
            var count_key := "%s_count" % room_type
            result[count_key] = int(inst.room_counts[room_type])
        for exists_key in inst.room_exists.keys():
            result[exists_key] = inst.room_exists[exists_key]
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
        if inst.adj_summary is Dictionary:
            var summary_dict: Dictionary = inst.adj_summary
            for pair_label in summary_dict.keys():
                var summary: Dictionary = summary_dict[pair_label]
                result["adj_%s_exist" % pair_label] = 1 if summary.get("exist", false) else 0
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
        result["footprint_bin_pair"] = dict_prog.get("footprint_bin_pair", Vector2i(dict_prog.get("footprint_w_bin", -1), dict_prog.get("footprint_d_bin", -1)))
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
        var summary_dict_any = dict_prog.get("adj_summary", {})
        if summary_dict_any is Dictionary:
            var summary_dict: Dictionary = summary_dict_any
            for pair_label in summary_dict.keys():
                var summary: Dictionary = summary_dict[pair_label]
                result["adj_%s_exist" % pair_label] = 1 if summary.get("exist", false) else 0
        var counts_dict_any = dict_prog.get("room_counts", {})
        if counts_dict_any is Dictionary:
            var counts_dict: Dictionary = counts_dict_any
            for room_type in counts_dict.keys():
                result["%s_count" % room_type] = int(counts_dict[room_type])
        var exists_dict_any = dict_prog.get("room_exists", {})
        if exists_dict_any is Dictionary:
            var exists_dict: Dictionary = exists_dict_any
            for exists_key in exists_dict.keys():
                result[exists_key] = exists_dict[exists_key]
        return result
    return result

static func _build_schema(programs: Array, edges: Dictionary) -> Dictionary:
    var room_types := {}
    var count_max := {}
    var adj_labels := {}

    for prog in programs:
        if typeof(prog) != TYPE_DICTIONARY:
            continue
        var dict_prog: Dictionary = prog
        var counts: Dictionary = dict_prog.get("room_counts", {})
        for t in counts.keys():
            room_types[t] = true
            var c := int(counts[t])
            var prev := int(count_max.get(t, 0))
            if c > prev:
                count_max[t] = c
        for pair in dict_prog.get("adj_pairs", []):
            if pair is Dictionary:
                var label := String(pair.get("pair", ""))
                if label != "":
                    adj_labels[label] = true
        var summary_variant := dict_prog.get("adj_summary", {})
        if summary_variant is Dictionary:
            var summary_dict: Dictionary = summary_variant
            for label in summary_dict.keys():
                if String(label) != "":
                    adj_labels[String(label)] = true

    var room_type_list: Array = room_types.keys()
    room_type_list.sort()
    var adj_list: Array = adj_labels.keys()
    adj_list.sort()

    var schema := {
        "total_m2_edges": edges.get("total_m2_edges", PackedFloat64Array()),
        "footprint_w_edges": edges.get("footprint_w_edges", PackedFloat64Array()),
        "footprint_d_edges": edges.get("footprint_d_edges", PackedFloat64Array()),
        "room_area_edges": edges.get("room_area_edges", PackedFloat64Array()),
        "aspect_edges": edges.get("aspect_edges", PackedFloat64Array()),
        "room_types": room_type_list,
        "adj_pairs": adj_list,
        "count_max_by_type": count_max,
        "adj_type_labels": [],
        "exist_labels": [0, 1],
        "area_labels": {},
        "aspect_labels": {},
    }
    schema["adj_pairs_count"] = adj_list.size()
    var bin_edges_dict := {
        "total_sqft": schema.get("total_m2_edges", PackedFloat64Array()),
        "width": schema.get("footprint_w_edges", PackedFloat64Array()),
        "depth": schema.get("footprint_d_edges", PackedFloat64Array()),
        "area": schema.get("room_area_edges", PackedFloat64Array()),
        "aspect": schema.get("aspect_edges", PackedFloat64Array()),
    }
    schema["bin_edges"] = bin_edges_dict
    var w_bins_count := 1
    var d_bins_count := 1
    var w_edges_variant := schema.get("footprint_w_edges", PackedFloat64Array())
    if w_edges_variant is PackedFloat64Array:
        w_bins_count = (w_edges_variant as PackedFloat64Array).size() + 1
    var d_edges_variant := schema.get("footprint_d_edges", PackedFloat64Array())
    if d_edges_variant is PackedFloat64Array:
        d_bins_count = (d_edges_variant as PackedFloat64Array).size() + 1
    schema["footprint_w_bin_count"] = w_bins_count
    schema["footprint_d_bin_count"] = d_bins_count
    schema["footprint_bin_count"] = w_bins_count * d_bins_count

    var area_edges: PackedFloat64Array = schema["room_area_edges"]
    var aspect_edges: PackedFloat64Array = schema["aspect_edges"]
    for t in room_type_list:
        schema["area_labels"][t] = _labels_from_edges("%s_area" % t, area_edges)
        schema["aspect_labels"][t] = _labels_from_edges("%s_aspect" % t, aspect_edges)

    return schema
static func save_binned_corpus(path: String, binning: Dictionary) -> void:
    var payload := {
        "schema": binning.get("schema", {}),
        "instances": [],
    }
    var instances: Array = binning.get("instances", [])
    for prog in instances:
        if typeof(prog) == TYPE_DICTIONARY:
            payload["instances"].append(prog)
        else:
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

static func _labels_from_edges(name: String, edges: PackedFloat64Array) -> Array:
    if edges.is_empty():
        return ["%s_any" % name]
    var labels: Array = []
    var previous := float(edges[0])
    labels.append("%s<=%.2f" % [name, float(edges[0])])
    for i in range(1, edges.size()):
        var upper := float(edges[i])
        labels.append("%.2f<%s<=%.2f" % [previous, name, upper])
        previous = upper
    labels.append("%s>%.2f" % [name, float(edges[edges.size() - 1])])
    return labels
static func _edge_count(value) -> int:
    if value is PackedFloat64Array:
        return (value as PackedFloat64Array).size()
    if value is Array:
        return (value as Array).size()
    return 0

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
