extends Resource
class_name ArchitecturalProgram

@export var footprint_m: Vector2i = Vector2i.ZERO
@export var rooms: Array[Dictionary] = []
@export var edges: Array[Dictionary] = []
@export var default_door_w: float = 0.9
@export var door_clear: float = 0.1

# --- Building Layout Design additions ---

enum Privacy { PUBLIC, SEMI, PRIVATE }

@export var floors: int = 1
@export var entry_room_id: String = ""   # e.g., "foyer" or program-chosen entry

static func default_privacy(t: String) -> int:
	var s := t.to_lower()
	if s in ["foyer","entry","living","great room","dining","kitchen","family"]:
		return Privacy.PUBLIC
	if s in ["hall","corridor","study","office","laundry","mudroom","loft"]:
		return Privacy.SEMI
	return Privacy.PRIVATE

# room dicts should include:
# { id:String, type:String, floor:int, target_area:float, aspect:float, privacy:int, multistory:bool=false }

# edge dicts should include:
# { a_id:String, b_id:String, kind:String }  # kind: "door" | "open"
