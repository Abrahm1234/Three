extends Node3D
# RMB look. MMB pan. Wheel zoom.
# WASD move, Q/E down/up, Shift fast, Ctrl slow. Tab toggles Orbit<->Fly.

enum Mode { ORBIT, FLY }

@export var mode: Mode = Mode.ORBIT
@export var target := Vector3(8, 0, 6)
@export var distance := 24.0
@export var min_distance := 3.0
@export var max_distance := 120.0
@export var orbit_sens := 0.01
@export var pan_speed := 0.02
@export var zoom_speed := 1.0

@export var fly_speed := 8.0
@export var fly_fast_mult := 3.0
@export var fly_slow_mult := 0.35
@export var mouse_sens := 0.012

@export var focus_root_path: NodePath = NodePath("../Rooms")   # node that holds your house meshes

var yaw := -0.6
var pitch := -0.6
var looking := false

@onready var cam: Camera3D = $Camera3D

func _ready() -> void:
	_ensure_actions()
	cam.current = true
	_apply_mouse_mode()

func _input(e: InputEvent) -> void:
	if e is InputEventKey and e.pressed and not e.echo:
		if Input.is_action_just_pressed("cam_toggle_mode"):
			mode = Mode.FLY if mode == Mode.ORBIT else Mode.ORBIT
			looking = false
			_apply_mouse_mode()
		# manual recapture
		if Input.is_action_just_pressed("cam_capture"):
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

	# ensure the mouse remains captured while flying (UI may release it)
	if mode == Mode.FLY and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if Input.is_action_just_pressed("ui_cancel") and mode == Mode.FLY:
			# allow Esc to release the cursor while flying
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		if Input.is_action_just_pressed("cam_focus"):
			focus_now()
		if Input.is_action_just_pressed("cam_reset"):
			yaw = -0.6; pitch = -0.6; distance = clamp(distance, min_distance, max_distance)
			if mode == Mode.FLY:
				global_position = target - _dir_from_angles() * distance
	if e is InputEventMouseButton:
		# RMB only controls look in ORBIT. In FLY the mouse is always active.
		if e.button_index == MOUSE_BUTTON_RIGHT and mode == Mode.ORBIT:
			looking = e.pressed
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if looking else Input.MOUSE_MODE_VISIBLE
		elif mode == Mode.ORBIT and e.pressed:
			if e.button_index == MOUSE_BUTTON_WHEEL_UP:
				distance = max(min_distance, distance - zoom_speed)
			elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				distance = min(max_distance, distance + zoom_speed)
	elif e is InputEventMouseMotion:
		if mode == Mode.FLY:
			yaw -= e.relative.x * mouse_sens
			pitch = clamp(pitch - e.relative.y * mouse_sens, -1.45, 1.35)
		elif looking:
			yaw -= e.relative.x * mouse_sens
			pitch = clamp(pitch - e.relative.y * mouse_sens, -1.35, 1.35)
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_MIDDLE) and mode == Mode.ORBIT:
			var right := Vector3.RIGHT.rotated(Vector3.UP, yaw)
			var fwd := Vector3.FORWARD.rotated(Vector3.UP, yaw)
			target -= (right * e.relative.x + fwd * e.relative.y) * pan_speed

func _physics_process(dt: float) -> void:
	match mode:
		Mode.ORBIT: _orbit_step()
		Mode.FLY:   _fly_step(dt)

func _orbit_step() -> void:
	var dir := _dir_from_angles()
	var pos := target - dir * distance
	global_transform.origin = pos
	look_at(target, Vector3.UP)

func _fly_step(dt: float) -> void:
	# rotate rig by yaw/pitch
	rotation = Vector3(pitch, yaw, 0.0)
	# build movement from input
	var move := Vector3.ZERO
	if Input.is_action_pressed("cam_forward"): move -= Vector3.FORWARD
	if Input.is_action_pressed("cam_back"):    move += Vector3.FORWARD
	if Input.is_action_pressed("cam_left"):    move -= Vector3.RIGHT
	if Input.is_action_pressed("cam_right"):   move += Vector3.RIGHT
	if Input.is_action_pressed("cam_up"):      move += Vector3.UP
	if Input.is_action_pressed("cam_down"):    move -= Vector3.UP
	if move != Vector3.ZERO:
		move = move.normalized()
	var sp := fly_speed
	if Input.is_action_pressed("cam_fast"): sp *= fly_fast_mult
	if Input.is_action_pressed("cam_slow"): sp *= fly_slow_mult
	# transform local to world
	var basis := global_transform.basis
	var world_move := (basis * move) * sp * dt
	global_position += world_move

func _dir_from_angles() -> Vector3:
	return Vector3(
		cos(pitch) * sin(yaw),
		sin(pitch),
		cos(pitch) * cos(yaw)
	).normalized()

func _ensure_actions() -> void:
	_add_action_once("cam_forward",  [KEY_W])
	_add_action_once("cam_back",     [KEY_S])
	_add_action_once("cam_left",     [KEY_A])
	_add_action_once("cam_right",    [KEY_D])
	_add_action_once("cam_up",       [KEY_E])
	_add_action_once("cam_down",     [KEY_Q])
	_add_action_once("cam_fast",     [KEY_SHIFT])
	_add_action_once("cam_slow",     [KEY_CTRL])
	_add_action_once("cam_toggle_mode", [KEY_TAB])
	_add_action_once("cam_reset",    [KEY_R])
	_add_action_once("cam_focus",    [KEY_F])
	_add_action_once("cam_capture",  [KEY_C])

func _add_action_once(name: String, keys: Array) -> void:
	if InputMap.has_action(name): return
	InputMap.add_action(name)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(name, ev)

func focus_now(pad: float = 1.15) -> void:
	var root := get_node_or_null(focus_root_path) as Node3D
	var bb := _world_bounds(root)
	if bb.size == Vector3.ZERO:
		target = Vector3.ZERO
		return
	var center: Vector3 = bb.position + bb.size * 0.5
	var ext := bb.size * 0.5
	target = center

	var vfov := deg_to_rad(cam.fov)
	var hfov := 2.0 * atan(tan(vfov * 0.5) * cam.aspect)
	var need_v: float = (ext.y * pad) / max(0.001, tan(vfov * 0.5))
	var need_h: float = (max(ext.x, ext.z) * pad) / max(0.001, tan(hfov * 0.5))
	distance = clamp(max(need_v, need_h), min_distance, max_distance)

	if mode == Mode.FLY:
		global_position = target - _dir_from_angles() * distance
	else:
		_orbit_step()

func _world_bounds(root: Node3D) -> AABB:
	if root == null:
		return AABB(Vector3.ZERO, Vector3.ZERO)
	var have := false
	var minv := Vector3.INF
	var maxv := -Vector3.INF
	var stack: Array = [root]
	while not stack.is_empty():
		var n := stack.pop_back()
		if n is MeshInstance3D:
			var mi := n as MeshInstance3D
			var a := mi.get_aabb()
			var c := mi.global_transform.origin
			var half := a.size * 0.5
			var minp := c - half
			var maxp := c + half
			if not have:
				minv = minp; maxv = maxp; have = true
			else:
				minv = Vector3(min(minv.x, minp.x), min(minv.y, minp.y), min(minv.z, minp.z))
				maxv = Vector3(max(maxv.x, maxp.x), max(maxv.y, maxp.y), max(maxv.z, maxp.z))
		for ch in n.get_children():
			if ch is Node3D:
				stack.append(ch)
	return AABB(minv, maxv - minv) if have else AABB(Vector3.ZERO, Vector3.ZERO)

func _apply_mouse_mode() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if mode == Mode.FLY else Input.MOUSE_MODE_VISIBLE
