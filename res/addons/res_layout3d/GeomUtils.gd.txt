extends Node
class_name GeomUtils

static func shared_wall(a: Rect2, b: Rect2) -> Dictionary:
	var a_end := a.position + a.size
	var b_end := b.position + b.size

	var x_overlap := max(0.0, min(a_end.x, b_end.x) - max(a.position.x, b.position.x))
	var y_overlap := max(0.0, min(a_end.y, b_end.y) - max(a.position.y, b.position.y))

	if is_equal_approx(a_end.y, b.position.y) or is_equal_approx(b_end.y, a.position.y):
		if x_overlap > 0.0:
			var x0 := max(a.position.x, b.position.x)
			var x1 := min(a_end.x, b_end.x)
			var y := a_end.y if is_equal_approx(a_end.y, b.position.y) else b_end.y
			return {"axis": "x", "start": Vector2(x0, y), "end": Vector2(x1, y)}

	if is_equal_approx(a_end.x, b.position.x) or is_equal_approx(b_end.x, a.position.x):
		if y_overlap > 0.0:
			var y0 := max(a.position.y, b.position.y)
			var y1 := min(a_end.y, b_end.y)
			var x := a_end.x if is_equal_approx(a_end.x, b.position.x) else b_end.x
			return {"axis": "z", "start": Vector2(x, y0), "end": Vector2(x, y1)}

	return {}
