extends Node
class_name PlanMoves

const Partition := preload("res://addons/res_layout3d/partition/Partition.gd")
const Validate := preload("res://addons/res_layout3d/partition/Validate.gd")

# Paper (Section 5.1): Wall sliding with Gaussian distribution
static func slide_wall(part: Partition, steps: int) -> bool:
	var pairs: Array = _adjacent_pairs(part)
	if pairs.is_empty():
		return false
	var edge: Dictionary = pairs[randi() % pairs.size()]
	
	# Paper: "distance d ~ N(0, σ²)"
	var sigma := 2.0 * part.grid.step_m
	var delta: float = randfn(0.0, sigma)
	delta = clamp(delta, -6 * part.grid.step_m, 6 * part.grid.step_m)
	
	if is_zero_approx(delta):
		return false

	if edge.get("vert", false):
		var left_idx := int(edge["left_idx"])
		var right_idx := int(edge["right_idx"])
		var left_rect := part.rooms[left_idx].rect
		var right_rect := part.rooms[right_idx].rect
		var boundary_x := left_rect.end.x
		if not is_equal_approx(boundary_x, right_rect.position.x):
			boundary_x = right_rect.end.x
		var left_rooms: Array = []
		var right_rooms: Array = []
		for room_obj in part.rooms:
			if is_equal_approx(room_obj.rect.end.x, boundary_x):
				left_rooms.append(room_obj)
			if is_equal_approx(room_obj.rect.position.x, boundary_x):
				right_rooms.append(room_obj)
		if left_rooms.is_empty() or right_rooms.is_empty():
			return false
		var min_x := -INF
		for room_obj in left_rooms:
			min_x = max(min_x, room_obj.rect.position.x + Partition.MIN_ROOM.x)
		var max_x := INF
		for room_obj in right_rooms:
			max_x = min(max_x, room_obj.rect.end.x - Partition.MIN_ROOM.x)
		if min_x > max_x:
			return false
		var target := part.grid.snapf(clamp(boundary_x + delta, min_x, max_x))
		if is_equal_approx(target, boundary_x):
			return false
		for room_obj_left in left_rooms:
			room_obj_left.rect.size.x = max(Partition.MIN_ROOM.x, target - room_obj_left.rect.position.x)
		for room_obj_right in right_rooms:
			var end_x: float = room_obj_right.rect.end.x
			room_obj_right.rect.position.x = target
			room_obj_right.rect.size.x = max(Partition.MIN_ROOM.x, end_x - target)
	else:
		var top_idx := int(edge["top_idx"])
		var bottom_idx := int(edge["bottom_idx"])
		var top_rect := part.rooms[top_idx].rect
		var bottom_rect := part.rooms[bottom_idx].rect
		var boundary_y := top_rect.end.y
		if not is_equal_approx(boundary_y, bottom_rect.position.y):
			boundary_y = bottom_rect.end.y
		var top_rooms: Array = []
		var bottom_rooms: Array = []
		for room_obj in part.rooms:
			if is_equal_approx(room_obj.rect.end.y, boundary_y):
				top_rooms.append(room_obj)
			if is_equal_approx(room_obj.rect.position.y, boundary_y):
				bottom_rooms.append(room_obj)
		if top_rooms.is_empty() or bottom_rooms.is_empty():
			return false
		var min_y := -INF
		for room_obj in top_rooms:
			min_y = max(min_y, room_obj.rect.position.y + Partition.MIN_ROOM.y)
		var max_y := INF
		for room_obj in bottom_rooms:
			max_y = min(max_y, room_obj.rect.end.y - Partition.MIN_ROOM.y)
		if min_y > max_y:
			return false
		var target_y := part.grid.snapf(clamp(boundary_y + delta, min_y, max_y))
		if is_equal_approx(target_y, boundary_y):
			return false
		for room_obj_top in top_rooms:
			room_obj_top.rect.size.y = max(Partition.MIN_ROOM.y, target_y - room_obj_top.rect.position.y)
		for room_obj_bottom in bottom_rooms:
			var end_y: float = room_obj_bottom.rect.end.y
			room_obj_bottom.rect.position.y = target_y
			room_obj_bottom.rect.size.y = max(Partition.MIN_ROOM.y, end_y - target_y)

	return Validate.feasible(part)

# Paper (Section 5.1): Snap nearly-aligned walls
static func snap_walls(part: Partition, eps := -1.0) -> bool:
	if eps < 0.0:
		eps = part.grid.step_m * 2.0
	var changed := false
	for edge in _adjacent_pairs(part):
		if edge["vert"]:
			var left_room = part.rooms[edge["left_idx"]]
			var right_room = part.rooms[edge["right_idx"]]
			var boundary: float = left_room.rect.position.x + left_room.rect.size.x
			var other_boundary: float = right_room.rect.position.x
			if abs(boundary - other_boundary) <= eps:
				var target := part.grid.snapf((boundary + other_boundary) * 0.5)
				var min_boundary: float = left_room.rect.position.x + Partition.MIN_ROOM.x
				var right_end: float = right_room.rect.position.x + right_room.rect.size.x
				var max_boundary: float = right_end - Partition.MIN_ROOM.x
				target = clamp(target, min_boundary, max_boundary)
				target = part.grid.snapf(target)
				if not is_equal_approx(target, boundary):
					left_room.rect.size.x = max(Partition.MIN_ROOM.x, target - left_room.rect.position.x)
					right_room.rect.position.x = target
					right_room.rect.size.x = max(Partition.MIN_ROOM.x, right_end - target)
					changed = true
		else:
			var top_room = part.rooms[edge["top_idx"]]
			var bottom_room = part.rooms[edge["bottom_idx"]]
			var boundary_y: float = top_room.rect.position.y + top_room.rect.size.y
			var other_boundary_y: float = bottom_room.rect.position.y
			if abs(boundary_y - other_boundary_y) <= eps:
				var target_y := part.grid.snapf((boundary_y + other_boundary_y) * 0.5)
				var min_boundary_y: float = top_room.rect.position.y + Partition.MIN_ROOM.y
				var bottom_end: float = bottom_room.rect.position.y + bottom_room.rect.size.y
				var max_boundary_y: float = bottom_end - Partition.MIN_ROOM.y
				target_y = clamp(target_y, min_boundary_y, max_boundary_y)
				target_y = part.grid.snapf(target_y)
				if not is_equal_approx(target_y, boundary_y):
					top_room.rect.size.y = max(Partition.MIN_ROOM.y, target_y - top_room.rect.position.y)
					bottom_room.rect.position.y = target_y
					bottom_room.rect.size.y = max(Partition.MIN_ROOM.y, bottom_end - target_y)
					changed = true
	return changed and Validate.feasible(part)

# Paper (Section 5.1): Swap room labels (identities)
static func swap_labels(part: Partition) -> bool:
	if part.rooms.size() < 2:
		return false
	var a := randi() % part.rooms.size()
	var b := randi() % part.rooms.size()
	if a == b:
		return false
	var tmp := part.rooms[a].label
	part.rooms[a].label = part.rooms[b].label
	part.rooms[b].label = tmp
	return true

static func _adjacent_pairs(part: Partition) -> Array:
	var pairs: Array = []
	for i in range(part.rooms.size()):
		var A := part.rooms[i].rect
		var Ae := A.position + A.size
		for j in range(i + 1, part.rooms.size()):
			var B := part.rooms[j].rect
			var Be := B.position + B.size
			if is_equal_approx(Ae.x, B.position.x) or is_equal_approx(Be.x, A.position.x):
				var y0 := max(A.position.y, B.position.y)
				var y1 := min(Ae.y, Be.y)
				if y1 - y0 > 0.0:
					var left_idx := i
					var right_idx := j
					if is_equal_approx(Be.x, A.position.x):
						left_idx = j
						right_idx = i
					pairs.append({
						"vert": true,
						"a": left_idx, "b": right_idx,
						"left_idx": left_idx, "right_idx": right_idx,
						"span": Vector2(y0, y1),
					})
			if is_equal_approx(Ae.y, B.position.y) or is_equal_approx(Be.y, A.position.y):
				var x0 := max(A.position.x, B.position.x)
				var x1 := min(Ae.x, Be.x)
				if x1 - x0 > 0.0:
					var top_idx := i
					var bottom_idx := j
					if is_equal_approx(Be.y, A.position.y):
						top_idx = j
						bottom_idx = i
					pairs.append({
						"vert": false,
						"a": top_idx, "b": bottom_idx,
						"top_idx": top_idx, "bottom_idx": bottom_idx,
						"span": Vector2(x0, x1),
					})
	return pairs
