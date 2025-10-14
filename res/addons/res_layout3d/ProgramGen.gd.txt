extends Node
class_name ProgramGen

func sample(req: Dictionary) -> ArchitecturalProgram:
	var program := ArchitecturalProgram.new()
	program.footprint_m = req.get("footprint", Vector2i(16, 12))

	var beds := int(req.get("bedrooms", 3))
	var baths := int(req.get("bathrooms", 2))
	var floors := int(req.get("floors", 1))
	var sqft := float(req.get("sq_m2", program.footprint_m.x * program.footprint_m.y))

	var rooms: Array[Dictionary] = []
	
	# ===== CORE ROOMS (Always included) =====
	
	# Entry
	rooms.append({
		"id": "entry",
		"type": "Entry",
		"floor": 0,
		"needs_window": true,
		"area_pdf": {"mean": 6.0, "sigma": 1.5},
		"aspect_pdf": {"mean": 1.2, "sigma": 0.2},
	})
	
	# Living Room
	rooms.append({
		"id": "living",
		"type": "Living",
		"floor": 0,
		"needs_window": true,
		"area_pdf": {"mean": 28.0, "sigma": 6.0},
		"aspect_pdf": {"mean": 1.5, "sigma": 0.4},
	})
	
	# Kitchen
	rooms.append({
		"id": "kitchen",
		"type": "Kitchen",
		"floor": 0,
		"needs_window": true,
		"area_pdf": {"mean": 16.0, "sigma": 3.0},
		"aspect_pdf": {"mean": 1.1, "sigma": 0.2},
	})
	
	# ===== CONDITIONAL ROOMS (Based on size/floors) =====
	
	# Dining Room (if sqft > 120 m²)
	if sqft > 120.0:
		rooms.append({
			"id": "dining",
			"type": "Dining",
			"floor": 0,
			"needs_window": true,
			"area_pdf": {"mean": 12.0, "sigma": 3.0},
			"aspect_pdf": {"mean": 1.2, "sigma": 0.3},
		})
	
	# Pantry (if sqft > 160 m²)
	if sqft > 160.0:
		rooms.append({
			"id": "pantry",
			"type": "Pantry",
			"floor": 0,
			"needs_window": false,
			"area_pdf": {"mean": 3.0, "sigma": 1.0},
			"aspect_pdf": {"mean": 1.5, "sigma": 0.3},
		})
	
	# Laundry (if beds >= 3)
	if beds >= 3:
		rooms.append({
			"id": "laundry",
			"type": "Laundry",
			"floor": 0,
			"needs_window": false,
			"area_pdf": {"mean": 5.0, "sigma": 1.5},
			"aspect_pdf": {"mean": 1.2, "sigma": 0.2},
		})
	
	# Office/Study (if sqft > 180 m²)
	if sqft > 180.0:
		rooms.append({
			"id": "office",
			"type": "Office",
			"floor": 0,
			"needs_window": true,
			"area_pdf": {"mean": 10.0, "sigma": 2.0},
			"aspect_pdf": {"mean": 1.3, "sigma": 0.2},
		})
	
	# Garage (if sqft > 140 m²)
	if sqft > 140.0:
		rooms.append({
			"id": "garage",
			"type": "Garage",
			"floor": 0,
			"needs_window": false,
			"area_pdf": {"mean": 45.0, "sigma": 10.0},
			"aspect_pdf": {"mean": 1.2, "sigma": 0.2},
		})
	
	# Hall (if floors > 1 or beds > 3)
	if floors > 1 or beds > 3:
		rooms.append({
			"id": "hall",
			"type": "Hall",
			"floor": 0 if floors == 1 else 1,  # Upper floor hall for multi-story
			"needs_window": false,
			"area_pdf": {"mean": 8.0, "sigma": 2.0},
			"aspect_pdf": {"mean": 2.5, "sigma": 0.5},
		})
	
	# Porch (if sqft > 100 m²)
	if sqft > 100.0:
		rooms.append({
			"id": "porch",
			"type": "Porch",
			"floor": 0,
			"needs_window": false,
			"area_pdf": {"mean": 15.0, "sigma": 5.0},
			"aspect_pdf": {"mean": 3.0, "sigma": 1.0},
		})
	
	# Stair (if floors > 1)
	if floors > 1:
		for f in range(floors):
			rooms.append({
				"id": "stair_%d" % f,
				"type": "Stair",
				"floor": f,
				"needs_window": false,
				"area_pdf": {"mean": 8.0, "sigma": 2.0},
				"aspect_pdf": {"mean": 2.0, "sigma": 0.3},
			})
	
	# ===== BEDROOMS =====
	
	for i in range(beds):
		var floor_num := 0
		# Move some bedrooms to upper floor if multi-story
		if floors > 1 and i > 0:  # Keep master on main floor
			floor_num = 1
		
		rooms.append({
			"id": "bed_%d" % (i + 1),
			"type": "Bedroom",
			"floor": floor_num,
			"needs_window": true,
			"area_pdf": {"mean": 12.0, "sigma": 2.5},
			"aspect_pdf": {"mean": 1.4, "sigma": 0.3},
		})
		
		# Add closet for each bedroom (if sqft > 140 m²)
		if sqft > 140.0:
			rooms.append({
				"id": "closet_%d" % (i + 1),
				"type": "Closet",
				"floor": floor_num,
				"needs_window": false,
				"area_pdf": {"mean": 4.0, "sigma": 1.0},
				"aspect_pdf": {"mean": 1.5, "sigma": 0.3},
			})
	
	# ===== BATHROOMS =====
	
	for i in range(baths):
		rooms.append({
			"id": "bath_%d" % (i + 1),
			"type": "Bathroom",
			"floor": 0 if i == 0 else (1 if floors > 1 else 0),  # Spread across floors
			"needs_window": true,
			"area_pdf": {"mean": 5.0, "sigma": 1.2},
			"aspect_pdf": {"mean": 1.2, "sigma": 0.2},
		})
	
	# ===== ADJACENCIES =====
	
	var edges: Array[Dictionary] = [
		{"a_id": "entry", "b_id": "living", "type": "door"},
		{"a_id": "living", "b_id": "kitchen", "type": "open"},
	]
	
	# Add dining adjacencies
	if sqft > 120.0:
		edges.append({"a_id": "living", "b_id": "dining", "type": "open"})
		edges.append({"a_id": "dining", "b_id": "kitchen", "type": "open"})
	
	# Add pantry adjacency
	if sqft > 160.0:
		edges.append({"a_id": "kitchen", "b_id": "pantry", "type": "door"})
	
	# Add laundry adjacency
	if beds >= 3:
		edges.append({"a_id": "kitchen", "b_id": "laundry", "type": "door"})
	
	# Add office adjacency
	if sqft > 180.0:
		edges.append({"a_id": "entry", "b_id": "office", "type": "door"})
	
	# Add garage adjacency
	if sqft > 140.0:
		edges.append({"a_id": "entry", "b_id": "garage", "type": "door"})
	
	# Add porch adjacency
	if sqft > 100.0:
		edges.append({"a_id": "living", "b_id": "porch", "type": "door"})
	
	# Add bedroom adjacencies
	for i in range(beds):
		edges.append({"a_id": "living", "b_id": "bed_%d" % (i + 1), "type": "door"})
		
		# Add closet adjacencies
		if sqft > 140.0:
			edges.append({"a_id": "bed_%d" % (i + 1), "b_id": "closet_%d" % (i + 1), "type": "door"})
	
	# Add stair adjacencies (if multi-story)
	if floors > 1:
		edges.append({"a_id": "entry", "b_id": "stair_0", "type": "door"})
		edges.append({"a_id": "hall", "b_id": "stair_1", "type": "door"})
		
		# Connect hall to upper floor bedrooms
		for i in range(1, beds):  # Skip master bedroom (stays on main floor)
			edges.append({"a_id": "hall", "b_id": "bed_%d" % (i + 1), "type": "door"})

	program.rooms = rooms
	program.edges = edges
	return program
