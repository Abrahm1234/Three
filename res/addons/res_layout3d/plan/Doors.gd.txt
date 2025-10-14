extends Resource
class_name Doors

const Partition := preload("res://addons/res_layout3d/partition/Partition.gd")

const DOOR_W := 0.9

static func candidates(part: Partition) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for edge in _adjacent_pairs(part):
		var span: Vector2 = edge.get("span", Vector2.ZERO)
		var length: float = span.y - span.x
		if length >= DOOR_W + 0.2:
			out.append(edge)
	return out

static func access_graph(part: Partition) -> Dictionary:
	var graph := {}
	for i in range(part.rooms.size()):
		graph[i] = {}
	for edge in candidates(part):
		graph[edge["a"]][edge["b"]] = 1.0
		graph[edge["b"]][edge["a"]] = 1.0
	return graph

static func access_graph_pairs(part: Partition, pairs: Array[Vector2i]) -> Dictionary:
	var allow := {}
	for p in pairs:
		var key := "%d|%d" % [min(p.x, p.y), max(p.x, p.y)]
		allow[key] = true
	var graph := {}
	for i in range(part.rooms.size()):
		graph[i] = {}
	for edge in _adjacent_pairs(part):
		var a := int(edge.get("a", -1))
		var b := int(edge.get("b", -1))
		if a < 0 or b < 0:
			continue
		var key := "%d|%d" % [min(a, b), max(a, b)]
		if allow.has(key):
			graph[a][b] = 1.0
			graph[b][a] = 1.0
	return graph

static func dists_from(part: Partition, start_idx: int) -> PackedFloat64Array:
	var graph := access_graph(part)
	var count := part.rooms.size()
	var dist := PackedFloat64Array()
	dist.resize(count)
	for i in range(count):
		dist[i] = INF
	if count == 0 or start_idx < 0 or start_idx >= count:
		return dist
	dist[start_idx] = 0.0
	var queue: Array[int] = [start_idx]
	while not queue.is_empty():
		var u := queue.pop_front()
		for v in graph[u].keys():
			if dist[v] == INF:
				dist[v] = dist[u] + 1.0
				queue.append(v)
	return dist

static func dists_from_pairs(part: Partition, start_idx: int, pairs: Array[Vector2i]) -> PackedFloat64Array:
	var graph := access_graph_pairs(part, pairs)
	var count := part.rooms.size()
	var dist := PackedFloat64Array()
	dist.resize(count)
	for i in range(count):
		dist[i] = INF
	if count == 0 or start_idx < 0 or start_idx >= count:
		return dist
	dist[start_idx] = 0.0
	var queue: Array[int] = [start_idx]
	while not queue.is_empty():
		var u := queue.pop_front()
		for v in graph[u].keys():
			if dist[v] == INF:
				dist[v] = dist[u] + 1.0
				queue.append(v)
	return dist

static func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]

static func access_graph_labels(part: Partition, allowed: Dictionary) -> Dictionary:
	var G := {}
	for i in range(part.rooms.size()): G[i] = {}
	for e in _adjacent_pairs(part):
		var i := int(e["a"]); var j := int(e["b"])
		var ka := _pair_key(part.rooms[i].label, part.rooms[j].label)
		if allowed.is_empty() or allowed.has(ka):
			G[i][j] = 1.0; G[j][i] = 1.0
	return G

static func dists_from_labels(part: Partition, start_idx: int, allowed: Dictionary) -> PackedFloat64Array:
	var G := access_graph_labels(part, allowed)
	var N := part.rooms.size()
	var dist := PackedFloat64Array(); dist.resize(N)
	for k in N: dist[k] = INF
	if start_idx < 0 or start_idx >= N: return dist
	dist[start_idx] = 0.0
	var q: Array[int] = [start_idx]
	while not q.is_empty():
		var u := q.pop_front()
		for v in G[u].keys():
			if dist[v] == INF:
				dist[v] = dist[u] + 1.0
				q.append(v)
	return dist

static func _adjacent_pairs(part: Partition) -> Array[Dictionary]:
	var pairs: Array[Dictionary] = []
	for i in range(part.rooms.size()):
		var rect_a := part.rooms[i].rect
		var a_end := rect_a.position + rect_a.size
		for j in range(i + 1, part.rooms.size()):
			var rect_b := part.rooms[j].rect
			var b_end := rect_b.position + rect_b.size

			if is_equal_approx(a_end.x, rect_b.position.x) or is_equal_approx(b_end.x, rect_a.position.x):
				var y0 := max(rect_a.position.y, rect_b.position.y)
				var y1 := min(a_end.y, b_end.y)
				if y1 - y0 > 0.0:
					pairs.append({
						"a": i,
						"b": j,
						"vert": true,
						"span": Vector2(y0, y1),
					})
			if is_equal_approx(a_end.y, rect_b.position.y) or is_equal_approx(b_end.y, rect_a.position.y):
				var x0 := max(rect_a.position.x, rect_b.position.x)
				var x1 := min(a_end.x, b_end.x)
				if x1 - x0 > 0.0:
					pairs.append({
						"a": i,
						"b": j,
						"vert": false,
						"span": Vector2(x0, x1),
					})
	return pairs
