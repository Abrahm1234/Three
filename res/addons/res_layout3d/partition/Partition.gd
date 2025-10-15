extends Resource
class_name Partition

const Grid2D := preload("res://addons/res_layout3d/partition/Grid2D.gd")

const MIN_ROOM := Vector2(2.0, 2.0)

@export var grid := Grid2D.new()
@export var wall_thickness_m := 0.15
@export var footprint := Rect2()

class Room:
	var id: int
	var label: String
	var rect: Rect2
	var floor: int = 0  # Track which floor this room is on

var rooms: Array[Room] = []

func set_footprint(r: Rect2) -> void:
	var p := grid.snap(r.position)
	var q := grid.snap(r.position + r.size)
	footprint = Rect2(p, q - p)

func clear() -> void:
	rooms.clear()

func add_room_rect(label: String, rect: Rect2, floor_num: int = 0) -> void:
	var room := Room.new()
	room.id = rooms.size()
	room.label = label
	var snapped := grid.snap_rect(rect)
	room.rect = Rect2(snapped.position, snapped.size)
	room.floor = floor_num  # Set floor assignment
	rooms.append(room)

func to_state_rects() -> Dictionary:
	var out := {
		"outer": footprint,
		"rooms": {},
		"doors": {},
		"stairs": [],
	}
	for r in rooms:
		var hue := float((abs(r.label.hash()) + r.id * 97) % 360) / 360.0
		out["rooms"][str(r.id)] = {
			"rect": r.rect,
			"color": Color.from_hsv(hue, 0.6, 0.9),
			"label": r.label,
		}
	return out

func to_state_dict() -> Dictionary:
	return to_state_rects()

func snapshot() -> Dictionary:
	var data: Array = []
	for room in rooms:
		data.append({
			"id": room.id,
			"label": room.label,
			"rect": Rect2(room.rect.position, room.rect.size),
			"floor": room.floor,
		})
	return {"rooms": data}

func restore(state: Dictionary) -> void:
	var data: Array = state.get("rooms", [])
	if data.size() != rooms.size():
		return
	for i in range(rooms.size()):
		var info: Dictionary = data[i]
		rooms[i].id = int(info.get("id", rooms[i].id))
		rooms[i].label = String(info.get("label", rooms[i].label))
		var rect_val = info.get("rect", rooms[i].rect)
		var rect: Rect2
		if rect_val is Rect2:
			rect = rect_val
		else:
			rect = rooms[i].rect
		rooms[i].rect = Rect2(rect.position, rect.size)
		rooms[i].floor = int(info.get("floor", rooms[i].floor))

func nudge_random_room(rng: RandomNumberGenerator, max_delta: float) -> bool:
	if rooms.is_empty():
		return false
	var idx := rng.randi_range(0, rooms.size() - 1)
	var room := rooms[idx]
	var delta := Vector2(rng.randf_range(-max_delta, max_delta), rng.randf_range(-max_delta, max_delta))
	var new_pos := room.rect.position + delta
	var fp_end := footprint.position + footprint.size
	new_pos.x = clamp(new_pos.x, footprint.position.x, fp_end.x - room.rect.size.x)
	new_pos.y = clamp(new_pos.y, footprint.position.y, fp_end.y - room.rect.size.y)
	var new_rect := Rect2(new_pos, room.rect.size)
	new_rect = grid.snap_rect(new_rect)
	new_rect = _clamp_rect_to_footprint(new_rect)
	if _overlaps_any(idx, new_rect):
		return false
	rooms[idx].rect = new_rect
	return true

func resize_random_room(rng: RandomNumberGenerator, max_frac: float) -> bool:
	if rooms.is_empty():
		return false
	var idx := rng.randi_range(0, rooms.size() - 1)
	var room := rooms[idx]
	var sx := 1.0 + rng.randf_range(-max_frac, max_frac)
	var sy := 1.0 + rng.randf_range(-max_frac, max_frac)
	var new_size := Vector2(max(MIN_ROOM.x, room.rect.size.x * sx), max(MIN_ROOM.y, room.rect.size.y * sy))
	var center := room.rect.position + room.rect.size * 0.5
	var new_pos := center - new_size * 0.5
	var candidate := Rect2(new_pos, new_size)
	candidate = _clamp_rect_to_footprint(candidate)
	candidate = grid.snap_rect(candidate)
	if candidate.size.x < MIN_ROOM.x or candidate.size.y < MIN_ROOM.y:
		return false
	if not footprint.encloses(candidate):
		return false
	if _overlaps_any(idx, candidate):
		return false
	rooms[idx].rect = candidate
	return true

func slide_shared_wall(rng: RandomNumberGenerator, max_delta: float) -> bool:
	var pairs := _adjacent_pairs()
	if pairs.is_empty():
		return false
	var edge := pairs[rng.randi_range(0, pairs.size() - 1)]
	var delta := rng.randf_range(-max_delta, max_delta)
	if is_zero_approx(delta):
		delta = max_delta if rng.randf() < 0.5 else -max_delta
	if bool(edge.get("vert", false)):
		var left_idx := int(edge.get("left_idx", edge.get("a", 0)))
		var right_idx := int(edge.get("right_idx", edge.get("b", 0)))
		var left_rect := rooms[left_idx].rect
		var right_rect := rooms[right_idx].rect
		var boundary := left_rect.position.x + left_rect.size.x
		var min_x := left_rect.position.x + MIN_ROOM.x
		var max_x := right_rect.position.x + right_rect.size.x - MIN_ROOM.x
		if max_x <= min_x:
			return false
		var target := clamp(boundary + delta, min_x, max_x)
		target = grid.snapf(target)
		if is_equal_approx(target, boundary):
			return false
		var new_left := Rect2(left_rect.position, Vector2(target - left_rect.position.x, left_rect.size.y))
		var right_end := right_rect.position.x + right_rect.size.x
		var new_right := Rect2(Vector2(target, right_rect.position.y), Vector2(right_end - target, right_rect.size.y))
		if new_left.size.x < MIN_ROOM.x or new_right.size.x < MIN_ROOM.x:
			return false
		if _overlaps_any(left_idx, new_left, right_idx) or _overlaps_any(right_idx, new_right, left_idx):
			return false
		rooms[left_idx].rect = new_left
		rooms[right_idx].rect = new_right
		return true
	else:
		var top_idx := int(edge.get("top_idx", edge.get("a", 0)))
		var bottom_idx := int(edge.get("bottom_idx", edge.get("b", 0)))
		var top_rect := rooms[top_idx].rect
		var bottom_rect := rooms[bottom_idx].rect
		var boundary_y := top_rect.position.y + top_rect.size.y
		var min_y := top_rect.position.y + MIN_ROOM.y
		var max_y := bottom_rect.position.y + bottom_rect.size.y - MIN_ROOM.y
		if max_y <= min_y:
			return false
		var target_y := clamp(boundary_y + delta, min_y, max_y)
		target_y = grid.snapf(target_y)
		if is_equal_approx(target_y, boundary_y):
			return false
		var new_top := Rect2(top_rect.position, Vector2(top_rect.size.x, target_y - top_rect.position.y))
		var bottom_end := bottom_rect.position.y + bottom_rect.size.y
		var new_bottom := Rect2(Vector2(bottom_rect.position.x, target_y), Vector2(bottom_rect.size.x, bottom_end - target_y))
		if new_top.size.y < MIN_ROOM.y or new_bottom.size.y < MIN_ROOM.y:
			return false
		if _overlaps_any(top_idx, new_top, bottom_idx) or _overlaps_any(bottom_idx, new_bottom, top_idx):
			return false
		rooms[top_idx].rect = new_top
		rooms[bottom_idx].rect = new_bottom
		return true
	return false

func swap_adjacent_blocks(rng: RandomNumberGenerator) -> bool:
	if rooms.size() < 2:
		return false
	var a := rng.randi_range(0, rooms.size() - 1)
	var b := rng.randi_range(0, rooms.size() - 1)
	if a == b:
		return false
	var rect_a := rooms[a].rect
	var rect_b := rooms[b].rect
	var floor_a := rooms[a].floor
	var floor_b := rooms[b].floor
	rooms[a].rect = Rect2(rect_b.position, rect_b.size)
	rooms[b].rect = Rect2(rect_a.position, rect_a.size)
	rooms[a].floor = floor_b
	rooms[b].floor = floor_a
	if _has_overlaps():
		rooms[a].rect = rect_a
		rooms[b].rect = rect_b
		rooms[a].floor = floor_a
		rooms[b].floor = floor_b
		return false
	return true

func _clamp_rect_to_footprint(rect: Rect2) -> Rect2:
	var pos := rect.position
	var size := rect.size
	var fp_end := footprint.position + footprint.size
	pos.x = clamp(pos.x, footprint.position.x, fp_end.x - size.x)
	pos.y = clamp(pos.y, footprint.position.y, fp_end.y - size.y)
	return Rect2(pos, size)

func _overlaps_any(ignore_idx: int, rect: Rect2, skip_idx := -1) -> bool:
	for i in range(rooms.size()):
		if i == ignore_idx or i == skip_idx:
			continue
		if rect.intersects(rooms[i].rect, false):
			return true
	return false

func _has_overlaps() -> bool:
	for i in range(rooms.size()):
		for j in range(i + 1, rooms.size()):
			if rooms[i].rect.intersects(rooms[j].rect, false):
				return true
	return false

func _adjacent_pairs() -> Array:
	var pairs: Array = []
	for i in range(rooms.size()):
		var A := rooms[i].rect
		var Ae := A.position + A.size
		for j in range(i + 1, rooms.size()):
			var B := rooms[j].rect
			var Be := B.position + B.size
			if is_equal_approx(Ae.x, B.position.x):
				var y0 := max(A.position.y, B.position.y)
				var y1 := min(Ae.y, Be.y)
				if y1 - y0 > 0.0:
					pairs.append({
						"vert": true,
						"a": i,
						"b": j,
						"left_idx": i,
						"right_idx": j,
						"span": Vector2(y0, y1),
					})
			elif is_equal_approx(Be.x, A.position.x):
				var y0b := max(A.position.y, B.position.y)
				var y1b := min(Ae.y, Be.y)
				if y1b - y0b > 0.0:
					pairs.append({
						"vert": true,
						"a": i,
						"b": j,
						"left_idx": j,
						"right_idx": i,
						"span": Vector2(y0b, y1b),
					})
			if is_equal_approx(Ae.y, B.position.y):
				var x0 := max(A.position.x, B.position.x)
				var x1 := min(Ae.x, Be.x)
				if x1 - x0 > 0.0:
					pairs.append({
						"vert": false,
						"a": i,
						"b": j,
						"top_idx": i,
						"bottom_idx": j,
						"span": Vector2(x0, x1),
					})
			elif is_equal_approx(Be.y, A.position.y):
				var x0b := max(A.position.x, B.position.x)
				var x1b := min(Ae.x, Be.x)
				if x1b - x0b > 0.0:
					pairs.append({
						"vert": false,
						"a": i,
						"b": j,
						"top_idx": j,
						"bottom_idx": i,
						"span": Vector2(x0b, x1b),
					})
	return pairs
