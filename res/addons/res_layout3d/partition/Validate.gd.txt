extends Resource
class_name Validate

const Partition := preload("res://addons/res_layout3d/partition/Partition.gd")

static func min_sizes_ok(part: Partition) -> bool:
	for room in part.rooms:
		if room.rect.size.x < Partition.MIN_ROOM.x or room.rect.size.y < Partition.MIN_ROOM.y:
			return false
	return true

static func inside_footprint(part: Partition) -> bool:
	for room in part.rooms:
		if not part.footprint.encloses(room.rect):
			return false
	return true
static func tiling_ok(part: Partition) -> bool:
	var cell_scale := max(1, int(round(1.0 / max(part.grid.step_m, 1e-6))))
	var width_cells := int(round(part.footprint.size.x * cell_scale))
	var height_cells := int(round(part.footprint.size.y * cell_scale))
	if width_cells <= 0 or height_cells <= 0:
		return false
	var occ := PackedByteArray()
	occ.resize(width_cells * height_cells)
	for idx in range(occ.size()):
		occ[idx] = 0

	var mark: Callable = func(rect: Rect2) -> bool:
		var offset_x := int(round((rect.position.x - part.footprint.position.x) * cell_scale))
		var offset_y := int(round((rect.position.y - part.footprint.position.y) * cell_scale))
		var width := int(round(rect.size.x * cell_scale))
		var height := int(round(rect.size.y * cell_scale))
		if offset_x < 0 or offset_y < 0 or offset_x + width > width_cells or offset_y + height > height_cells:
			return false
		for y in range(height):
			for x in range(width):
				var idx := (offset_y + y) * width_cells + (offset_x + x)
				if occ[idx] == 1:
					return false
				occ[idx] = 1
		return true

	for room in part.rooms:
		if not mark.call(room.rect):
			return false
	for idx in range(occ.size()):
		if occ[idx] == 0:
			return false
	return true

static func feasible(part: Partition) -> bool:
	return inside_footprint(part) and min_sizes_ok(part) and tiling_ok(part)
