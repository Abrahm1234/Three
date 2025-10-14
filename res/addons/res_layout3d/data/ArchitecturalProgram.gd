extends Resource
class_name ArchitecturalProgram

@export var footprint_m: Vector2i = Vector2i.ZERO
@export var rooms: Array[Dictionary] = []
@export var edges: Array[Dictionary] = []
@export var default_door_w: float = 0.9
@export var door_clear: float = 0.1
