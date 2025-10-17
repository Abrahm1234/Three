extends Node3D

const EPS := 1e-4

const GeomUtils := preload("res://addons/res_layout3d/GeomUtils.gd")

const USE_RESPLAN := true
const RESPLAN_DIR := "res://addons/res_layout3d/data/datasets/resplan"

func _edge_key(axis: String, c: float) -> String:
	return "%s@%.5f" % [axis, c]

func _edge_params_from_shared_wall(w: Dictionary) -> Dictionary:
	if w.is_empty(): return {}
	var axis: String = String(w.get("axis", ""))
	var s: Vector2 = w.get("start", Vector2.ZERO)
	var e: Vector2 = w.get("end", Vector2.ZERO)
	var c: float
	var a: float
	var b: float
	if axis == "x":
		c = s.y
		a = min(s.x, e.x)
		b = max(s.x, e.x)
	else:
		c = s.x
		a = min(s.y, e.y)
		b = max(s.y, e.y)
	return {"axis": axis, "c": c, "a": a, "b": b}

func _collect_unique_edges(part: Partition) -> Dictionary:
	var idx := {}
	for i in range(part.rooms.size()):
		var A := part.rooms[i].rect
		for j in range(i + 1, part.rooms.size()):
			var B := part.rooms[j].rect
			var w := GeomUtils.shared_wall(A, B)
			if w.is_empty(): continue
			var p := _edge_params_from_shared_wall(w)
			var axis: String = p["axis"]
			var c: float = p["c"]
			var a: float = p["a"]
			var b: float = p["b"]
			if b - a <= EPS: continue
			var k := _edge_key(axis, c)
			if not idx.has(k):
				idx[k] = {
					"axis": axis, "c": c,
					"runs": [],
					"doors": [],
					"thickness": part.wall_thickness_m
				}
			idx[k]["runs"].append(Vector2(a, b))
	return idx

func _merge_runs(runs: Array) -> Array[Vector2]:
	var items: Array[Vector2] = []
	for v in runs:
		if typeof(v) == TYPE_VECTOR2:
			items.append(v as Vector2)
	if items.is_empty():
		return items
	items.sort_custom(Callable(self, "_span_sort"))
	var out: Array[Vector2] = []
	var cur: Vector2 = items[0]
	for i in range(1, items.size()):
		var r: Vector2 = items[i]
		if r.x <= cur.y + EPS:
			cur.y = max(cur.y, r.y)
		else:
			out.append(cur)
			cur = r
	out.append(cur)
	return out

func _subtract_spans(base: Array[Vector2], holes: Array[Vector2]) -> Array[Vector2]:
	if holes.is_empty():
		return base
	var H: Array[Vector2] = _merge_runs(holes)
	var out: Array[Vector2] = []
	for seg in base:
		var s := seg.x
		var e := seg.y
		for h in H:
			if h.y <= s or h.x >= e: continue
			if h.x > s + EPS:
				out.append(Vector2(s, min(h.x, e)))
			s = max(s, h.y)
			if s >= e - EPS: break
		if s < e - EPS:
			out.append(Vector2(s, e))
	return out

func _door_spans_for_edge(axis: String, c: float, a: float, b: float, doors: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for d in doors:
		if d["axis"] != axis: continue
		if abs(d["c"] - c) > EPS: continue
		var s: Vector2 = d["span"]
		var ds := max(a, s.x)
		var de := min(b, s.y)
		if de - ds > EPS:
			out.append(Vector2(ds, de))
	return out

func _draw_wall_segment_centerline(axis: String, c: float, s0: float, s1: float, thickness: float) -> void:
	var wall := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	var length := s1 - s0
	var mid := (s0 + s1) * 0.5
	
	if axis == "x":
		mesh.size = Vector3(length, WALL_H, thickness)
		wall.transform = Transform3D(Basis(), Vector3(mid, WALL_H * 0.5, c))
	else:
		mesh.size = Vector3(thickness, WALL_H, length)
		wall.transform = Transform3D(Basis(), Vector3(c, WALL_H * 0.5, mid))
	
	wall.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.85, 0.88)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.roughness = 1.0
	wall.material_override = mat
	rooms_root.add_child(wall)

func _build_walls_unique(part: Partition, doors: Array) -> void:
	var edges := _collect_unique_edges(part)
	for k in edges.keys():
		var rec = edges[k]
		var axis: String = rec["axis"]
		var c: float = rec["c"]
		var runs: Array[Vector2] = _merge_runs(rec["runs"])
		var holes: Array[Vector2] = []
		for r in runs:
			for h in _door_spans_for_edge(axis, c, r.x, r.y, doors):
				holes.append(h)
		var cleaned: Array[Vector2] = _subtract_spans(runs, holes)
		for r in cleaned:
			var seg_len := r.y - r.x
			if seg_len <= EPS:
				continue
			var trim := clamp(part.wall_thickness_m * 0.5, 0.02, 0.10)
			var s0: float = r.x + trim
			var s1: float = r.y - trim
			if s1 - s0 <= EPS:
				continue
			_draw_wall_segment_centerline(axis, c, s0, s1, part.wall_thickness_m)

func _build_exterior_walls(part: Partition, doors: Array) -> void:
	if part == null or part.footprint.size == Vector2.ZERO:
		return
	
	var tolerance := max(part.grid.step_m * 0.25, 1e-4)
	var footprint := part.footprint
	var fp_end := footprint.position + footprint.size
	var exterior_edges := {}
	
	for room in part.rooms:
		var rect := room.rect
		var rect_end := rect.position + rect.size
		
		if abs(rect.position.y - footprint.position.y) <= tolerance:
			var axis := "x"
			var c := footprint.position.y
			var key := _edge_key(axis, c)
			if not exterior_edges.has(key):
				exterior_edges[key] = {"axis": axis, "c": c, "runs": []}
			exterior_edges[key]["runs"].append(Vector2(rect.position.x, rect_end.x))
		
		if abs(rect_end.y - fp_end.y) <= tolerance:
			var axis := "x"
			var c := fp_end.y
			var key := _edge_key(axis, c)
			if not exterior_edges.has(key):
				exterior_edges[key] = {"axis": axis, "c": c, "runs": []}
			exterior_edges[key]["runs"].append(Vector2(rect.position.x, rect_end.x))
		
		if abs(rect.position.x - footprint.position.x) <= tolerance:
			var axis := "z"
			var c := footprint.position.x
			var key := _edge_key(axis, c)
			if not exterior_edges.has(key):
				exterior_edges[key] = {"axis": axis, "c": c, "runs": []}
			exterior_edges[key]["runs"].append(Vector2(rect.position.y, rect_end.y))
		
		if abs(rect_end.x - fp_end.x) <= tolerance:
			var axis := "z"
			var c := fp_end.x
			var key := _edge_key(axis, c)
			if not exterior_edges.has(key):
				exterior_edges[key] = {"axis": axis, "c": c, "runs": []}
			exterior_edges[key]["runs"].append(Vector2(rect.position.y, rect_end.y))
	
	for key in exterior_edges.keys():
		var rec = exterior_edges[key]
		var axis: String = rec["axis"]
		var c: float = rec["c"]
		var runs: Array[Vector2] = _merge_runs(rec["runs"])
		var holes: Array[Vector2] = []
		for r in runs:
			for h in _door_spans_for_edge(axis, c, r.x, r.y, doors):
				holes.append(h)
		var cleaned: Array[Vector2] = _subtract_spans(runs, holes)
		for r in cleaned:
			var seg_len := r.y - r.x
			if seg_len <= EPS:
				continue
			_draw_wall_segment_centerline(axis, c, r.x, r.y, part.wall_thickness_m)

const HouseStyle := preload("res://addons/res_layout3d/styles/HouseStyle.gd")
const RandomCtx := preload("res://addons/res_layout3d/core/RandomCtx.gd")
const PartitionIO := preload("res://addons/res_layout3d/partition/PartitionIO.gd")
const Partition := preload("res://addons/res_layout3d/partition/Partition.gd")
const Doors := preload("res://addons/res_layout3d/plan/Doors.gd")
const PlanCost := preload("res://addons/res_layout3d/plan/PlanCost.gd")
const Annealer := preload("res://addons/res_layout3d/opt/Annealer.gd")
const BubbleOverlay := preload("res://addons/res_layout3d/BubbleOverlay.gd")

@onready var rooms_root: Node3D = $"Rooms"
@onready var new_btn: Button = $"UI/Root/Panel/VBox/Header/NewBtn"
@onready var sample_btn: Button = $"UI/Root/Panel/VBox/Header/SampleBtn"
@onready var opt_btn: Button = $"UI/Root/Panel/VBox/Header/OptimizeBtn"
@onready var run_btn: Button = $"UI/Root/Panel/VBox/Bottom/RunBtn"
@onready var floors_sb: SpinBox = $"UI/Root/Panel/VBox/Grid/Floors"
@onready var bedrooms_sb: SpinBox = $"UI/Root/Panel/VBox/Grid/Bedrooms"
@onready var bathrooms_sb: SpinBox = $"UI/Root/Panel/VBox/Grid/Bathrooms"
@onready var sqft_sb: SpinBox = $"UI/Root/Panel/VBox/Grid/Sqft"
@onready var footprint_le: LineEdit = $"UI/Root/Panel/VBox/Grid/Footprint"
@onready var cost_tree: Tree = $"UI/Root/Panel/VBox/CostTree"
@onready var seeds_sb: SpinBox = $"UI/Root/Panel/VBox/BatchBar/Seeds"
@onready var batch_btn: Button = $"UI/Root/Panel/VBox/BatchBar/BatchBtn"
@onready var style_btn: Button = $"UI/Root/Panel/VBox/BatchBar/StyleBtn"
@onready var export_svg_btn: Button = $"UI/Root/Panel/VBox/BatchBar/ExportSvgBtn"
@onready var export_gltf_btn: Button = $"UI/Root/Panel/VBox/BatchBar/ExportGltfBtn"
@onready var save_plan_btn: Button = $"UI/Root/Panel/VBox/BatchBar/SavePlanBtn"
@onready var load_plan_btn: Button = $"UI/Root/Panel/VBox/BatchBar/LoadPlanBtn"
@onready var batch_header: Label = $"UI/Root/Panel/VBox/BatchHeader"
@onready var batch_container: FlowContainer = $"UI/Root/Panel/VBox/BatchResults"
@onready var w_access: SpinBox = $"UI/Root/Panel/VBox/WeightsGrid/WAccess"
@onready var w_dims: SpinBox = $"UI/Root/Panel/VBox/WeightsGrid/WDims"
@onready var w_floors: SpinBox = $"UI/Root/Panel/VBox/WeightsGrid/WFloors"
@onready var w_shape: SpinBox = $"UI/Root/Panel/VBox/WeightsGrid/WShape"
@onready var w_exposure: SpinBox = $"UI/Root/Panel/VBox/WeightsGrid/WExposure"
@onready var ui_root: Control = $"UI/Root"
@onready var ui_panel: Panel = $"UI/Root/Panel"
@onready var overlay_chk: CheckButton = $"UI/Root/Panel/VBox/Header/OverlayChk"
@onready var roof_chk: CheckButton = $"UI/Root/Panel/VBox/Header/RoofChk"
@onready var adj_list: ItemList = $"UI/Root/Panel/VBox/AdjList"
@onready var beta: SpinBox = $"UI/Root/Panel/VBox/Bottom/Beta"
@onready var iters: SpinBox = $"UI/Root/Panel/VBox/Bottom/Iters"
@onready var bubble_ui: BubbleOverlay = $"%BubbleOverlay" if has_node("%BubbleOverlay") else null

@export_enum("Bubble","Schematic","Detailed") var view_stage := "Bubble"
@export var use_bn: bool = true
@export var styles: Array[HouseStyle] = []

var program: ArchitecturalProgram
var partition: Partition
var state: Dictionary = {}
var program_gen: ProgramGen
var overlay: BubbleOverlay
var plan_cost: PlanCost
var style := HouseStyle.new()
var style_idx := 0
var bn: ProgramBN
var R := RandomCtx.new()
var roof_root: Node3D

const WALL_H := 3.0
const DEBUG_VERIFY := true

func _ready() -> void:
	_bind_key("ui_stage_bubble", KEY_1)
	_bind_key("ui_stage_schematic", KEY_2)
	_bind_key("ui_stage_detailed", KEY_3)
	_bind_key("ui_floor_prev", KEY_PAGEUP)
	_bind_key("ui_floor_next", KEY_PAGEDOWN)
	_bind_key("toggle_roof", KEY_R)
	new_btn.pressed.connect(_new_program)
	sample_btn.pressed.connect(_sample_program)
	opt_btn.pressed.connect(_optimize_once)
	run_btn.pressed.connect(_optimize_many)
	batch_btn.pressed.connect(_on_batch_run_pressed)
	style_btn.pressed.connect(cycle_style)
	export_svg_btn.pressed.connect(func(): export_svg())
	export_gltf_btn.pressed.connect(func(): export_gltf())
	save_plan_btn.pressed.connect(func(): save_plan())
	load_plan_btn.pressed.connect(func(): load_plan())
	add_child(R)

	R.reseed(Time.get_ticks_msec())
	print("✓ RNG seeded with: %d" % Time.get_ticks_msec())

	program_gen = ProgramGen.new()
	add_child(program_gen)
	bn = ProgramBN.new()
	if bn and bn.has_method("configure_rng"):
		bn.configure_rng(R)
	add_child(bn)

	var TrainingDataClass = load("res://addons/res_layout3d/data/TrainingData.gd")
	var corpus: Array = []
	var used_resplan := false
	if USE_RESPLAN and TrainingDataClass.has_method("load_resplan_as_programs"):
		corpus = TrainingDataClass.load_resplan_as_programs(RESPLAN_DIR)
		used_resplan = true
	if corpus.is_empty():
		if used_resplan and DEBUG_VERIFY:
			print("[RESPLAN] corpus empty, falling back to synthetic defaults")
		var training_data = TrainingDataClass.create_default()
		corpus.append_array(training_data.single_story)
		corpus.append_array(training_data.two_story)
		corpus.append_array(training_data.three_story)
        var binning: Dictionary = TrainingDataClass.bin_corpus(corpus)
	var schema: Dictionary = binning.get("schema", {})
	if bn and bn.has_method("configure_from_schema"):
		bn.configure_from_schema(schema)
		var binned_instances: Array = binning.get("instances", [])
		if bn and bn.has_method("train_binned"):
			bn.train_binned(binned_instances, schema)
			print("✓ Bayesian Network trained with %d instances" % binned_instances.size())
			if DEBUG_VERIFY:
				var room_types_count := 0
				var room_types_variant := schema.get("room_types")
				if room_types_variant is Array:
					room_types_count = (room_types_variant as Array).size()
				var adj_pairs_count := int(schema.get("adj_pairs_count", 0))
				if adj_pairs_count == 0:
					var adj_variant := schema.get("adj_pairs")
					if adj_variant is Array:
						adj_pairs_count = (adj_variant as Array).size()
				print("[PLAN] BN ready. room_types=%d adj_pairs=%d" % [room_types_count, adj_pairs_count])
	w_access.value_changed.connect(func(_v): _apply_weights())
	w_dims.value_changed.connect(func(_v): _apply_weights())
	w_shape.value_changed.connect(func(_v): _apply_weights())
	w_exposure.value_changed.connect(func(_v): _apply_weights())
	for sb in [floors_sb, bedrooms_sb, bathrooms_sb, sqft_sb]:
		sb.value_changed.connect(func(_v): _new_program())
	footprint_le.text_submitted.connect(func(_text): _new_program())
	w_floors.value_changed.connect(func(_v): _apply_weights())
	
	var ui_root_node := $"UI/Root"
	_ensure_overlay()
	overlay.name = "BubbleOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.z_index = -100
	ui_root_node.add_child(overlay)
	overlay_chk.toggled.connect(func(pressed: bool) -> void:
		if overlay: overlay.visible = pressed and view_stage == "Bubble"
	)
	overlay.visible = overlay_chk.button_pressed and view_stage == "Bubble"
	_ensure_roof_root()
	roof_chk.toggled.connect(func(on: bool):
		if is_instance_valid(roof_root):
			roof_root.visible = on
	)
	_rescale_ui()
	ui_root_node.resized.connect(_rescale_ui)
	if cost_tree != null:
		cost_tree.columns = 2
		cost_tree.hide_root = true
		cost_tree.set_column_titles_visible(true)
		cost_tree.set_column_title(0, "Term")
		cost_tree.set_column_title(1, "Value")
	plan_cost = PlanCost.new()
	if styles.size() > 0:
		style_idx = 0
		style = styles[0]
	_apply_weights()
	_new_program()
	if is_instance_valid(roof_root):
		roof_root.visible = roof_chk.button_pressed

func _ensure_roof_root() -> void:
	if not is_instance_valid(roof_root):
		roof_root = Node3D.new()
		roof_root.name = "Roof"
		rooms_root.add_child(roof_root)

func _bind_key(action: StringName, keycode: int) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var events := InputMap.action_get_events(action)
	for existing in events:
		if existing is InputEventKey and existing.physical_keycode == keycode:
			return
	var ev := InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)

func _unhandled_input(e: InputEvent) -> void:
	if InputMap.has_action("ui_stage_bubble") and e.is_action_pressed("ui_stage_bubble"):
		set_stage("Bubble")
	elif InputMap.has_action("ui_stage_schematic") and e.is_action_pressed("ui_stage_schematic"):
		set_stage("Schematic")
	elif InputMap.has_action("ui_stage_detailed") and e.is_action_pressed("ui_stage_detailed"):
		set_stage("Detailed")
	elif InputMap.has_action("ui_floor_prev") and e.is_action_pressed("ui_floor_prev"):
		if bubble_ui and program:
			var next_floor := max(0, (bubble_ui.current_floor if bubble_ui != null else 0) - 1)
			show_bubble_for(program, next_floor)
	elif InputMap.has_action("ui_floor_next") and e.is_action_pressed("ui_floor_next"):
		if bubble_ui and program:
			var next_floor := (bubble_ui.current_floor if bubble_ui != null else 0) + 1
			show_bubble_for(program, next_floor)
	elif InputMap.has_action("toggle_roof") and e.is_action_pressed("toggle_roof"):
		roof_chk.button_pressed = not roof_chk.button_pressed

func _new_program() -> void:
	var req := {
		"footprint": _read_footprint(),
		"sq_m2": float(sqft_sb.value),
		"floors": int(floors_sb.value),
		"bedrooms": int(bedrooms_sb.value),
		"bathrooms": int(bathrooms_sb.value),
	}

	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("REQ: ", req)
	if use_bn:
		program = bn.sample(req)
	else:
		program = program_gen.sample(req)
	print("✓ Generated: rooms=%d edges=%d" % [program.rooms.size(), program.edges.size()])
	print("  Room types: %s" % [_get_room_types_summary(program)])
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

	_update_adj_list()
	_clear_batch_results()
	show_bubble_for(program)
	_seed_state_from_program(program)
	_rebuild_meshes()

	print("⏳ Auto-optimizing initial layout...")
	var quick_steps := max(500, int(iters.value) / 10)
	var optimized := _optimize_partition(quick_steps, partition)
	if optimized != null:
		partition = optimized
		_update_state_from_partition()
		_rebuild_meshes()

func _get_room_types_summary(prog: ArchitecturalProgram) -> String:
	var types := {}
	for room in prog.rooms:
		var t := String(room.get("type", "Unknown"))
		types[t] = types.get(t, 0) + 1
	var parts: PackedStringArray = []
	for t in types.keys():
		parts.append("%s×%d" % [t, types[t]])
	return ", ".join(parts)

func _sample_program() -> void:
	_new_program()

func _read_footprint() -> Vector2i:
	var fp: Vector2i = Vector2i(16, 12)
	var text := footprint_le.text.strip_edges()
	if text.find("x") != -1:
		var parts: PackedStringArray = text.split("x")
		if parts.size() == 2:
			fp = Vector2i(parts[0].to_int(), parts[1].to_int())
	return fp

func _update_adj_list() -> void:
	if adj_list == null or program == null:
		return
	adj_list.clear()
	for e in program.edges:
		var ed: Dictionary = e
		adj_list.add_item("%s <-> %s (%s)" % [ed.get("a_id", ""), ed.get("b_id", ""), ed.get("kind", "")])

func _seed_state_from_program(prog: ArchitecturalProgram) -> void:
	if prog == null:
		return
	partition = PartitionIO.from_program_rect_seed(prog, 0.1)
	_update_state_from_partition()

func _door_key(a_id: String, b_id: String) -> String:
	return _unordered_key(a_id, b_id)

func _unordered_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if _id_less(a, b) else "%s|%s" % [b, a]

func _id_less(a: String, b: String) -> bool:
	if a.is_valid_int() and b.is_valid_int():
		return int(a) < int(b)
	return a < b

func _ids_by_room_index(part: Partition) -> Array[String]:
	var ids: Array[String] = []
	if part == null:
		return ids
	if program == null:
		for i in range(part.rooms.size()):
			ids.append(str(i))
		return ids
	for i in range(part.rooms.size()):
		ids.append(String(program.rooms[i].get("id", str(i))))
	return ids

func _allowed_door_types() -> Dictionary:
	var types := {}
	if program == null: return types
	for e in program.edges:
		var t := String(e.get("kind","door"))
		if t != "door" and t != "open": continue
		var a := String(e.get("a_id","")); var b := String(e.get("b_id",""))
		if a == "" or b == "": continue
		types[_unordered_key(a,b)] = t
	return types

func _room_rect_by_id(part: Partition, room_id: String) -> Rect2:
	if part == null or program == null:
		return Rect2()
	for i in range(part.rooms.size()):
		if i >= program.rooms.size():
			break
		var prog_id := String(program.rooms[i].get("id", str(i)))
		if prog_id == room_id:
			return part.rooms[i].rect
	return Rect2()

func _doors_from_partition_array(part: Partition) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if part == null or program == null:
		return out
	for e in program.edges:
		var a_id := String(e.get("a_id", ""))
		var b_id := String(e.get("b_id", ""))
		var typ := String(e.get("kind", "door"))
		var A := _room_rect_by_id(part, a_id)
		var B := _room_rect_by_id(part, b_id)
		if A == Rect2() or B == Rect2(): continue
		var w := GeomUtils.shared_wall(A, B)
		if w.is_empty(): continue
		var p := _edge_params_from_shared_wall(w)
		var axis: String = p["axis"]
		var c: float = p["c"]
		var a: float = p["a"]
		var b: float = p["b"]
		var span_len := b - a
		if span_len <= EPS: continue
		if typ == "open":
			out.append({"axis": axis, "c": c, "span": Vector2(a, b), "type": "open"})
		else:
			var mid := 0.5 * (a + b)
			var half := ((program.default_door_w if program != null else 0.9) * 0.5)
			out.append({"axis": axis, "c": c, "span": Vector2(mid - half, mid + half), "type": "door"})
	return out

func _doors_from_partition(part: Partition) -> Dictionary:
	var out := {}
	if part == null: return out
	var ids := _ids_by_room_index(part)
	var types := _allowed_door_types()
	
	print("🚪 _doors_from_partition: Found %d allowed door types" % types.size())
	if types.size() > 0:
		print("  Allowed: %s" % [types.keys()])
	
	for i in range(part.rooms.size()):
		for j in range(i + 1, part.rooms.size()):
			var a_id := ids[i]
			var b_id := ids[j]
			var key := _door_key(a_id, b_id)
			if not types.is_empty() and not types.has(key):
				continue
			
			var ra: Rect2 = part.rooms[i].rect
			var rb: Rect2 = part.rooms[j].rect
			var wall := GeomUtils.shared_wall(ra, rb)
			
			if wall.is_empty():
				continue
			
			var start: Vector2 = wall["start"]
			var end: Vector2 = wall["end"]
			var L := (end - start).length()
			if L <= 1e-6:
				continue
			
			var typ := String(types.get(key, "door"))
			var clearance := program.door_clear if program != null else 0.1
			var door_w := program.default_door_w if program != null else 0.9

			var corner_bias := 0.2
			var t := corner_bias if randf() < 0.5 else (1.0 - corner_bias)
			
			if typ == "open":
				door_w = max(0.0, L - 2.0 * clearance)
				t = 0.5
			
			var half := clamp(0.5 * door_w / max(1e-6, L), 0.01, 0.49)
			out[key] = {"t": clamp(t, half, 1.0 - half), "w": door_w}
			
			print("🚪 Created door: %s | type=%s t=%.2f w=%.2f" % [key, typ, t, door_w])
	
	print("✓ Total doors created: %d" % out.size())
	return out

func _allowed_idx_pairs(part: Partition) -> Array[Vector2i]:
	var pairs: Array[Vector2i] = []
	if program == null or part == null:
		return pairs
	if program.rooms.size() != part.rooms.size():
		return pairs
	var id_to_idx := {}
	for i in range(part.rooms.size()):
		var prog_id := String(program.rooms[i].get("id", str(i)))
		id_to_idx[prog_id] = i
	for edge in program.edges:
		var typ := String(edge.get("kind", ""))
		if typ != "door" and typ != "open":
			continue
		var a_id := String(edge.get("a_id", ""))
		var b_id := String(edge.get("b_id", ""))
		var a_idx := int(id_to_idx.get(a_id, -1))
		var b_idx := int(id_to_idx.get(b_id, -1))
		if a_idx < 0 or b_idx < 0:
			continue
		pairs.append(Vector2i(min(a_idx, b_idx), max(a_idx, b_idx)))
	return pairs

func _state_from_partition(part: Partition) -> Dictionary:
	if part == null:
		return {}
	var snap := part.to_state_rects()
	var mapped := {
		"outer": snap.get("outer", Rect2()),
		"rooms": {},
		"doors": {},
		"stairs": [],
	}
	if program != null and program.rooms.size() == part.rooms.size():
		for i in range(part.rooms.size()):
			var prog_id := String(program.rooms[i].get("id", str(i)))
			mapped["rooms"][prog_id] = snap.get("rooms", {}).get(str(i), {})
	else:
		mapped["rooms"] = snap.get("rooms", {})
	mapped["doors"] = _doors_from_partition(part)
	if snap.has("stairs"):
		mapped["stairs"] = snap["stairs"]
	return mapped

func _update_state_from_partition() -> void:
	if partition == null:
		state = {}
		return
	state = _state_from_partition(partition)
	_update_cost_ui()
	if is_instance_valid(overlay):
		if view_stage == "Bubble" and program != null:
			var floor_idx := bubble_ui.current_floor if bubble_ui != null else 0
			show_bubble_for(program, floor_idx)
		else:
			overlay.update_display(program, state)

func _program_terms() -> Dictionary:
	var terms := {}
	if program == null:
		return terms
	for room_def in program.rooms:
		var label := String(room_def.get("type", ""))
		if label == "":
			continue
		var entry := terms.get(label, {})
		entry["access_w"] = float(room_def.get("access_w", 1.0))
		entry["min_exterior"] = float(room_def.get("min_exterior", 0.0))
		entry["floor"] = int(room_def.get("floor", 0))
		terms[label] = entry
	return terms

func _entry_room_index_for(part: Partition) -> int:
	if part == null or part.rooms.is_empty():
		return 0
	for i in range(part.rooms.size()):
		var lbl := part.rooms[i].label.to_lower()
		if lbl == "entry" or lbl == "hall" or lbl == "foyer":
			return i
	var best_idx := 0
	var best_len := -INF
	for i in range(part.rooms.size()):
		var rect: Rect2 = part.rooms[i].rect
		var len := _exterior_len_for_room(part, rect)
		if len > best_len:
			best_len = len
			best_idx = i
	return best_idx

func _exterior_len_for_room(part: Partition, rect: Rect2) -> float:
	if part == null:
		return 0.0
	var tolerance := part.grid.step_m * 0.25
	var footprint := part.footprint
	var footprint_end := footprint.position + footprint.size
	var rect_end := rect.position + rect.size
	var length := 0.0
	if abs(rect.position.x - footprint.position.x) <= tolerance:
		length += rect.size.y
	if abs(rect_end.x - footprint_end.x) <= tolerance:
		length += rect.size.y
	if abs(rect.position.y - footprint.position.y) <= tolerance:
		length += rect.size.x
	if abs(rect_end.y - footprint_end.y) <= tolerance:
		length += rect.size.x
	return length

func _allowed_label_pairs() -> Dictionary:
	var out := {}
	if program == null: return out
	var id2label := {}
	for r in program.rooms:
		id2label[String(r.get("id",""))] = String(r.get("type",""))
	for e in program.edges:
		var t := String(e.get("kind",""))
		if t != "door" and t != "open": continue
		var a := id2label.get(String(e.get("a_id","")), "")
		var b := id2label.get(String(e.get("b_id","")), "")
		if a == "" or b == "": continue
		var k := _unordered_key(a, b)
		out[k] = true
	return out

func _metrics_for(part: Partition) -> Dictionary:
	if part == null or plan_cost == null:
		if plan_cost != null:
			var empty_pairs: Array[Vector2i] = []
			plan_cost.allowed_pairs = empty_pairs
		return {
			"access": 0.0,
			"privacy": 0.0,
			"dims": 0.0,
			"shape": 0.0,
			"exposure": 0.0,
			"overlap": 0.0,
			"total": 0.0,
		}
	var pairs := _allowed_idx_pairs(part)
	plan_cost.allowed_pairs = pairs
	plan_cost.allowed_label_pairs = _allowed_label_pairs()
	var terms := _program_terms()
	var entry_idx := _entry_room_index_for(part)
	var access: float = plan_cost.C_access(part, entry_idx, terms)
	var privacy: float = plan_cost.C_privacy(part, entry_idx)
	var dims: float = plan_cost.C_dims(part)
	var shape: float = plan_cost.C_shape(part)
	var exposure: float = plan_cost.C_exposure(part, terms)
	var overlap: float = plan_cost.C_overlap(part)
	var total: float = plan_cost.total(part, entry_idx, terms)
	return {
		"access": access,
		"privacy": privacy,
		"dims": dims,
		"shape": shape,
		"exposure": exposure,
		"overlap": overlap,
		"total": total,
	}

func _copy_partition(src: Partition) -> Partition:
	if src == null:
		return null
	var copy := Partition.new()
	copy.grid.step_m = src.grid.step_m
	copy.wall_thickness_m = src.wall_thickness_m
	copy.footprint = Rect2(src.footprint.position, src.footprint.size)
	for room in src.rooms:
		var new_room := Partition.Room.new()
		new_room.id = room.id
		new_room.label = room.label
		new_room.rect = Rect2(room.rect.position, room.rect.size)
		new_room.floor = room.floor
		copy.rooms.append(new_room)
	return copy

func _optimize_partition(iterations: int, source: Partition) -> Partition:
	var working := _copy_partition(source)
	if working == null:
		return null
	var steps := max(1, iterations)
	var entry_idx := _entry_room_index_for(working)
	var terms := _program_terms()
	plan_cost.allowed_pairs = _allowed_idx_pairs(working)
	plan_cost.allowed_label_pairs = _allowed_label_pairs()
	var annealer := Annealer.new()
	annealer.iters = steps
	annealer.t0 = max(0.01, float(beta.value))
	var decay := pow(0.01, 1.0 / max(1.0, float(steps)))
	annealer.alpha = clamp(decay, 0.90, 0.999)
	annealer.run(working, plan_cost, entry_idx, terms)
	return working

func _compare_results(a: Dictionary, b: Dictionary) -> bool:
	return float(a.get("metrics", {}).get("total", INF)) < float(b.get("metrics", {}).get("total", INF))

func run_batch(seeds: int = 6, steps: int = 5000, keep: int = 3) -> Array:
	var results: Array = []
	for _i in range(seeds):
		var candidate := _optimize_partition(steps, partition)
		if candidate == null:
			continue
		var metrics := _metrics_for(candidate)
		results.append({
			"partition": candidate,
			"state": _state_from_partition(candidate),
			"metrics": metrics,
		})
	results.sort_custom(Callable(self, "_compare_results"))
	var limit := min(keep, results.size())
	return results.slice(0, limit)

func _on_batch_run_pressed() -> void:
	call_deferred("_batch_run_async")

func _batch_run_async() -> void:
	if program == null:
		return
	var seeds := max(1, int(seeds_sb.value))
	var steps := max(1, int(iters.value))
	var keep := min(3, seeds)
	var results := run_batch(seeds, steps, keep)
	if results.is_empty():
		return
	await _display_batch_results(results)
	var best: Dictionary = results[0]
	partition = _copy_partition(best.get("partition"))
	_update_state_from_partition()
	_rebuild_meshes()

func _display_batch_results(results: Array) -> void:
	_clear_batch_results()
	batch_header.text = "Batch Results (%d)" % results.size()
	for result in results:
		var part: Partition = result.get("partition")
		var snapshot: Dictionary = result.get("state", part.to_state_rects() if part != null else {})
		var metrics: Dictionary = result.get("metrics", {})
		var tex := await _state_to_texture(snapshot)
		var preview := TextureRect.new()
		preview.texture = tex
		preview.custom_minimum_size = Vector2(120, 120)
		preview.gui_input.connect(func(ev):
			if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
				if part != null:
					partition = _copy_partition(part)
					_update_state_from_partition()
				else:
					state = snapshot.duplicate(true)
				_rebuild_meshes()
		)
		var container := VBoxContainer.new()
		var label := Label.new()
		label.text = "total %.2f" % float(metrics.get("total", 0.0))
		container.add_child(preview)
		container.add_child(label)
		batch_container.add_child(container)

func _clear_batch_results() -> void:
	for child in batch_container.get_children():
		child.queue_free()
	batch_header.text = "Batch Results (0)"

func _state_to_texture(snapshot: Dictionary) -> Texture2D:
	var viewport: SubViewport = SubViewport.new()
	viewport.disable_3d = true
	viewport.update_mode = SubViewport.UPDATE_ONCE
	viewport.clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	viewport.clear_color = Color(0.1, 0.1, 0.12)
	viewport.size = Vector2i(256, 256)
	var overlay_instance := BubbleOverlay.new()
	overlay_instance.custom_minimum_size = viewport.size
	overlay_instance.size = viewport.size
	var bg := ColorRect.new()
	bg.color = viewport.clear_color
	bg.anchor_right = 1.0
	bg.anchor_bottom = 1.0
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bg.size_flags_vertical = Control.SIZE_EXPAND_FILL
	viewport.add_child(bg)
	viewport.add_child(overlay_instance)
	add_child(viewport)
	overlay_instance.update_display(program, snapshot)
	await get_tree().process_frame
	await get_tree().process_frame
	var image: Image = viewport.get_texture().get_image()
	var texture := ImageTexture.create_from_image(image)
	viewport.queue_free()
	return texture

func _optimize_once() -> void:
	if partition == null:
		return
	var steps := max(1, int(iters.value) / 10)
	var result := _optimize_partition(steps, partition)
	if result == null:
		return
	partition = result
	_update_state_from_partition()
	_rebuild_meshes()

# 🔥 FIX: Complete implementation of optimize_with_restarts
func optimize_with_restarts(restart_count: int, steps: int) -> Dictionary:
	print("⏳ Optimizing with %d restarts..." % restart_count)
	
	var best_partition: Partition = null
	var best_cost := INF
	var best_metrics := {}
	
	# Include the current partition as the first candidate
	var candidates: Array[Partition] = [partition]
	
	# Generate additional candidates by re-seeding from the program
	for _i in range(restart_count):
		var candidate := PartitionIO.from_program_rect_seed(program, 0.1)
		candidates.append(candidate)
	
	# Optimize each candidate
	for i in range(candidates.size()):
		print("  Optimizing candidate %d/%d..." % [i + 1, candidates.size()])
		var optimized := _optimize_partition(steps, candidates[i])
		if optimized == null:
			continue
		
		var metrics := _metrics_for(optimized)
		var cost := float(metrics.get("total", INF))
		
		if cost < best_cost:
			best_cost = cost
			best_partition = optimized
			best_metrics = metrics
			print("    ✓ New best: %.2f" % cost)
	
	print("✓ Optimization complete. Best cost: %.2f" % best_cost)
	
	return {
		"partition": best_partition,
		"state": _state_from_partition(best_partition) if best_partition != null else {},
		"metrics": best_metrics
	}

func _optimize_many() -> void:
	if partition == null:
		return
	var steps := max(1, int(iters.value))
	var seed_count := max(1, int(seeds_sb.value))
	if seed_count > 1:
		var best: Dictionary = optimize_with_restarts(seed_count - 1, steps)
		if best.has("partition") and best["partition"] != null:
			partition = best["partition"]
			_update_state_from_partition()
		_rebuild_meshes()
	else:
		var result := _optimize_partition(steps, partition)
		if result != null:
			partition = result
			_update_state_from_partition()
			_rebuild_meshes()

func _rebuild_meshes() -> void:
	_ensure_roof_root()
	var outer: Rect2 = state.get("outer", Rect2())
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
	print("🏠 Rebuilding meshes: rooms=%d footprint=%s" % [state.get("rooms", {}).size(), outer])

	if is_instance_valid(overlay):
		if view_stage == "Bubble" and program != null:
			var floor_idx := bubble_ui.current_floor if bubble_ui != null else 0
			show_bubble_for(program, floor_idx)
		else:
			overlay.update_display(program, state)

	_update_cost_ui()

	for c in rooms_root.get_children():
		if c != roof_root:
			c.queue_free()
	for c in roof_root.get_children():
		c.queue_free()

	if outer.size == Vector2.ZERO:
		print("⚠️ Empty footprint, skipping mesh generation")
		print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
		return

	var slab := MeshInstance3D.new()
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(outer.size.x, 0.1, outer.size.y)
	slab.mesh = slab_mesh
	slab.transform = Transform3D(Basis(), Vector3(outer.size.x * 0.5, 0.05, outer.size.y * 0.5))
	var slab_mat := StandardMaterial3D.new()
	slab_mat.albedo_color = Color(0.35, 0.35, 0.38)
	slab_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	slab.material_override = slab_mat
	rooms_root.add_child(slab)

	var rooms_dict: Dictionary = state.get("rooms", {})
	for id in rooms_dict.keys():
		var r: Dictionary = rooms_dict[id]
		var rect: Rect2 = r["rect"]
		var col: Color = r["color"]
		var piece := MeshInstance3D.new()
		var piece_box := BoxMesh.new()
		piece_box.size = Vector3(rect.size.x, 0.3, rect.size.y)
		piece.mesh = piece_box
		piece.transform = Transform3D(Basis(), Vector3(rect.position.x + rect.size.x * 0.5, 0.15, rect.position.y + rect.size.y * 0.5))
		var mat := StandardMaterial3D.new()
		mat.albedo_color = col
		mat.roughness = 0.9
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		piece.material_override = mat
		rooms_root.add_child(piece)

	if partition != null:
		var doors := _doors_from_partition_array(partition)
		_build_walls_unique(partition, doors)
		_build_exterior_walls(partition, doors)

	var stairs_list: Array = state.get("stairs", [])
	for stair_data in stairs_list:
		var stair_dict: Dictionary = stair_data
		var stair_rect: Rect2 = stair_dict.get("rect", Rect2())
		if stair_rect.size == Vector2.ZERO:
			continue
		var stair_mesh := MeshInstance3D.new()
		var stair_box := BoxMesh.new()
		stair_box.size = Vector3(stair_rect.size.x, WALL_H, stair_rect.size.y)
		stair_mesh.mesh = stair_box
		stair_mesh.transform = Transform3D(
			Basis(),
			Vector3(
				stair_rect.position.x + stair_rect.size.x * 0.5,
				WALL_H * 0.5,
				stair_rect.position.y + stair_rect.size.y * 0.5
			)
		)
		var stair_mat := StandardMaterial3D.new()
		stair_mat.albedo_color = Color(0.7, 0.6, 0.45)
		stair_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		stair_mesh.material_override = stair_mat
		rooms_root.add_child(stair_mesh)

	if roof_chk.button_pressed:
		_add_simple_hip_roof_rect(outer, 28.0)

	_debug_draw_doors()
	print("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")

func _debug_draw_doors() -> void:
	var door_count := 0
	for key in state.get("doors", {}).keys():
		var ids: PackedStringArray = key.split("|")
		if ids.size() != 2: continue
		if not state["rooms"].has(ids[0]) or not state["rooms"].has(ids[1]): continue
		var ra: Rect2 = state["rooms"][ids[0]]["rect"]
		var rb: Rect2 = state["rooms"][ids[1]]["rect"]
		var w := GeomUtils.shared_wall(ra, rb)
		if w.is_empty(): continue
		
		var start: Vector2 = w["start"]
		var end: Vector2 = w["end"]
		var mid: Vector2 = (start + end) * 0.5
		var axis: String = w["axis"]
		
		var m := MeshInstance3D.new()
		var b := BoxMesh.new()
		
		var door_width := 0.9
		var door_height := 2.2
		var door_thickness := 0.1
		
		if axis == "x":
			b.size = Vector3(door_width, door_height, door_thickness)
			m.transform = Transform3D(Basis(), Vector3(mid.x, door_height * 0.5, mid.y))
		else:
			b.size = Vector3(door_thickness, door_height, door_width)
			m.transform = Transform3D(Basis(), Vector3(mid.x, door_height * 0.5, mid.y))
		
		m.mesh = b
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.2, 0.2)
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.8
		m.material_override = mat
		rooms_root.add_child(m)
		door_count += 1
	
	print("🚪 Visualized %d doors in 3D" % door_count)

func cycle_style() -> void:
	print("⚠️ cycle_style: Not yet implemented")

func _span_sort(a: Vector2, b: Vector2) -> bool:
	return a.x < b.x

func export_svg() -> void:
	print("⚠️ export_svg: Not yet implemented")

func export_gltf() -> void:
	print("⚠️ export_gltf: Not yet implemented")

func save_plan() -> void:
	print("⚠️ save_plan: Not yet implemented")

func load_plan() -> void:
	print("⚠️ load_plan: Not yet implemented")

func _add_simple_hip_roof_rect(rect: Rect2, height: float) -> void:
	print("⚠️ _add_simple_hip_roof_rect: Not yet implemented (rect=%s, height=%.1f)" % [rect, height])

func _apply_weights() -> void:
	if plan_cost == null:
		return

	plan_cost.k_access = float(w_access.value)
	plan_cost.k_dims = float(w_dims.value)
	plan_cost.k_shape = float(w_shape.value)
	plan_cost.k_expose = float(w_exposure.value)
	plan_cost.k_floors = float(w_floors.value)

	print("✓ Weights: k_access=%.1f k_privacy=%.1f k_dims=%.1f k_shape=%.1f k_expose=%.1f k_floors=%.0f" % [
		plan_cost.k_access,
		plan_cost.k_privacy,
		plan_cost.k_dims,
		plan_cost.k_shape,
		plan_cost.k_expose,
		plan_cost.k_floors
	])

func _ensure_overlay() -> void:
	if overlay == null or not is_instance_valid(overlay):
		overlay = BubbleOverlay.new()
	if bubble_ui == null or not is_instance_valid(bubble_ui):
		bubble_ui = overlay

func set_stage(stage: String) -> void:
	view_stage = stage
	if bubble_ui:
		bubble_ui.visible = overlay_chk.button_pressed and stage == "Bubble"
	_rebuild_meshes()

func show_bubble_for(program: ArchitecturalProgram, floor := 0) -> void:
	if bubble_ui == null:
		return
	bubble_ui.update_display(program, {
		"floor": floor,
		"show_privacy": true,
		"show_labels": true,
		"show_edges": true
	})

func _rescale_ui() -> void:
	pass

func _update_cost_ui() -> void:
	if cost_tree == null or partition == null:
		return

	cost_tree.clear()
	var root := cost_tree.create_item()

	var metrics := _metrics_for(partition)

	var access_item := cost_tree.create_item(root)
	access_item.set_text(0, "Access")
	access_item.set_text(1, "%.2f" % metrics.get("access", 0.0))

	var privacy_item := cost_tree.create_item(root)
	privacy_item.set_text(0, "Privacy")
	privacy_item.set_text(1, "%.2f" % metrics.get("privacy", 0.0))

	var dims_item := cost_tree.create_item(root)
	dims_item.set_text(0, "Dimensions")
	dims_item.set_text(1, "%.2f" % metrics.get("dims", 0.0))

	var shape_item := cost_tree.create_item(root)
	shape_item.set_text(0, "Shape")
	shape_item.set_text(1, "%.2f" % metrics.get("shape", 0.0))

	var exposure_item := cost_tree.create_item(root)
	exposure_item.set_text(0, "Exposure")
	exposure_item.set_text(1, "%.2f" % metrics.get("exposure", 0.0))

	var overlap_item := cost_tree.create_item(root)
	overlap_item.set_text(0, "Overlap")
	overlap_item.set_text(1, "%.2f" % metrics.get("overlap", 0.0))

	var total_item := cost_tree.create_item(root)
	total_item.set_text(0, "TOTAL")
	total_item.set_text(1, "%.2f" % metrics.get("total", 0.0))
