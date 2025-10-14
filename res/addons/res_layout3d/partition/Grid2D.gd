extends Resource
class_name Grid2D

@export var step_m := 0.1

func snap(v: Vector2) -> Vector2:
	return Vector2(round(v.x / step_m) * step_m, round(v.y / step_m) * step_m)

func snapf(value: float) -> float:
	return round(value / step_m) * step_m

func snap_rect(r: Rect2) -> Rect2:
	var p := snap(r.position)
	var s := snap(r.position + r.size) - p
	return Rect2(p, s)

static func is_axis_aligned(a: Vector2, b: Vector2) -> bool:
	return is_equal_approx(a.x, b.x) or is_equal_approx(a.y, b.y)

static func rect_poly(r: Rect2) -> PackedVector2Array:
	return PackedVector2Array([
		r.position,
		r.position + Vector2(r.size.x, 0.0),
		r.position + r.size,
		r.position + Vector2(0.0, r.size.y),
	])
