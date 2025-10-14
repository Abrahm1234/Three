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
