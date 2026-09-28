extends CharacterBody3D
class_name Player

const WALK_SPEED := 4.0
const RUN_SPEED := 7.5
const MOUSE_SENSITIVITY := 0.0025
const GRAVITY := 9.8
const BOB_FREQ := 1.6
const BOB_AMP := 0.07
const WALK_FOV := 75.0
const RUN_FOV := 86.0

# Camera feel: two underdamped springs (they overshoot, then settle), kept
# small on purpose — tension, not nausea.
## Dutch roll per rad/s of mouse yaw; leans into the turn.
const ROLL_PER_TURN := 0.012
const MAX_ROLL := deg_to_rad(4.0)
const ROLL_STIFF := 140.0
const ROLL_DAMP := 9.0
## Camera lag per m/s of sudden velocity change (start, stop, reverse, strafe flip).
const JERK_KICK := 0.08
const JERK_TILT := 0.5 # rad of tilt per metre of lag
const JERK_STIFF := 180.0
const JERK_DAMP := 11.0

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var _pitch := 0.0
var _bob_t := 0.0
var _bob_amount := 0.0
var _yaw_accum := 0.0
var _roll := 0.0
var _roll_vel := 0.0
var _jerk := Vector3.ZERO
var _jerk_vel := Vector3.ZERO
var _prev_vel := Vector3.ZERO

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var yaw: float = event.relative.x * MOUSE_SENSITIVITY
		rotate_y(-yaw)
		_yaw_accum += yaw
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-80.0), deg_to_rad(80.0))
		head.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var speed := RUN_SPEED if Input.is_action_pressed("run") else WALK_SPEED

	if direction:
		velocity.x = direction.x * speed
		velocity.z = direction.z * speed
	else:
		velocity.x = move_toward(velocity.x, 0.0, speed)
		velocity.z = move_toward(velocity.z, 0.0, speed)

	move_and_slide()

	# Inertia: the camera lags behind any sudden horizontal velocity change.
	var dv := velocity - _prev_vel
	dv.y = 0.0
	_prev_vel = velocity
	_jerk_vel -= (global_basis.inverse() * dv) * JERK_KICK

	var hspeed := Vector2(velocity.x, velocity.z).length()
	_bob_amount = clampf(hspeed / RUN_SPEED, 0.0, 1.0)
	if is_on_floor() and hspeed > 0.1:
		_bob_t += delta * hspeed * BOB_FREQ
	var running := Input.is_action_pressed("run") and hspeed > 0.1
	camera.fov = lerpf(camera.fov, RUN_FOV if running else WALK_FOV, delta * 6.0)

# Springs run per rendered frame so they stay smooth above 60 fps.
func _process(delta: float) -> void:
	var target_roll := clampf(-_yaw_accum / delta * ROLL_PER_TURN, -MAX_ROLL, MAX_ROLL)
	_yaw_accum = 0.0
	_roll_vel += ((target_roll - _roll) * ROLL_STIFF - _roll_vel * ROLL_DAMP) * delta
	_roll += _roll_vel * delta

	_jerk_vel += (-_jerk * JERK_STIFF - _jerk_vel * JERK_DAMP) * delta
	_jerk += _jerk_vel * delta

	var bob := Vector3(cos(_bob_t * 0.5) * BOB_AMP * 0.5, sin(_bob_t) * BOB_AMP, 0.0) * _bob_amount
	camera.position = bob + _jerk
	# Lagging back pitches up, lurching forward pitches down; strafe lag rolls.
	camera.rotation = Vector3(_jerk.z * JERK_TILT, 0.0, _roll - _jerk.x * JERK_TILT)
