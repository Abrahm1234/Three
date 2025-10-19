extends Control
class_name BubbleOverlay

const GeomUtils := preload("res://addons/res_layout3d/GeomUtils.gd")

@export var current_floor: int = 0
@export var show_privacy := true
@export var show_labels := true
@export var show_edges := true

var footprint: Rect2 = Rect2()
var rooms := {}
var edges: Array = []
var doors := {}

var _bubble_mode := false
var _view_scale: float = 1.0
var _view_offset: Vector2 = Vector2.ZERO

static func _privacy_color(pr: int) -> Color:
	match pr:
		ArchitecturalProgram.Privacy.PUBLIC:
			return Color.hex(0x46c37aff)
		ArchitecturalProgram.Privacy.SEMI:
			return Color.hex(0xffc857ff)
		_:
			return Color.hex(0xe04f5aff)

static func _default_privacy(label: String) -> int:
	var s := label.to_lower()
	if s in ["foyer", "entry", "living", "great room", "dining", "kitchen", "family"]:
		return ArchitecturalProgram.Privacy.PUBLIC
	if s in ["hall", "corridor", "study", "office", "laundry", "mudroom", "loft"]:
		return ArchitecturalProgram.Privacy.SEMI
	return ArchitecturalProgram.Privacy.PRIVATE

func update_display(program: ArchitecturalProgram, state: Dictionary) -> void:
	if state == null:
		state = {}
	if program == null and state.is_empty():
		footprint = Rect2()
		rooms = {}
		edges = []
		doors = {}
		queue_redraw()
		return

	if state.has("floor"):
		current_floor = int(state["floor"])
	if state.has("show_privacy"):
		show_privacy = bool(state["show_privacy"])
	if state.has("show_labels"):
		show_labels = bool(state["show_labels"])
	if state.has("show_edges"):
		show_edges = bool(state["show_edges"])

	var state_rooms: Dictionary = state.get("rooms", {})
	var has_rect := false
	for key in state_rooms.keys():
		var rd = state_rooms[key]
		if rd is Dictionary and rd.has("rect"):
			has_rect = true
			break

	if has_rect:
		_bubble_mode = false
		footprint = state.get("outer", Rect2())
		rooms = {}
		for id in state_rooms.keys():
			var rd: Dictionary = state_rooms[id]
			rooms[id] = {
				"rect": rd.get("rect", Rect2()),
				"color": rd.get("color", Color(0.3, 0.6, 0.9, 0.8)),
				"type": rd.get("type", id)
			}
			edges = program.edges.duplicate(true) if program != null else []
		doors = state.get("doors", {})
	else:
		_bubble_mode = true
		doors = {}
		var fp_vec := Vector2.ZERO
		if program != null:
			var fp_i: Vector2i = program.footprint_m
			fp_vec = Vector2(fp_i.x, fp_i.y)
		if state.has("outer") and fp_vec == Vector2.ZERO:
			var st_outer: Rect2 = state.get("outer", Rect2())
			fp_vec = st_outer.size
		footprint = Rect2(Vector2.ZERO, fp_vec)
		rooms = {}
		edges = []
		if program != null:
			for room_def in program.rooms:
				var rdict: Dictionary = room_def
				var rid := String(rdict.get("id", ""))
				if rid == "":
					continue
				var floor := int(rdict.get("floor", 0))
				if floor != current_floor:
					continue
				rooms[rid] = rdict.duplicate(true)
			for edge_def in program.edges:
				var a_id := String(edge_def.get("a_id", ""))
				var b_id := String(edge_def.get("b_id", ""))
				if rooms.has(a_id) and rooms.has(b_id):
					edges.append(edge_def)
	queue_redraw()

func _draw() -> void:
	if _bubble_mode:
		_draw_bubble()
	else:
		_draw_partition()

func _draw_bubble() -> void:
	if rooms.is_empty():
		return
	var base_rect := footprint
	if base_rect.size == Vector2.ZERO:
		base_rect = _bubble_bounds()
	if base_rect.size == Vector2.ZERO:
		return
	var padding: float = 20.0
	var view_size: Vector2 = get_size()
	var available := Vector2(max(view_size.x - padding * 2.0, 1.0), max(view_size.y - padding * 2.0, 1.0))
	var scale := min(available.x / max(base_rect.size.x, 0.001), available.y / max(base_rect.size.y, 0.001))
	var offset: Vector2 = (view_size - base_rect.size * scale) * 0.5 - base_rect.position * scale
	_view_scale = scale
	_view_offset = offset

	var bg_rect := Rect2(base_rect.position * scale + offset, base_rect.size * scale)
	draw_rect(bg_rect, Color(0.05, 0.05, 0.08, 0.6), true)
	draw_rect(bg_rect, Color(0.3, 0.4, 0.6, 0.8), false, 2.0)

	for id in rooms.keys():
		var room_dict: Dictionary = rooms[id]
		var room_rect := _bubble_rect(room_dict)
		var view_rect := _to_view(room_rect)
		var base_col := Color(0.3, 0.6, 0.9, 1.0)
		if show_privacy:
			base_col = _privacy_color(int(room_dict.get("privacy", _default_privacy(String(room_dict.get("type", id))))))
		var fill_col := base_col
		fill_col.a = 0.55
		draw_rect(view_rect, fill_col, true)
		draw_rect(view_rect, base_col.darkened(0.25), false, 2.0)
		if show_labels:
			var label := String(room_dict.get("type", id))
			var font := get_theme_default_font()
			if font == null:
				font = ThemeDB.fallback_font
			var font_size := get_theme_default_font_size()
			if font_size <= 0:
				font_size = 14
			draw_string(font, view_rect.get_center(), label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)

	if not show_edges:
		return

	for edge_def in edges:
		var edge: Dictionary = edge_def
		var a_id := String(edge.get("a_id", ""))
		var b_id := String(edge.get("b_id", ""))
		if not rooms.has(a_id) or not rooms.has(b_id):
			continue
		var pa := _to_view(_bubble_rect(rooms[a_id])).get_center()
		var pb := _to_view(_bubble_rect(rooms[b_id])).get_center()
		var kind := String(edge.get("kind", "door"))
		var color := Color.hex(0x99e2ffff) if kind == "open" else Color.hex(0xffffffaa)
		var width := 3.0 if kind == "open" else 1.5
		draw_line(pa, pb, color, width)

func _draw_partition() -> void:
	if footprint.size == Vector2.ZERO or rooms.is_empty():
		return
	var padding: float = 20.0
	var view_size: Vector2 = get_size()
	var available: Vector2 = Vector2(max(view_size.x - padding * 2.0, 1.0), max(view_size.y - padding * 2.0, 1.0))
	var scale: float = min(available.x / max(footprint.size.x, 0.001), available.y / max(footprint.size.y, 0.001))
	var offset: Vector2 = (view_size - footprint.size * scale) * 0.5

	var bg_rect := Rect2(offset, footprint.size * scale)
	draw_rect(bg_rect, Color(0.05, 0.05, 0.08, 0.6), true)
	draw_rect(bg_rect, Color(0.3, 0.4, 0.6, 0.8), false, 2.0)

	var centers := {}
	for id in rooms.keys():
		var rd: Dictionary = rooms[id]
		var rect: Rect2 = rd["rect"]
		var center: Vector2 = rect.position + rect.size * 0.5
		var mapped_center: Vector2 = offset + center * scale
		centers[id] = mapped_center
		var radii: Vector2 = rect.size * 0.5 * scale
		_draw_ellipse(mapped_center, radii, rd["color"])
		_draw_label(id, mapped_center, rd["color"].darkened(0.4))

	for edge in edges:
		var ed: Dictionary = edge
		var a_id: String = ed.get("a_id", "")
		var b_id: String = ed.get("b_id", "")
		if not centers.has(a_id) or not centers.has(b_id):
			continue
		var a_pos: Vector2 = centers[a_id]
		var b_pos: Vector2 = centers[b_id]
		var edge_color := Color(1.0, 0.3, 0.3, 0.9)
		var shared := 0.0
		if rooms.has(a_id) and rooms.has(b_id):
			var ra: Rect2 = rooms[a_id].get("rect", Rect2())
			var rb: Rect2 = rooms[b_id].get("rect", Rect2())
			shared = _shared_edge_len(ra, rb)
		if shared > 0.0:
			edge_color = Color(0.3, 1.0, 0.3, 0.9)
		elif a_pos.distance_to(b_pos) < 80.0:
			edge_color = Color(1.0, 0.9, 0.3, 0.9)
		draw_line(a_pos, b_pos, edge_color, 2.0)

		var door_color: Color = Color(0.95, 0.95, 0.2, 0.9)
		var door_data: Dictionary = _door_between(a_id, b_id)
		if not door_data.is_empty():
			var ra: Rect2 = rooms[a_id].get("rect", Rect2())
			var rb: Rect2 = rooms[b_id].get("rect", Rect2())
			var wall: Dictionary = GeomUtils.shared_wall(ra, rb)
			if not wall.is_empty():
				var t: float = clamp(float(door_data.get("t", 0.5)), 0.0, 1.0)
				var point: Vector2 = (wall["start"] as Vector2).lerp(wall["end"] as Vector2, t)
				var mapped_point: Vector2 = offset + point * scale
				var size: Vector2 = Vector2(6, 6)
				draw_rect(Rect2(mapped_point - size * 0.5, size), door_color, true)

func _bubble_rect(data: Dictionary) -> Rect2:
	var pos := Vector2(float(data.get("x", 0.0)), float(data.get("y", 0.0)))
	var size := Vector2(float(data.get("w", 2.0)), float(data.get("h", 2.0)))
	return Rect2(pos, size)

func _bubble_bounds() -> Rect2:
	var first := true
	var rect := Rect2()
	for id in rooms.keys():
		var r := _bubble_rect(rooms[id])
		if first:
			rect = r
			first = false
		else:
			rect = rect.merge(r)
	return rect

func _to_view(rect: Rect2) -> Rect2:
	return Rect2(_view_offset + rect.position * _view_scale, rect.size * _view_scale)

func _draw_ellipse(center: Vector2, radii: Vector2, color: Color) -> void:
	var steps := 40
	var points: PackedVector2Array = []
	for i in range(steps):
		var angle := TAU * float(i) / float(steps)
		points.append(center + Vector2(cos(angle) * radii.x, sin(angle) * radii.y))
	var colors: PackedColorArray = PackedColorArray()
	colors.resize(points.size())
	for i in range(points.size()):
		colors[i] = color
	draw_polygon(points, colors)

func _draw_label(text: String, position: Vector2, color: Color) -> void:
	var font := get_theme_font("font", "Label")
	if font == null:
		font = ThemeDB.fallback_font
	var size := get_theme_font_size("font_size", "Label")
	if size == 0:
		size = 14
	var text_size := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, size)
	var draw_pos := position - text_size * 0.5 + Vector2(0, text_size.y * 0.25)
	draw_string(font, draw_pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1.0, size, color)

func _shared_edge_len(a: Rect2, b: Rect2) -> float:
	var x_overlap := max(0.0, min(a.position.x + a.size.x, b.position.x + b.size.x) - max(a.position.x, b.position.x))
	var y_touch := is_equal_approx(a.position.y + a.size.y, b.position.y) or is_equal_approx(b.position.y + b.size.y, a.position.y)
	var h := x_overlap if y_touch else 0.0

	var y_overlap := max(0.0, min(a.position.y + a.size.y, b.position.y + b.size.y) - max(a.position.y, b.position.y))
	var x_touch := is_equal_approx(a.position.x + a.size.x, b.position.x) or is_equal_approx(b.position.x + b.size.x, a.position.x)
	var v := y_overlap if x_touch else 0.0

	return max(h, v)

func _door_between(a_id: String, b_id: String) -> Dictionary:
	var key1 := "%s|%s" % [a_id, b_id]
	var key2 := "%s|%s" % [b_id, a_id]
	if doors.has(key1):
		return doors[key1]
	if doors.has(key2):
		return doors[key2]
	return {}
