extends Node
class_name PlanOptimize

const Partition := preload("res://addons/res_layout3d/partition/Partition.gd")
const Validate := preload("res://addons/res_layout3d/partition/Validate.gd")
const Moves := preload("res://addons/res_layout3d/plan/PlanMoves.gd")
const Cost := preload("res://addons/res_layout3d/plan/PlanCost.gd")

@export var iters := 20000
@export var temp0 := 1.0
@export var allowed_pairs: Array[Vector2i] = []
@export var allowed_label_pairs: Dictionary = {}

# Paper's Metropolis algorithm (Section 5.1, Algorithm 1)
func optimize(initial: Partition, entry_idx: int, program_terms: Dictionary) -> Partition:
	var cost_eval := Cost.new()
	cost_eval.allowed_pairs = allowed_pairs
	cost_eval.allowed_label_pairs = allowed_label_pairs
	var current := _duplicate_partition(initial)
	var best := _duplicate_partition(initial)

	var current_cost := cost_eval.total(current, entry_idx, program_terms)
	var best_cost := current_cost
	
	print("Initial cost: %.2f" % current_cost)

	for step in range(iters):
		var candidate := _duplicate_partition(current)
		var moved := false
		
		# Paper (Section 5.1, Figure 7): Move probabilities
		# 60% slide wall, 20% snap walls, 20% swap labels
		match randi() % 10:
			0, 1, 2, 3, 4, 5:
				moved = Moves.slide_wall(candidate, randi_range(-5, 5))
			6, 7:
				moved = Moves.snap_walls(candidate)
			8, 9:
				moved = Moves.swap_labels(candidate)
		
		if not moved:
			continue
		
		# Basic feasibility check only
		if not Validate.feasible(candidate):
			continue
		
		# Evaluate cost
		var candidate_cost := cost_eval.total(candidate, entry_idx, program_terms)
		
		# Paper's Metropolis acceptance criterion
		var temperature := max(1e-6, temp0 * (1.0 - float(step) / float(iters)))
		var delta := current_cost - candidate_cost
		var accept_prob := min(1.0, exp(delta / temperature))
		
		if randf() < accept_prob:
			current = candidate
			current_cost = candidate_cost
			
			if candidate_cost < best_cost:
				best = _duplicate_partition(candidate)
				best_cost = candidate_cost
				
				if step % 1000 == 0:
					print("Step %d: Cost %.2f" % [step, best_cost])
	
	print("Final cost: %.2f" % best_cost)
	return best

func _duplicate_partition(src: Partition) -> Partition:
	var copy := Partition.new()
	copy.grid.step_m = src.grid.step_m
	copy.wall_thickness_m = src.wall_thickness_m
	copy.footprint = Rect2(src.footprint.position, src.footprint.size)
	for room in src.rooms:
		var new_room := Partition.Room.new()
		new_room.id = room.id
		new_room.label = room.label
		new_room.rect = Rect2(room.rect.position, room.rect.size)
		new_room.floor = room.floor
		copy.rooms.append(new_room)
	return copy
