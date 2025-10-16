extends Resource
class_name InitBSP

const Partition := preload("res://addons/res_layout3d/partition/Partition.gd")

# Paper (Section 5, page 4): "The optimization begins from a canonical high-cost configuration,
# in which equally-sized rectangular rooms are packed on a grid on each floor."
static func build(prog: ArchitecturalProgram, step := 0.1) -> Partition:
	# Try adjacency-aware initialization first
	var smart_init := build_adjacency_aware(prog, step)
	if smart_init != null:
		return smart_init
	
	# Fallback to grid-based initialization
	return build_grid(prog, step)

# 🔥 NEW: Adjacency-aware initialization
static func build_adjacency_aware(prog: ArchitecturalProgram, step := 0.1) -> Partition:
	if prog == null or prog.rooms.is_empty():
		return null

	var part := Partition.new()
	part.grid.step_m = step
	part.set_footprint(Rect2(Vector2.ZERO, Vector2(prog.footprint_m.x, prog.footprint_m.y)))

	var adj_graph := _build_adjacency_graph(prog)
	var start_room := _find_start_room(prog, adj_graph)
	if start_room == null or start_room.is_empty():
		return null
	var start_id := String(start_room.get("id", ""))
	if start_id == "":
		return null

	var placed := {}
	var visited := {}
	var queue: Array[String] = []

	var start_rect := _initial_room_rect(prog, start_room, part.footprint)
	placed[start_id] = start_rect
	visited[start_id] = true
	queue.push_back(start_id)

	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var current_rect: Rect2 = placed.get(current_id, Rect2())
		if current_rect == Rect2():
			continue
		var neighbors := adj_graph.get(current_id, [])
		for neighbor_id in neighbors:
			if visited.has(neighbor_id):
				continue
			visited[neighbor_id] = true
			var neighbor_room := _find_room_by_id(prog, neighbor_id)
			if neighbor_room.is_empty():
				continue
			var neighbor_rect := _place_adjacent(current_rect, neighbor_room, prog, placed, part)
			if neighbor_rect != Rect2():
				placed[neighbor_id] = neighbor_rect
				queue.push_back(neighbor_id)

	for room_dict in prog.rooms:
		var rid := String(room_dict.get("id", ""))
		if rid == "":
			continue
		if not placed.has(rid):
			var fallback_rect := _find_empty_space(part.footprint, placed.values(), room_dict, prog)
			placed[rid] = fallback_rect

        for room_dict in prog.rooms:
                var rid := String(room_dict.get("id", ""))
                if rid == "":
                        continue
                var rect: Rect2 = placed.get(rid, Rect2())
                if rect == Rect2():
                        rect = _find_empty_space(part.footprint, placed.values(), room_dict, prog)
                rect.size.x = max(rect.size.x, Partition.MIN_ROOM.x)
                rect.size.y = max(rect.size.y, Partition.MIN_ROOM.y)
                rect = part.grid.snap_rect(rect)
                var room_type := String(room_dict.get("type", ""))
                var floor_num := int(room_dict.get("floor", 0))
                part.add_room_rect(room_type, rect, floor_num)

        part.enforce_required_adjacencies(prog)
        print("✓ Adjacency-aware initialization: placed %d/%d rooms" % [placed.size(), prog.rooms.size()])
        return part

# Build adjacency graph from program edges
static func _build_adjacency_graph(prog: ArchitecturalProgram) -> Dictionary:
	var graph := {}
	
	for edge in prog.edges:
		var a_id: String = edge.get("a_id", "")
		var b_id: String = edge.get("b_id", "")
		
		if a_id == "" or b_id == "":
			continue
		
		if not graph.has(a_id):
			graph[a_id] = []
		if not graph.has(b_id):
			graph[b_id] = []
		
		graph[a_id].append(b_id)
		graph[b_id].append(a_id)
	
	return graph

# Find starting room (Entry, Hall, or most connected)
static func _find_start_room(prog: ArchitecturalProgram, adj_graph: Dictionary) -> Dictionary:
	# Prefer Entry
	for room in prog.rooms:
		var room_type: String = room.get("type", "").to_lower()
		if room_type == "entry" or room_type == "foyer":
			return room
	
	# Fallback to most connected room
	var max_connections := 0
	var best_room: Dictionary = {}
	
	for room in prog.rooms:
		var room_id: String = room["id"]
		var connections: int = adj_graph.get(room_id, []).size()  # ✅ FIX: Add explicit type annotation
		
		if connections > max_connections:
			max_connections = connections
			best_room = room
	
	return best_room if not best_room.is_empty() else prog.rooms[0]

# Get initial rect for starting room
static func _initial_room_rect(prog: ArchitecturalProgram, room: Dictionary, footprint: Rect2) -> Rect2:
	var area_mean: float = room.get("area_pdf", {}).get("mean", 10.0)
	var aspect_mean: float = room.get("aspect_pdf", {}).get("mean", 1.3)
	
	var width := sqrt(area_mean * aspect_mean)
	var height := area_mean / width
	
	# Center-left placement
	var pos := Vector2(
		footprint.position.x + 1.0,
		footprint.position.y + (footprint.size.y - height) * 0.5
	)
	
	return Rect2(pos, Vector2(width, height))

# Find room by ID
static func _find_room_by_id(prog: ArchitecturalProgram, room_id: String) -> Dictionary:
	for room in prog.rooms:
		if room["id"] == room_id:
			return room
	return {}

# Place a room adjacent to an existing room
static func _place_adjacent(anchor: Rect2, room: Dictionary, prog: ArchitecturalProgram, 
							 placed: Dictionary, part: Partition) -> Rect2:
	var area_mean: float = room.get("area_pdf", {}).get("mean", 10.0)
	var aspect_mean: float = room.get("aspect_pdf", {}).get("mean", 1.3)
	
	var width := sqrt(area_mean * aspect_mean)
	var height := area_mean / width
	
	# Try placing on each side of the anchor room
	var candidates: Array[Rect2] = [
		# Right
		Rect2(Vector2(anchor.end.x, anchor.position.y), Vector2(width, height)),
		# Below
		Rect2(Vector2(anchor.position.x, anchor.end.y), Vector2(width, height)),
		# Above
		Rect2(Vector2(anchor.position.x, anchor.position.y - height), Vector2(width, height)),
		# Left
		Rect2(Vector2(anchor.position.x - width, anchor.position.y), Vector2(width, height)),
	]
	
	# Pick first candidate that fits and doesn't overlap
	for candidate in candidates:
		if _fits_in_footprint(candidate, part.footprint) and \
		   not _overlaps_existing(candidate, placed.values()):
			return candidate
	
	# Fallback: return zero rect (will be placed in empty space later)
	return Rect2()  # ✅ FIX: Use Rect2() instead of Rect2.ZERO

# Check if rect fits within footprint
static func _fits_in_footprint(rect: Rect2, footprint: Rect2) -> bool:
	return footprint.encloses(rect)

# Check if rect overlaps any existing rects
static func _overlaps_existing(rect: Rect2, existing: Array) -> bool:
	for other in existing:
		if typeof(other) == TYPE_RECT2:
			var other_rect := other as Rect2
			if rect.intersects(other_rect):
				return true
	return false

# Find empty space for unplaced room
static func _find_empty_space(footprint: Rect2, placed_rects: Array, room: Dictionary, 
							  prog: ArchitecturalProgram) -> Rect2:
	var area_mean: float = room.get("area_pdf", {}).get("mean", 10.0)
	var aspect_mean: float = room.get("aspect_pdf", {}).get("mean", 1.3)
	
	var width := sqrt(area_mean * aspect_mean)
	var height := area_mean / width
	
	# Try grid positions
	var cols := int(ceil(footprint.size.x / width))
	var rows := int(ceil(footprint.size.y / height))
	
	for row in range(rows):
		for col in range(cols):
			var pos := Vector2(col * width, row * height)
			var candidate := Rect2(pos, Vector2(width, height))
			
			if _fits_in_footprint(candidate, footprint) and \
			   not _overlaps_existing(candidate, placed_rects):
				return candidate
	
	# Fallback: place in top-right corner
	return Rect2(
		Vector2(footprint.end.x - width, footprint.position.y),
		Vector2(width, height)
	)

# 🔥 FALLBACK: Original grid-based initialization
static func build_grid(prog: ArchitecturalProgram, step := 0.1) -> Partition:
	var part := Partition.new()
	part.grid.step_m = step
	part.set_footprint(Rect2(Vector2.ZERO, Vector2(prog.footprint_m.x, prog.footprint_m.y)))
	
	var count := prog.rooms.size()
	if count == 0:
		return part
	
	# Pack equally-sized rooms on a grid
	var cols := int(ceil(sqrt(float(count))))
	var rows := int(ceil(float(count) / float(cols)))
	
	var cell_w := part.footprint.size.x / float(cols)
	var cell_h := part.footprint.size.y / float(rows)
	
	for i in range(count):
		var row := i / cols
		var col := i % cols
		var pos := Vector2(col * cell_w, row * cell_h)
		var size := Vector2(cell_w, cell_h)
		
		# Snap to grid
		pos = part.grid.snap(pos)
		size = part.grid.snap(size)
		
		# Ensure minimum room size
		size.x = max(size.x, Partition.MIN_ROOM.x)
		size.y = max(size.y, Partition.MIN_ROOM.y)
		
		# Assign room label and floor from architectural program
		var room_type := String(prog.rooms[i].get("type", ""))
		var floor_num := int(prog.rooms[i].get("floor", 0))
		part.add_room_rect(room_type, Rect2(pos, size), floor_num)
	
	print("✓ Grid-based initialization: %d rooms" % count)
	return part