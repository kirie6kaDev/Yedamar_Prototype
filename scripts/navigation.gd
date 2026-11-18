extends RefCounted

const CELL := 4.0
const CLEARANCE := 0.8
const MAX_SLOPE := 0.82
const BUCKET := 64.0
var _height: Callable
var _bounds := Rect2()
var _grid := AStarGrid2D.new()
var _obstacles: Dictionary = {}
var _dynamic: Dictionary = {}
var _dynamic_points: Array = []
# Lightweight profiling counters (read by tests/playtest.gd; negligible cost).
var stats_calls := 0
var stats_usec := 0
var stats_max_usec := 0
var stats_failed := 0


func configure(sampler: Callable, area: Rect2, obstacles: Array) -> void:
	_height = sampler
	_bounds = area.grow(-1.5)
	_obstacles.clear()
	_dynamic.clear()
	_dynamic_points.clear()
	for obstacle: Dictionary in obstacles:
		var center: Vector3 = obstacle.position
		var radius: float = float(obstacle.radius) + CLEARANCE
		var bucket_radius := radius + CELL * 0.7
		var first := Vector2i(floori((center.x - bucket_radius) / BUCKET), floori((center.z - bucket_radius) / BUCKET))
		var last := Vector2i(floori((center.x + bucket_radius) / BUCKET), floori((center.z + bucket_radius) / BUCKET))
		for y in range(first.y, last.y + 1):
			for x in range(first.x, last.x + 1):
				var key := Vector2i(x, y)
				if not _obstacles.has(key):
					_obstacles[key] = []
				_obstacles[key].append(Vector3(center.x, radius, center.z))
	_grid.region = Rect2i(Vector2i.ZERO, Vector2i(floori(_bounds.size.x / CELL) + 1, floori(_bounds.size.y / CELL) + 1))
	_grid.cell_size = Vector2.ONE * CELL
	_grid.offset = _bounds.position
	_grid.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	_grid.default_compute_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.default_estimate_heuristic = AStarGrid2D.HEURISTIC_OCTILE
	_grid.update()
	for y in range(_grid.region.size.y):
		for x in range(_grid.region.size.x):
			var id := Vector2i(x, y)
			var p := _grid.get_point_position(id)
			_grid.set_point_solid(id, not is_walkable(p, CELL * 0.7))


func is_walkable(p: Vector2, extra_clearance: float = 0.0) -> bool:
	if not _terrain_ok(p):
		return false
	var key:=Vector2i(floori(p.x / BUCKET),floori(p.y / BUCKET))
	for circle: Vector3 in _obstacles.get(key, []):
		if p.distance_squared_to(Vector2(circle.x, circle.z)) < pow(circle.y + extra_clearance, 2.0):
			return false
	for circle: Vector3 in _dynamic.get(key, []):
		if p.distance_squared_to(Vector2(circle.x, circle.z)) < pow(circle.y + extra_clearance, 2.0):
			return false
	return true


## Runtime step check used by moving actors: only the prop body itself blocks,
## the CLEARANCE band is a planning margin. Prevents a planned path that grazes
## the margin from being rejected mid-walk (the main cause of "cannot reach").
func is_passable(p: Vector2) -> bool:
	return is_walkable(p, -CLEARANCE)


func _terrain_ok(p: Vector2) -> bool:
	if not _bounds.has_point(p):
		return false
	var elevation := float(_height.call(p.x, p.y))
	if elevation < 0.5:
		return false
	var dx := (float(_height.call(p.x + 3.0, p.y)) - float(_height.call(p.x - 3.0, p.y))) / 6.0
	var dz := (float(_height.call(p.x, p.y + 3.0)) - float(_height.call(p.x, p.y - 3.0))) / 6.0
	return Vector2(dx, dz).length() <= MAX_SLOPE

func set_dynamic_obstacles(obstacles:Array)->void:
	var changed:Array=_dynamic_points.duplicate(true)
	changed.append_array(obstacles)
	_dynamic_points=obstacles.duplicate(true)
	_dynamic.clear()
	for obstacle:Dictionary in obstacles:
		var center:Vector3=obstacle.position
		var radius:float=float(obstacle.radius)+CLEARANCE
		var first:=Vector2i(floori((center.x-radius-CELL)/BUCKET),floori((center.z-radius-CELL)/BUCKET))
		var last:=Vector2i(floori((center.x+radius+CELL)/BUCKET),floori((center.z+radius+CELL)/BUCKET))
		for y in range(first.y,last.y+1):
			for x in range(first.x,last.x+1):
				var key:=Vector2i(x,y)
				if not _dynamic.has(key): _dynamic[key]=[]
				_dynamic[key].append(Vector3(center.x,radius,center.z))
	for obstacle:Dictionary in changed:
		var center:=Vector2(obstacle.position.x,obstacle.position.z)
		var radius:float=float(obstacle.radius)+CLEARANCE+CELL*2
		var first:=Vector2i(((center-Vector2.ONE*radius-_bounds.position)/CELL).floor())
		var last:=Vector2i(((center+Vector2.ONE*radius-_bounds.position)/CELL).ceil())
		for y in range(maxi(0,first.y),mini(_grid.region.end.y,last.y+1)):
			for x in range(maxi(0,first.x),mini(_grid.region.end.x,last.x+1)):
				var id:=Vector2i(x,y)
				_grid.set_point_solid(id,not is_walkable(_grid.get_point_position(id),CELL*.7))


func _clear(a: Vector2, b: Vector2) -> bool:
	# Terrain (water/slope) is sampled; props are tested exactly against the
	# segment. Point sampling every 2.5 m used to cut through small props, and
	# the actor then refused the step at runtime and dropped the order.
	var count := maxi(1, ceili(a.distance_to(b) / 2.5))
	for i in range(count + 1):
		if not _terrain_ok(a.lerp(b, float(i) / count)):
			return false
	return _segment_free(a, b)


func _segment_free(a: Vector2, b: Vector2) -> bool:
	var segment := b - a
	var length_squared := maxf(0.0001, segment.length_squared())
	var first := Vector2i(floori(minf(a.x, b.x) / BUCKET), floori(minf(a.y, b.y) / BUCKET))
	var last := Vector2i(floori(maxf(a.x, b.x) / BUCKET), floori(maxf(a.y, b.y) / BUCKET))
	for y in range(first.y, last.y + 1):
		for x in range(first.x, last.x + 1):
			var key := Vector2i(x, y)
			for source: Dictionary in [_obstacles, _dynamic]:
				for circle: Vector3 in source.get(key, []):
					var center := Vector2(circle.x, circle.z)
					var nearest := a + segment * clampf((center - a).dot(segment) / length_squared, 0.0, 1.0)
					if nearest.distance_squared_to(center) < circle.y * circle.y:
						return false
	return true


func _nearby(p: Vector2) -> Vector2i:
	var snapped := Vector2i(((p - _bounds.position) / CELL).round())
	snapped.x = clampi(snapped.x, 0, _grid.region.size.x - 1)
	snapped.y = clampi(snapped.y, 0, _grid.region.size.y - 1)
	for radius in range(10):
		var closest := Vector2i(-1, -1)
		var best := INF
		for y in range(snapped.y - radius, snapped.y + radius + 1):
			for x in range(snapped.x - radius, snapped.x + radius + 1):
				var id := Vector2i(x, y)
				if not _grid.region.has_point(id) or _grid.is_point_solid(id):
					continue
				var world := _grid.get_point_position(id)
				var d := world.distance_squared_to(p)
				if d < best:
					best = d
					closest = id
		if closest.x >= 0:
			return closest
	return Vector2i(-1, -1)


## strict=true skips the straight-line/shortcut smoothing and returns the raw
## grid route (every waypoint has full clearance); used as a recovery path.
func path(start: Vector3, finish: Vector3, strict: bool = false) -> PackedVector3Array:
	var t0 := Time.get_ticks_usec()
	var result := _path(start, finish, strict)
	var spent := Time.get_ticks_usec() - t0
	stats_calls += 1
	stats_usec += spent
	stats_max_usec = maxi(stats_max_usec, spent)
	if result.is_empty():
		stats_failed += 1
	return result


func _path(start: Vector3, finish: Vector3, strict: bool = false) -> PackedVector3Array:
	var result := PackedVector3Array()
	var a := Vector2(start.x, start.z)
	var b := Vector2(finish.x, finish.z)
	if not strict and _clear(a, b):
		result.append(Vector3(b.x, float(_height.call(b.x, b.y)), b.y))
		return result
	var first := _nearby(a)
	var last := _nearby(b)
	if first.x < 0 or last.x < 0:
		return result
	var route := _grid.get_point_path(first, last)
	if route.is_empty():
		return result
	if is_walkable(b) and _clear(route[-1], b):
		route.append(b)
	else:
		# Reach the actual free edge of a prop instead of stopping a whole grid cell away.
		var approach := route[-1]
		var last_cell := route[-1]
		var steps := maxi(1, ceili(last_cell.distance_to(b) / 0.5))
		for i in range(1, steps + 1):
			var candidate := last_cell.lerp(b, float(i) / steps)
			if not is_walkable(candidate):
				break
			approach = candidate
		if approach.distance_squared_to(last_cell) > 0.01:
			route.append(approach)
	if strict:
		for p in route:
			result.append(Vector3(p.x, float(_height.call(p.x, p.y)), p.y))
		return result
	var cursor := 0
	var previous := a
	while cursor < route.size():
		var farthest := cursor
		# Shortcut only across verified terrain, retaining turns around obstacles.
		var limit := mini(route.size() - 1, cursor + 36)
		for candidate in range(limit, cursor, -1):
			if _clear(previous, route[candidate]):
				farthest = candidate
				break
		var p := route[farthest]
		result.append(Vector3(p.x, float(_height.call(p.x, p.y)), p.y))
		previous = p
		cursor = farthest + 1
	return result
