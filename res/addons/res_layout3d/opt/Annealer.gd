extends RefCounted
class_name Annealer

const Partition := preload("res://addons/res_layout3d/partition/Partition.gd")
const PlanCost := preload("res://addons/res_layout3d/plan/PlanCost.gd")
const Validate := preload("res://addons/res_layout3d/partition/Validate.gd")

const DEBUG_VERIFY := true

@export var iters: int = 20000
@export var t0: float = 2.0
@export var alpha: float = 0.995


func run(part: Partition, cost: PlanCost, entry_idx: int, terms: Dictionary) -> void:
	if part == null or cost == null:
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var best_snapshot: Dictionary = part.snapshot()
	var best_cost := cost.total(part, entry_idx, terms)
	var current_cost := best_cost
	var temperature := t0
	var total_steps := max(1, iters)
	var accept_count := 0
	for step in range(total_steps):
		var backup: Dictionary = part.snapshot()
		if not _apply_random_edit(part, rng):
			continue
		if not Validate.feasible(part):
			part.restore(backup)
			temperature *= alpha
			continue
		var candidate_cost := cost.total(part, entry_idx, terms)
		var accept := candidate_cost < current_cost
		if not accept and temperature > 1e-6:
			var delta := current_cost - candidate_cost
			var prob := exp(delta / temperature)
			if rng.randf() < prob:
				accept = true
		if accept:
			current_cost = candidate_cost
			if candidate_cost < best_cost:
				best_cost = candidate_cost
				best_snapshot = part.snapshot()
			accept_count += 1
		else:
			part.restore(backup)
		temperature *= alpha
	part.restore(best_snapshot)
	if DEBUG_VERIFY:
		var final_cost := cost.total(part, entry_idx, terms)
		var accept_rate := float(accept_count) / float(max(1, total_steps))
		print("[ANNEAL] iters=%d accepts=%d accept_rate=%.2f final_cost=%.3f" % [total_steps, accept_count, accept_rate, final_cost])
func _apply_random_edit(part: Partition, rng: RandomNumberGenerator) -> bool:
	for _i in range(6):
		match rng.randi_range(0, 3):
			0:
				if part.nudge_random_room(rng, 0.2):
					return true
			1:
				if part.resize_random_room(rng, 0.15):
					return true
			2:
				if part.slide_shared_wall(rng, 0.25):
					return true
			3:
				if part.swap_adjacent_blocks(rng):
					return true
	return false
