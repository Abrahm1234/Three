extends Node
class_name ProgramGen

func sample(req: Dictionary) -> ArchitecturalProgram:
	var program := ArchitecturalProgram.new()
	program.floors = int(req.get("floors", 1))
	var fp: Vector2i = req.get("footprint", Vector2i(16, 12))
	program.footprint_m = fp

	var beds := int(req.get("bedrooms", 3))
	var baths := int(req.get("bathrooms", 2))
	var sq_m2 := float(req.get("sq_m2", fp.x * fp.y))

	# --- Rooms (bubble nodes) ---
	var rooms: Array[Dictionary] = []
	var add_room := func(id: String, typ: String, floor: int) -> void:
		var room := {
			"id": id,
			"type": typ,
			"floor": floor,
			"target_area": 12.0,      # placeholder target; BN will override via PlanCost likelihoods
			"aspect": 1.2,
			"privacy": ArchitecturalProgram.default_privacy(typ),
			"multistory": false
		}
		rooms.append(room)

	# Public core
	add_room.call("foyer", "Foyer", 0)
	add_room.call("living", "Living", 0)
	add_room.call("kitchen", "Kitchen", 0)
	if sq_m2 > 110.0:
		add_room.call("dining", "Dining", 0)

	# Bedrooms + baths
	var upstairs_beds: Array[String] = []
	var ground_beds: Array[String] = []
	for i in range(beds):
		var bed_id := "bed_%d" % i
		var bed_floor := 0
		if program.floors > 1 and beds > 2 and i > 0:
			bed_floor = 1
		add_room.call(bed_id, "Bedroom", bed_floor)
		if bed_floor == 1:
			upstairs_beds.append(bed_id)
		else:
			ground_beds.append(bed_id)

	var upstairs_baths: Array[String] = []
	var ground_baths: Array[String] = []
	for i in range(baths):
		var bath_id := "bath_%d" % i
		var bath_floor := 0 if i == 0 else min(1, program.floors - 1)
		add_room.call(bath_id, "Bathroom", bath_floor)
		if bath_floor == 1:
			upstairs_baths.append(bath_id)
		else:
			ground_baths.append(bath_id)

	# Circulation
	add_room.call("hall_0", "Hall", 0)
	if program.floors > 1:
		add_room.call("stairs", "Stairs", 0)
		rooms.back()["multistory"] = true
		add_room.call("hall_1", "Hall", 1)

	# Garage / patio optional
	var has_garage := false
	var has_patio := false
	if sq_m2 > 140.0:
		add_room.call("garage", "Garage", 0)
		has_garage = true
	if sq_m2 > 120.0:
		add_room.call("patio", "Patio", 0)
		has_patio = true

	program.rooms = rooms
	program.entry_room_id = "foyer"

	# --- Bubble adjacencies (edges) ---
	var E: Array[Dictionary] = []
	var link := func(a: String, b: String, kind := "door") -> void:
		E.append({"a_id": a, "b_id": b, "kind": kind})

	# Public core openness
	link.call("foyer", "living", "open")
	link.call("living", "kitchen", "open")
	if sq_m2 > 110.0:
		link.call("kitchen", "dining", "open")

	# Access to bedrooms/baths via halls
	link.call("living", "hall_0", "door")
	for bed_id in ground_beds:
		link.call("hall_0", bed_id, "door")
	if ground_baths.size() > 0:
		link.call("hall_0", ground_baths[0], "door")

	# Stairs and upstairs hall
	if program.floors > 1:
		link.call("living", "stairs", "door")
		link.call("stairs", "hall_1", "open")
		for bed_id in upstairs_beds:
			link.call("hall_1", bed_id, "door")
		for bath_id in upstairs_baths:
			link.call("hall_1", bath_id, "door")

	# Outside connections
	if has_garage:
		link.call("hall_0", "garage", "door")
	if has_patio:
		link.call("living", "patio", "french")

	program.edges = E
	return program

