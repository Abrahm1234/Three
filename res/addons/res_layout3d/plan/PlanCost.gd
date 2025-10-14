extends Node
class_name PlanCost

const Partition := preload("res://addons/res_layout3d/partition/Partition.gd")
const Doors := preload("res://addons/res_layout3d/plan/Doors.gd")
const ProgramBN := preload("res://addons/res_layout3d/ProgramBN.gd")
const GeomUtils := preload("res://addons/res_layout3d/GeomUtils.gd")

# Paper's cost function weights (Section 5.2)
@export var k_access := 1.0   # Accessibility penalty
@export var k_dims := 1.5     # Dimension likelihood
@export var k_shape := 1.0    # Shape regularity (paper value)
@export var k_expose := 0.8   # Exposure requirement (paper value)
@export var k_floors := 100.0 # Floor compatibility (paper value)

# These are NOT in the paper - we compute overlap but don't include it in total
@export var allowed_pairs: Array[Vector2i] = []
@export var allowed_label_pairs: Dictionary = {}

var bn := ProgramBN.new()

# Paper's cost function: C(x) = k_a·C_access + k_d·C_dims + k_s·C_shape + k_e·C_exposure + k_f·C_floors
func total(part: Partition, entry_idx: int, program_terms: Dictionary) -> float:
	return k_access * C_access(part, entry_idx, program_terms) \
		+ k_dims * C_dims(part) \
		+ k_shape * C_shape(part) \
		+ k_expose * C_exposure(part, program_terms) \
		+ k_floors * C_floors(part, program_terms)

# C_access: Penalizes inaccessible rooms with 1e6 (Section 5.2)
# This is how the paper enforces adjacencies - no separate C_adj needed
func C_access(part: Partition, entry_idx: int, program_terms: Dictionary) -> float:
	var distances: PackedFloat64Array
	
	# Use label-based or pair-based access graph if specified
	if not allowed_label_pairs.is_empty():
		distances = Doors.dists_from_labels(part, entry_idx, allowed_label_pairs)
	elif not allowed_pairs.is_empty():
		distances = Doors.dists_from_pairs(part, entry_idx, allowed_pairs)
	else:
		distances = Doors.dists_from(part, entry_idx)
	
	var cost := 0.0
	for i in range(part.rooms.size()):
		var label := part.rooms[i].label
		var weights := program_terms.get(label, {})
		var w := float(weights.get("access_w", 1.0))
		var d := distances[i]
		
		# KEY: Unreachable rooms get penalty of 1e6 (paper's formula)
		cost += 1e6 if d == INF else w * d
	
	return cost

# C_dims: Negative log-likelihood of room dimensions (Section 5.2)
func C_dims(part: Partition) -> float:
	var cost := 0.0
	for room in part.rooms:
		var size: Vector2 = room.rect.size
		var short_side: float = max(0.001, min(size.x, size.y))
		var long_side: float = max(size.x, size.y)
		var aspect: float = long_side / short_side
		var area: float = size.x * size.y
		
		# Use Bayesian network to get log-likelihood
		cost += -bn.logp_size(room.label, area, aspect)
	
	return cost

# C_shape: Shape regularity from paper (Section 5.2)
# Formula: C_shape(x) = k_r·Σ(1-h_i)·M_c(R_i) + k_g·Σ M_c(G_i) + k_o·Σ e(F_i)
# where M_c(S) = (Area(ConvexHull(S)) - Area(S))/Area(S) + EdgeCount(S)
func C_shape(part: Partition) -> float:
	const k_r := 1.0  # Weight for individual room convexity
	const k_o := 0.3  # Weight for exterior outline complexity
	
	var cost := 0.0
	
	# Individual room shapes (excluding hallways/stairs per paper)
	for i in range(part.rooms.size()):
		var room := part.rooms[i]
		var is_hall := room.label.to_lower() in ["hall", "hallway", "stair", "stairway"]
		var h_i := 1.0 if is_hall else 0.0
		
		# Paper's formula: (1 - h_i) * M_c(R_i)
		cost += (1.0 - h_i) * _M_c_rect(room.rect)
	
	# Exterior outline complexity for each floor
	# Paper counts edge segments in the outline
	cost += k_o * _count_outline_edges(part.footprint)
	
	return cost

# M_c: Convexity measure from paper (Section 5.2)
# M_c(S) = (Area(ConvexHull(S)) - Area(S))/Area(S) + EdgeCount(S)
func _M_c_rect(rect: Rect2) -> float:
	# For axis-aligned rectangles:
	# - ConvexHull(rect) = rect itself
	# - So convexity deficit = 0
	# - EdgeCount = 4
	return 4.0

# Count edges in building outline (for multi-floor buildings, this would be more complex)
func _count_outline_edges(footprint: Rect2) -> float:
	# Simplified: rectangles have 4 edges
	# For non-rectangular footprints, count actual edge segments
	return 4.0

# C_exposure: Exterior wall length requirement (Section 5.2)
func C_exposure(part: Partition, program_terms: Dictionary) -> float:
	var cost := 0.0
	for room in part.rooms:
		var need := float(program_terms.get(room.label, {}).get("min_exterior", 0.0))
		var have := _exterior_len(part, room.rect)
		if have < need:
			cost += (need - have) * 10.0
	return cost

# C_floors: Floor compatibility (Section 5.2, Equation)
# Penalizes upper floors that aren't supported by floors below
func C_floors(part: Partition, program_terms: Dictionary) -> float:
	var cost := 0.0
	
	# Group rooms by floor
	var floors: Dictionary = {}  # floor_num -> Array[Rect2]
	var max_floor := 0
	
	for room in part.rooms:
		# 🔥 FIX: Direct access to floor property (always defined with default = 0)
		var floor_num := int(room.floor)
		
		if not floors.has(floor_num):
			floors[floor_num] = []
		floors[floor_num].append(room.rect)
		max_floor = max(max_floor, floor_num)
	
	# Check each floor above ground for support
	for floor_num in range(1, max_floor + 1):
		if not floors.has(floor_num):
			continue
		
		var current_floor_rects: Array = floors[floor_num]
		var below_floor_rects: Array = floors.get(floor_num - 1, [])
		
		# Calculate total area of current floor
		var current_area := 0.0
		for rect in current_floor_rects:
			current_area += rect.size.x * rect.size.y
		
		# Calculate unsupported area (paper's formula)
		var unsupported_area := 0.0
		for rect in current_floor_rects:
			var room_area: float = rect.size.x * rect.size.y
			var supported_area := 0.0
			
			# Sum intersection areas with rooms below
			for below_rect in below_floor_rects:
				var inter: Rect2 = rect.intersection(below_rect)
				if inter.size.x > 0.0 and inter.size.y > 0.0:
					supported_area += inter.size.x * inter.size.y
			
			# Unsupported = room area minus supported area
			unsupported_area += max(0.0, room_area - supported_area)
		
		# Add penalty proportional to unsupported ratio
		if current_area > 0.0:
			cost += unsupported_area / current_area
	
	return cost

# Helper: Calculate exterior wall length for a room
func _exterior_len(part: Partition, rect: Rect2) -> float:
	var total := 0.0
	var footprint := part.footprint
	var tolerance := part.grid.step_m * 0.25
	
	var rect_end := rect.position + rect.size
	var footprint_end := footprint.position + footprint.size
	
	# Check each edge against footprint boundaries
	if abs(rect.position.x - footprint.position.x) <= tolerance:
		total += rect.size.y
	if abs(rect_end.x - footprint_end.x) <= tolerance:
		total += rect.size.y
	if abs(rect.position.y - footprint.position.y) <= tolerance:
		total += rect.size.x
	if abs(rect_end.y - footprint_end.y) <= tolerance:
		total += rect.size.x
	
	return total

# Diagnostic: Check for overlaps (not part of cost function, just for debugging)
func C_overlap(part: Partition) -> float:
	var cost := 0.0
	for i in range(part.rooms.size()):
		var a: Rect2 = part.rooms[i].rect
		for j in range(i + 1, part.rooms.size()):
			var b: Rect2 = part.rooms[j].rect
			var inter := a.intersection(b)
			if inter.size.x > 0.0 and inter.size.y > 0.0:
				cost += inter.size.x * inter.size.y
	return cost
