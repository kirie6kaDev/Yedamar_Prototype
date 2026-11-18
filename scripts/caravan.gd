extends Node3D

signal notice(text: String)
signal arrived
signal status_changed

const CART_SCENE := preload("res://assets/environment/fantasy-town-kit/cart.glb")
const HORSE_SCENE := preload("res://assets/animals/horse.glb")
const MINUTES_PER_SECOND := 1.0
const WHEEL_RADIUS := 0.70164

class WagonNavigation:
	extends "res://scripts/navigation.gd"

	# A long wagon cannot shave past a prop between sampled shortcut points.
	func _clear(a: Vector2, b: Vector2) -> bool:
		if not super._clear(a, b):
			return false
		var segment := b - a
		var length_squared := maxf(0.001, segment.length_squared())
		var count := maxi(1, ceili(segment.length() / 32.0))
		var visited: Dictionary = {}
		for i in range(count + 1):
			var p := a.lerp(b, float(i) / count)
			var cell := Vector2i(floori(p.x / BUCKET), floori(p.y / BUCKET))
			for y in range(cell.y - 1, cell.y + 2):
				for x in range(cell.x - 1, cell.x + 2):
					for circle: Vector3 in _obstacles.get(Vector2i(x, y), []) + _dynamic.get(Vector2i(x,y),[]):
						if visited.has(circle):
							continue
						visited[circle] = true
						var center := Vector2(circle.x, circle.z)
						var nearest := a + segment * clampf((center - a).dot(segment) / length_squared, 0.0, 1.0)
						if nearest.distance_squared_to(center) < pow(circle.y + 0.04, 2.0):
							return false
		return true

var storage: Dictionary = {}
var animal_stats: Dictionary = {"name": "Зорька", "health": 100.0, "stamina": 100.0, "hunger": 100.0, "thirst": 100.0}
var mode: String = "idle"
var passengers: Array[String] = []
var animal_available: bool = true
var day_time: float = 480.0
var day_number: int = 1
var _world: Node3D
var _nav: RefCounted
var _wagon_nav: RefCounted
var _brother: Node3D
var _sister: Node3D
var _cart: Node3D
var _horse: Node3D
var _horse_model: Node3D
var _horse_animation: AnimationPlayer
var _horse_clips: Dictionary = {}
var _wheels: Array[Node3D] = []
var _harness: Node3D
var _lamps: Array[OmniLight3D] = []
var _sun: DirectionalLight3D
var _environment: Environment
var _route := PackedVector3Array()
var _route_index := 0
var _destination := Vector3.ZERO
var _has_destination := false
var _requested_mode := "animal"
var _manual_attached := false
var _boarding_elapsed := 0.0
var _wheel_angle := 0.0
var _eating_left := 0.0
var _tick := 0.0
var _clock_tick := 0.0
var _sleeping := false
var _moving := false
var _configured := false
var _heading := 0.0
var _pending_restore: Dictionary = {}
var _animal_label: Label3D
var _human_poses: Dictionary = {}


func configure(world: Node3D, nav: RefCounted, brother: Node3D, sister: Node3D) -> void:
	_world = world
	_nav = nav
	_brother = brother
	_sister = sister
	_configured = true
	if is_node_ready():
		_build()


func build(world: Node3D, nav: RefCounted, brother: Node3D, sister: Node3D) -> void:
	configure(world, nav, brother, sister)


func _ready() -> void:
	if _configured:
		_build()


func _build() -> void:
	if is_instance_valid(_cart):
		return
	_wagon_nav = WagonNavigation.new()
	var expanded: Array = []
	for obstacle: Dictionary in _world.obstacles:
		if obstacle.has("industry_id") or obstacle.has("settlement_id") or obstacle.has("farm_id"):
			continue
		expanded.append({"position": obstacle.position, "radius": float(obstacle.radius) + 0.5})
	_wagon_nav.configure(Callable(_world, "sample_height"), _world.bounds, expanded)
	_cart = Node3D.new()
	_cart.name = "Повозка"
	add_child(_cart)
	_cart.global_position = _ground(Vector2(4008.0, 4412.0))
	if not _wagon_nav.is_walkable(Vector2(_cart.global_position.x, _cart.global_position.z)):
		_cart.global_position = _safe_ground(_brother.global_position + Vector3(4, 0, 8))
	var cart_model := CART_SCENE.instantiate() as Node3D
	cart_model.scale = Vector3.ONE * 3.0
	_cart.add_child(cart_model)
	for mesh: Node in cart_model.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name).begins_with("Group"):
			var wheel := mesh as MeshInstance3D
			var pivot := Node3D.new()
			wheel.get_parent().add_child(pivot)
			pivot.transform = wheel.transform
			var center := wheel.get_aabb().get_center()
			pivot.position += wheel.basis * center
			wheel.reparent(pivot, false)
			wheel.transform = Transform3D(Basis.IDENTITY, -center)
			_wheels.append(pivot)
	# Seat cushions fit inside the original Kenney cart body.
	_box(_cart, Vector3(0, 0.85, 0.25), Vector3(1.6, 0.13, 0.65), Color("#6f6650"))
	_box(_cart, Vector3(0, 0.83, -0.65), Vector3(1.6, 0.12, 0.62), Color("#8e7955"))
	for side in [-1.0, 1.0]:
		_beam(_cart, Vector3(side * 0.70, 0.82, 0.75), Vector3(side * 0.50, 0.95, 3.5), 0.075, Color("#685037"))
	_harness = Node3D.new()
	_cart.add_child(_harness)
	for side in [-1.0, 1.0]:
		_beam(_harness, Vector3(side * 0.25, 1.35, 0.65), Vector3(side * 0.28, 1.45, 4.35), 0.028, Color("#3c3026"))
	_horse = Node3D.new()
	_horse.name = "Зорька"
	add_child(_horse)
	_horse_model = HORSE_SCENE.instantiate() as Node3D
	_horse_model.scale = Vector3.ONE * 0.4
	_horse_model.position.y = 0.006
	_horse.add_child(_horse_model)
	for node: Node in _horse_model.find_children("*", "AnimationPlayer", true, false):
		_horse_animation = node as AnimationPlayer
		break
	if _horse_animation:
		for clip in _horse_animation.get_animation_list():
			var simple := String(clip).get_slice("|", String(clip).get_slice_count("|") - 1)
			_horse_clips[simple] = clip
			if simple in ["Walk", "Gallop", "Idle", "Idle_Headlow", "Eating"]:
				_horse_animation.get_animation(clip).loop_mode = Animation.LOOP_LINEAR
	_horse.global_position = _ground(Vector2(_cart.global_position.x, _cart.global_position.z + 3.7))
	_add_collar()
	_animal_label = Label3D.new()
	_animal_label.text = "Зорька · вьючная лошадь"
	_animal_label.font_size = 40
	_animal_label.pixel_size = 0.008
	_animal_label.outline_size = 9
	_animal_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_animal_label.position.y = 2.3
	_horse.add_child(_animal_label)
	_register("wagon", "cart", "Дорожная повозка", _cart, Vector3(2.8, 1.9, 3.1), "Повозка перевозит семью и общий груз. Можно запрячь Зорьку или везти её вручную.")
	_register("pack_animal", "animal", "Зорька", _horse, Vector3(1.2, 2.1, 2.5), "Вьючная лошадь. Ест сено, морковь и немного ягод. Ей нужны вода и отдых.")
	for node: Node in _world.find_children("*", "DirectionalLight3D", true, false):
		_sun = node as DirectionalLight3D
		break
	for node: Node in _world.find_children("*", "WorldEnvironment", true, false):
		_environment = (node as WorldEnvironment).environment
		break
	for side in [-1.0, 1.0]:
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("#ffc880")
		lamp.light_energy = 1.6
		lamp.omni_range = 8.0
		lamp.position = Vector3(side * 0.8, 1.8, 0.8)
		_cart.add_child(lamp)
		_lamps.append(lamp)
	_update_light()
	_update_objects()
	if not _pending_restore.is_empty():
		var data := _pending_restore
		_pending_restore = {}
		restore(data)


func _box(parent: Node3D, at: Vector3, size: Vector3, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.position = at
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.9
	mesh.material_override = material
	parent.add_child(mesh)


func _beam(parent: Node3D, a: Vector3, b: Vector3, width: float, color: Color) -> void:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(width, width, a.distance_to(b))
	mesh.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	mesh.material_override = material
	parent.add_child(mesh)
	mesh.position = (a + b) * 0.5
	mesh.look_at(parent.to_global(b))


func _add_collar() -> void:
	var collar := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = 0.34
	torus.outer_radius = 0.41
	torus.rings = 16
	torus.ring_segments = 6
	collar.mesh = torus
	collar.position = Vector3(0, 1.08, 0.43)
	collar.rotation.x = PI * 0.5
	collar.scale.x = 0.9
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("#493a28")
	collar.material_override = material
	_horse.add_child(collar)


func _register(id: String, type: String, title: String, node: Node3D, size: Vector3, description: String) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 2
	body.collision_mask = 0
	body.set_meta("object_id", id)
	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	collider.shape = box
	collider.position.y = size.y * 0.5
	body.add_child(collider)
	node.add_child(body)
	_world.objects[id] = {"id": id, "type": type, "name": title, "description": description, "position": node.global_position, "node": node}


func _ground(p: Vector2) -> Vector3:
	return Vector3(p.x, float(_world.sample_height(p.x, p.y)), p.y)


func _safe_ground(p: Vector3) -> Vector3:
	var start := Vector2(p.x, p.z)
	if _nav.is_walkable(start):
		return _ground(start)
	for radius in range(1, 13):
		for i in range(12):
			var q := start + Vector2.from_angle(i * TAU / 12.0) * radius
			if _nav.is_walkable(q):
				return _ground(q)
	return _ground(start)


func _actor(role: String) -> Node3D:
	return _brother if role == "brother" else _sister


func _boarding_point(role: String) -> Vector3:
	var side := -1.0 if role == "brother" else 1.0
	var p := _cart.to_global(Vector3(side * 1.8, 0, -0.4))
	if _requested_mode == "hand" and role == "brother":
		p = _cart.to_global(Vector3(0, 0, 2.0))
	return _safe_ground(p)


func travel_to(target: Vector3) -> bool:
	if mode == "hand":
		return manual_target(target)
	return travel_to_animal(target)


func travel_to_animal(target: Vector3) -> bool:
	if not animal_available or float(animal_stats.health) <= 0.0:
		notice.emit("Зорька сейчас не может тянуть повозку.")
		return false
	if minf(float(animal_stats.stamina), minf(float(animal_stats.hunger), float(animal_stats.thirst))) < 8.0:
		notice.emit("Сначала напоите и накормите Зорьку, дайте ей отдохнуть.")
		return false
	return _plan(target, "animal")


func manual_target(target: Vector3) -> bool:
	return _plan(target, "hand")


func pull_by_brother() -> bool:
	_has_destination = false
	return _start_boarding("hand")


func _plan(target: Vector3, drive_mode: String) -> bool:
	if not is_instance_valid(_cart):
		return false
	var route: PackedVector3Array = _wagon_nav.path(_cart.global_position, target)
	if route.is_empty():
		notice.emit("Повозке здесь не пройти. Выберите точку на дороге.")
		return false
	_destination = route[-1]
	_has_destination = true
	_route = route
	_route_index = 0
	if mode == drive_mode and _everyone_aboard():
		status_changed.emit()
		return true
	return _start_boarding(drive_mode)


func _start_boarding(drive_mode: String) -> bool:
	if not is_instance_valid(_cart):
		return false
	if (mode != "boarding" and mode != "idle") or (mode == "boarding" and _requested_mode != drive_mode):
		_release_people()
	_requested_mode = drive_mode
	mode = "boarding"
	_manual_attached = false
	_boarding_elapsed = 0.0
	var success := true
	for role in ["brother", "sister"]:
		if passengers.has(role):
			continue
		var human := _actor(role)
		human.set_hidden_in_cover(false)
		human.stop_moving()
		human.set_physics_process(true)
		if not human.navigate_to(_boarding_point(role)):
			success = false
	if not success:
		disembark()
		notice.emit("Не удалось подойти к повозке. Освободите проход.")
		return false
	notice.emit("Семья подходит к повозке." if drive_mode == "animal" else "Брат берётся за оглобли, сестра устраивается в повозке.")
	status_changed.emit()
	return true


func _everyone_aboard() -> bool:
	return passengers.has("sister") and (passengers.has("brother") or _manual_attached)


func _pose(human: Node3D, clip: String) -> void:
	var actor_id := human.get_instance_id()
	if _human_poses.get(actor_id, "") == clip:
		return
	_human_poses[actor_id] = clip
	human.play_action(clip)
	for node: Node in human.find_children("*", "AnimationPlayer", true, false):
		var player := node as AnimationPlayer
		for key in player.get_animation_list():
			if String(key).ends_with(clip):
				player.get_animation(key).loop_mode = Animation.LOOP_LINEAR
				player.play(key, 0.2)
				break


func _board(role: String) -> void:
	var human := _actor(role)
	human.stop_moving()
	human.set_physics_process(false)
	if role == "brother" and _requested_mode == "hand":
		_manual_attached = true
		_pose(human, "Walking_A")
	else:
		if not passengers.has(role):
			passengers.append(role)
		_pose(human, "Lie_Idle" if role == "sister" and is_night() else "Sit_Chair_Idle")
	status_changed.emit()


func _position_people() -> void:
	for role in passengers:
		var human := _actor(role)
		var seat := Vector3(-0.42, 0.88, 0.30) if role == "brother" else Vector3(0.42, 0.88, -0.45)
		if _sleeping and role == "sister":
			seat = Vector3(0.25, 0.91, -0.58)
		human.global_transform = _cart.global_transform * Transform3D(Basis.IDENTITY, seat)
		var model := human.get("_model") as Node3D
		if model:
			model.rotation = Vector3.ZERO
	if _manual_attached:
		_brother.global_position = _ground(Vector2(_cart.to_global(Vector3(0, 0, 2.0)).x, _cart.to_global(Vector3(0, 0, 2.0)).z))
		_brother.global_rotation = Vector3(0, _heading, 0)
		var model := _brother.get("_model") as Node3D
		if model:
			model.rotation = Vector3(0, 0, 0)
		_pose(_brother, "Walking_A" if _moving else "Idle")


func is_passenger(role: String) -> bool:
	return passengers.has(role)


func is_controlled(role: String) -> bool:
	return passengers.has(role) or (role == "brother" and _manual_attached)


func is_travelling() -> bool:
	return mode == "boarding" or (_has_destination and _route_index < _route.size())


func get_cart_position() -> Vector3:
	return _cart.global_position if is_instance_valid(_cart) else Vector3.ZERO


func get_animal_position() -> Vector3:
	return _horse.global_position if is_instance_valid(_horse) else Vector3.ZERO


func stop() -> void:
	_has_destination = false
	_route.clear()
	_route_index = 0
	_moving = false
	if mode == "boarding":
		disembark()
	status_changed.emit()


func _release_people() -> void:
	var roles: Array[String] = passengers.duplicate()
	if _manual_attached and not roles.has("brother"):
		roles.append("brother")
	for role in roles:
		var human := _actor(role)
		_human_poses.erase(human.get_instance_id())
		var side := -1.0 if role == "brother" else 1.0
		human.global_position = _safe_ground(_cart.to_global(Vector3(side * 2.0, 0, -0.5)))
		human.global_rotation = Vector3.ZERO
		human.stop_moving()
		human.play_action("idle")
		human.set_physics_process(true)
	passengers.clear()
	_manual_attached = false


func disembark() -> void:
	_has_destination = false
	_route.clear()
	_route_index = 0
	_moving = false
	for human: Node3D in [_brother, _sister]:
		human.stop_moving()
	_release_people()
	mode = "idle"
	status_changed.emit()


func feed(item: String) -> bool:
	var amount := {"hay": 42.0, "carrot": 25.0, "berry": 10.0}
	if not amount.has(item):
		notice.emit("Зорьке подходят сено, морковь и ягоды.")
		return false
	if float(animal_stats.hunger) >= 99.0:
		notice.emit("Зорька уже сыта.")
		return false
	animal_stats.hunger = minf(100.0, float(animal_stats.hunger) + float(amount[item]))
	animal_stats.health = minf(100.0, float(animal_stats.health) + 3.0)
	_eating_left = 3.0
	status_changed.emit()
	return true


func water() -> bool:
	if float(animal_stats.thirst) >= 99.0:
		notice.emit("Зорька уже напилась.")
		return false
	animal_stats.thirst = minf(100.0, float(animal_stats.thirst) + 45.0)
	_eating_left = 2.5
	status_changed.emit()
	return true


func _process(delta: float) -> void:
	if not is_instance_valid(_cart):
		return
	advance_time(delta)
	_moving = false
	if mode == "boarding":
		_boarding_elapsed += delta
		for role in ["brother", "sister"]:
			if is_controlled(role):
				continue
			var human := _actor(role)
			if Vector2(human.global_position.x, human.global_position.z).distance_to(Vector2(_boarding_point(role).x, _boarding_point(role).z)) < 1.4:
				_board(role)
			elif not human.is_moving():
				if not human.navigate_to(_boarding_point(role)):
					disembark()
					notice.emit("Не удалось добраться до повозки. Выберите место с открытым проходом.")
					return
		if _everyone_aboard() and _horse.global_position.distance_to(_animal_target()) < 0.4:
			mode = _requested_mode
			status_changed.emit()
		elif _boarding_elapsed > 900.0:
			disembark()
			notice.emit("Посадка прервана: к повозке не удалось подойти.")
	if mode in ["animal", "hand"] and _has_destination:
		_move_cart(delta)
	_update_animal(delta)
	_position_people()
	_tick -= delta
	if _tick <= 0.0:
		_tick = 0.3
		_update_objects()


func _move_cart(delta: float) -> void:
	if mode == "animal" and (not animal_available or float(animal_stats.health) <= 0.0):
		stop()
		notice.emit("Зорька больше не может тянуть. Осмотрите её или ведите повозку вручную.")
		return
	if mode == "animal" and minf(float(animal_stats.stamina), minf(float(animal_stats.hunger), float(animal_stats.thirst))) <= 2.0:
		stop()
		notice.emit("Зорька остановилась. Нужны вода, корм и отдых.")
		return
	if _route_index >= _route.size():
		_has_destination = false
		arrived.emit()
		status_changed.emit()
		return
	var target := _route[_route_index]
	var flat := Vector3(target.x - _cart.global_position.x, 0, target.z - _cart.global_position.z)
	if flat.length() < 0.25:
		_route_index += 1
		return
	var direction := flat.normalized()
	var ahead := _ground(Vector2(_cart.global_position.x + direction.x * 3, _cart.global_position.z + direction.z * 3))
	var grade := absf(ahead.y - _cart.global_position.y) / 3.0
	var base_speed := minf(3.0, float(_brother.move_speed) * 0.5) if mode == "hand" else 11.0
	var condition := minf(float(animal_stats.health), minf(float(animal_stats.stamina), float(animal_stats.thirst)))
	var need_factor := 1.0 if mode == "hand" else clampf(condition / 30.0, 0.25, 1.0)
	var speed := base_speed * need_factor / (1.0 + grade * 2.5)
	var distance := minf(flat.length(), speed * delta)
	var point := _cart.global_position + direction * distance
	if not _wagon_nav.is_walkable(Vector2(point.x, point.z)):
		stop()
		notice.emit("Дорога для повозки перекрыта. Выберите другую точку.")
		return
	_cart.global_position = _ground(Vector2(point.x, point.z))
	_heading = lerp_angle(_heading, atan2(direction.x, direction.z), minf(1.0, delta * 4.0))
	var behind := _ground(Vector2(point.x - direction.x * 1.0, point.z - direction.z * 1.0))
	var front := _ground(Vector2(point.x + direction.x * 1.0, point.z + direction.z * 1.0))
	_cart.rotation = Vector3(-atan2(front.y - behind.y, 2.0), _heading, 0)
	_wheel_angle += distance / WHEEL_RADIUS
	for wheel in _wheels:
		wheel.rotation.x = _wheel_angle
	_moving = true


func _update_animal(delta: float) -> void:
	_eating_left = maxf(0.0, _eating_left - delta)
	var working := _moving and mode == "animal"
	animal_stats.hunger = maxf(0.0, float(animal_stats.hunger) - delta * (0.030 if working else 0.010))
	animal_stats.thirst = maxf(0.0, float(animal_stats.thirst) - delta * (0.045 if working else 0.016))
	animal_stats.stamina = clampf(float(animal_stats.stamina) + delta * (-0.12 if working else 0.22), 0.0, 100.0)
	if minf(float(animal_stats.hunger), float(animal_stats.thirst)) <= 0.0:
		animal_stats.health = maxf(1.0, float(animal_stats.health) - delta * 0.015)
	var harnessed := (mode != "hand" and (mode != "boarding" or _requested_mode != "hand"))
	var desired := _animal_target()
	var old := _horse.global_position
	var step := 12.0 * delta if _moving else 3.2 * delta
	_horse.global_position = old.move_toward(desired, step)
	_horse.global_position.y = float(_world.sample_height(_horse.global_position.x, _horse.global_position.z))
	var direction := desired - old
	var animal_heading := atan2(direction.x, direction.z) if direction.length() > 0.5 and not _moving else _heading
	_horse.rotation.y = lerp_angle(_horse.rotation.y, animal_heading, minf(1, delta * 8))
	_harness.visible = harnessed
	_horse.visible = animal_available
	var moving_horse := old.distance_to(_horse.global_position) > 0.005
	var clip := "Gallop" if working else ("Walk" if moving_horse else ("Eating" if _eating_left > 0 else "Idle_Headlow" if is_night() else "Idle"))
	_play_animal(clip)
	animal_stats["status"] = "В пути" if working else ("Идёт рядом" if moving_horse else "Отдыхает")
	animal_stats["food_description"] = "Сено · морковь · ягоды"
	var sleep_now := is_night()
	if sleep_now != _sleeping:
		_sleeping = sleep_now
		if passengers.has("sister"):
			_pose(_sister, "Lie_Idle" if _sleeping else "Sit_Chair_Idle")
	_animal_label.text = "%s · %s" % [str(animal_stats.name), str(animal_stats.status)]


func _animal_target() -> Vector3:
	var hand_mode := mode == "hand" or (mode == "boarding" and _requested_mode == "hand")
	var relative := Vector3(2.8, 0, -0.7) if hand_mode else Vector3(0, 0, 3.7)
	var point := _cart.to_global(relative)
	return _ground(Vector2(point.x, point.z))


func _play_animal(clip: String) -> void:
	if not _horse_animation or not _horse_clips.has(clip):
		return
	var key: String = _horse_clips[clip]
	if String(_horse_animation.current_animation) != key:
		_horse_animation.play(key, 0.18)


func _update_objects() -> void:
	for id in ["wagon", "pack_animal"]:
		var obj: Dictionary = _world.objects[id]
		var node: Node3D = obj.node
		obj.position = node.global_position
		obj.approach = _safe_ground(node.to_global(Vector3(1.8 if id == "wagon" else 1.0, 0, 0)))


func advance_time(delta: float) -> void:
	day_time += delta * MINUTES_PER_SECOND
	while day_time >= 1440.0:
		day_time -= 1440.0
		day_number += 1
	_clock_tick -= delta
	if _clock_tick <= 0.0:
		_clock_tick = 0.5
		_update_light()


func get_clock_text() -> String:
	var minute := floori(day_time)
	return "День %d · %02d:%02d" % [day_number, minute / 60, minute % 60]


func is_night() -> bool:
	return day_time < 360.0 or day_time >= 1200.0


func _update_light() -> void:
	var daylight := clampf(sin((day_time - 360.0) / 1440.0 * TAU) * 2.2, 0.0, 1.0)
	if is_instance_valid(_sun):
		_sun.rotation_degrees = Vector3(-maxf(12.0, sin((day_time - 360.0) / 1440.0 * TAU) * 70.0), -35.0 + day_time * 0.08, 0)
		_sun.light_energy = lerpf(0.14, 0.92, daylight)
		_sun.light_color = Color("#90acd9").lerp(Color("#fff0cc"), daylight)
	if _environment:
		_environment.ambient_light_energy = lerpf(0.16, 0.34, daylight)
		_environment.ambient_light_color = Color("#8198ba").lerp(Color("#c6d7ca"), daylight)
		_environment.fog_light_color = Color("#3f516c").lerp(Color("#a6bda7"), daylight)
		var sky := _environment.sky.sky_material as ProceduralSkyMaterial if _environment.sky else null
		if sky:
			sky.sky_top_color = Color("#071326").lerp(Color("#6e9ba9"), daylight)
			sky.sky_horizon_color = Color("#28384d").lerp(Color("#c6d3b4"), daylight)
			sky.ground_horizon_color = sky.sky_horizon_color
	for lamp in _lamps:
		lamp.visible = is_night()
	if _world.has_method("set_night"):
		_world.set_night(is_night())


func snapshot() -> Dictionary:
	var p := get_cart_position()
	var horse := get_animal_position()
	return {"storage": storage.duplicate(true), "animal_stats": animal_stats.duplicate(true), "animal_available": animal_available,
		"mode": mode, "requested_mode": _requested_mode, "passengers": passengers.duplicate(), "manual_attached": _manual_attached,
		"position": [p.x, p.y, p.z], "animal_position": [horse.x, horse.y, horse.z], "heading": _heading,
		"target": [_destination.x, _destination.y, _destination.z], "has_destination": _has_destination,
		"day_time": day_time, "day_number": day_number, "wheel_angle": _wheel_angle}


func restore(data: Dictionary) -> void:
	if not is_instance_valid(_cart):
		_pending_restore = data.duplicate(true)
		return
	disembark()
	storage = data.get("storage", {}).duplicate(true)
	var stats: Dictionary = data.get("animal_stats", {})
	for key in ["health", "stamina", "hunger", "thirst"]:
		animal_stats[key] = clampf(float(stats.get(key, 100.0)), 0.0, 100.0)
	animal_stats.name = str(stats.get("name", "Зорька"))
	animal_available = bool(data.get("animal_available", true))
	day_time = fposmod(float(data.get("day_time", 480.0)), 1440.0)
	day_number = maxi(1, int(data.get("day_number", 1)))
	var position_data: Array = data.get("position", [4008, 0, 4412])
	_cart.global_position = _ground(Vector2(float(position_data[0]), float(position_data[2])))
	_heading = float(data.get("heading", 0))
	_cart.rotation = Vector3(0, _heading, 0)
	var animal_position: Array = data.get("animal_position", position_data)
	_horse.global_position = _ground(Vector2(float(animal_position[0]), float(animal_position[2])))
	_requested_mode = str(data.get("requested_mode", "animal"))
	mode = str(data.get("mode", "idle"))
	_manual_attached = false
	for role in data.get("passengers", []):
		if role in ["brother", "sister"]:
			_board(role)
	if bool(data.get("manual_attached", false)):
		_requested_mode = "hand"
		_board("brother")
	_wheel_angle = float(data.get("wheel_angle", 0))
	var target: Array = data.get("target", position_data)
	_destination = Vector3(float(target[0]), float(target[1]), float(target[2]))
	_has_destination = bool(data.get("has_destination", false))
	_route_index = 0
	_route = _wagon_nav.path(_cart.global_position, _destination) if _has_destination else PackedVector3Array()
	if _has_destination and _route.is_empty():
		_has_destination = false
	if mode == "boarding":
		_boarding_elapsed = 0.0
		for role in ["brother", "sister"]:
			if not is_controlled(role):
				_actor(role).navigate_to(_boarding_point(role))
	_position_people()
	_update_objects()
	_update_light()
	status_changed.emit()


func _exit_tree() -> void:
	for human: Node3D in [_brother, _sister]:
		if is_instance_valid(human):
			human.set_physics_process(true)
