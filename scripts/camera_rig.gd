extends Node3D

var camera: Camera3D
var follow_target: Node3D
var _last_target: Node3D
var _focus := Vector3.ZERO
var _yaw := deg_to_rad(35.0)
var _pitch := deg_to_rad(54.0)
var _zoom := 45.0
var _rotating := false
var _initialized := false
var _panning := false
var controls_enabled := true
var _view_yaw := _yaw
var _view_pitch := _pitch


func _ready() -> void:
	camera = Camera3D.new()
	camera.name = "Камера"
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = _zoom
	camera.near = 0.2
	camera.far = 6000.0
	camera.current = true
	add_child(camera)
	_update_camera()


func focus_on(actor: Node3D) -> void:
	follow_target = actor
	_last_target = actor
	if is_instance_valid(actor):
		focus_point(actor.global_position + Vector3.UP)
		follow_target = actor


func select_target(actor: Node3D) -> void:
	_last_target = actor
	if is_following():
		focus_on(actor)


func is_following() -> bool:
	return is_instance_valid(follow_target)


func set_controls_enabled(value: bool) -> void:
	controls_enabled = value
	if not value:
		_rotating = false
		_panning = false


func focus_point(p: Vector3) -> void:
	follow_target = null
	_focus = p
	if not _initialized:
		global_position = p
		_initialized = true


func _unhandled_input(event: InputEvent) -> void:
	if not controls_enabled:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			_rotating = event.pressed
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			_panning = event.pressed
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom = maxf(14.0, _zoom / 1.12)
			get_viewport().set_input_as_handled()
		elif event.pressed and event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom = minf(200.0, _zoom * 1.12)
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _rotating:
		_yaw -= event.relative.x * 0.006
		_pitch = clampf(_pitch + event.relative.y * 0.004, deg_to_rad(28.0), deg_to_rad(78.0))
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _panning:
		follow_target = null
		var metres_per_pixel := camera.size / maxf(1.0, get_viewport().get_visible_rect().size.y)
		var right := Vector3(cos(_view_yaw), 0.0, -sin(_view_yaw))
		var backward := Vector3(sin(_view_yaw), 0.0, cos(_view_yaw))
		_focus -= (right * event.relative.x + backward * event.relative.y / maxf(0.35, sin(_view_pitch))) * metres_per_pixel
		get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_SPACE:
		if is_instance_valid(_last_target):
			focus_on(_last_target)
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if _rotating and not Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE):
		_rotating = false
	if _panning and not Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
		_panning = false
	var focused := get_viewport().gui_get_focus_owner()
	var typing := focused is LineEdit or focused is TextEdit
	if not typing and controls_enabled:
		_yaw += (float(Input.is_physical_key_pressed(KEY_Q)) - float(Input.is_physical_key_pressed(KEY_E))) * delta
		var pan := Vector2(
			float(Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT)) - float(Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT)),
			float(Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN)) - float(Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP)))
		if pan.length_squared() > 0.0:
			follow_target = null
			var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
			var backward := Vector3(sin(_yaw), 0.0, cos(_yaw))
			_focus += (right * pan.x + backward * pan.y).normalized() * delta * _zoom * 0.7
	if is_instance_valid(follow_target):
		_focus = follow_target.global_position + Vector3.UP
	global_position = global_position.lerp(_focus, 1.0 - exp(-delta * 8.0))
	if camera:
		camera.size = lerpf(camera.size, _zoom, 1.0 - exp(-delta * 12.0))
		_view_yaw = lerp_angle(_view_yaw, _yaw, 1.0 - exp(-delta * 16.0))
		_view_pitch = lerpf(_view_pitch, _pitch, 1.0 - exp(-delta * 16.0))
		_update_camera()


func _update_camera() -> void:
	var distance := maxf(60.0, _zoom * 1.7)
	camera.position = Vector3(sin(_view_yaw) * cos(_view_pitch), sin(_view_pitch), cos(_view_yaw) * cos(_view_pitch)) * distance
	camera.look_at(global_position, Vector3.UP)
