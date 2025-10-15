extends RefCounted
class_name PlanCost

const Doors := preload("res://addons/res_layout3d/plan/Doors.gd")
const Partition := preload("res://addons/res_layout3d/partition/Partition.gd")

@export var k_access: float = 1.0
@export var k_dims: float = 1.0
@export var k_shape: float = 1.0
@export var k_expose: float = 1.0
@export var k_floors: float = 100.0

# Set by Planner3D before scoring
var allowed_pairs: Array[Vector2i] = []   # room index pairs that must connect (door or open)
var allowed_label_pairs: Dictionary = {}  # optional label pairs

func total(part: Partition, entry_idx: int = 0, terms: Dictionary = {}) -> float:
	return (
		k_access * C_access(part, entry_idx, terms)
		+ k_dims * C_dims(part)
		+ k_shape * C_shape(part)
		+ k_expose * C_exposure(part, terms)
		+ k_floors * C_overlap(part)
	)

# --- Access: penalize required pairs that lack a viable span for a door/opening
func C_access(part: Partition, entry_idx: int, terms: Dictionary) -> float:
	if part == null or allowed_pairs.is_empty():
		return 0.0
	var seen := {}
	for e in Doors.candidates(part):
		var a := int(e.get("a", -1))
		var b := int(e.get("b", -1))
		if a < 0 or b < 0:
			continue
		var k := Vector2i(min(a, b), max(a, b))
		seen[k] = true
	var miss := 0.0
	for p in allowed_pairs:
		if not seen.has(p):
			miss += 1.0
	return miss

# --- Dims: placeholder (wire to BN later)
func C_dims(part: Partition) -> float:
	return 0.0

# --- Shape: placeholder (concavity later)
func C_shape(part: Partition) -> float:
	return 0.0

# --- Exposure: rooms that require exterior contact but don’t meet it
func C_exposure(part: Partition, terms: Dictionary) -> float:
	if part == null:
		return 0.0
	var fp := part.footprint
	var fp_end := fp.position + fp.size
	var penalty := 0.0
	for i in range(part.rooms.size()):
		var r := part.rooms[i]
		var label := r.label
		var need := float(terms.get(label, {}).get("min_exterior", 0.0))
		if need <= 0.0:
			continue
		var rect := r.rect
		var rect_end := rect.position + rect.size
		var ext_len := 0.0
		# contact length with exterior
		if is_equal_approx(rect.position.x, fp.position.x):
			ext_len += rect.size.y
		if is_equal_approx(rect_end.x, fp_end.x):
			ext_len += rect.size.y
		if is_equal_approx(rect.position.y, fp.position.y):
			ext_len += rect.size.x
		if is_equal_approx(rect_end.y, fp_end.y):
			ext_len += rect.size.x
		if ext_len < need:
			penalty += (need - ext_len)
	return penalty

# --- Floors overlap mismatch (0 if 1 floor). Higher is worse.
func C_overlap(part: Partition) -> float:
	if part == null:
		return 0.0
	var floors := {}
	for r in part.rooms:
		floors[r.floor] = true
	var F := floors.keys()
	F.sort()
	if F.size() <= 1:
		return 0.0
	var total := 0.0
	for r in part.rooms:
		total += r.rect.size.x * r.rect.size.y
	var overlap := 0.0
	for idx in range(1, F.size()):
		overlap += _inter_area_between_floors(part, F[idx - 1], F[idx])
	if total <= 0.0:
		return 1.0
	return 1.0 - clamp(overlap / total, 0.0, 1.0)

func _inter_area_between_floors(part: Partition, f0: int, f1: int) -> float:
	var sum := 0.0
	var A := []
	var B := []
	for r in part.rooms:
		if r.floor == f0:
			A.append(r.rect)
		elif r.floor == f1:
			B.append(r.rect)
	for ra in A:
		for rb in B:
			var inter := ra.intersection(rb)
			if inter.size.x > 0.0 and inter.size.y > 0.0:
				sum += inter.size.x * inter.size.y
	return sum
