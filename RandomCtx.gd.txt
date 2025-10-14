extends Node
class_name RandomCtx

var rng := RandomNumberGenerator.new()

func reseed(seed: int) -> void:
	rng.seed = seed

func randi() -> int:
	return rng.randi()

func randf() -> float:
	return rng.randf()

func randf_range(a: float, b: float) -> float:
	return rng.randf_range(a, b)
