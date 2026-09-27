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

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D

var _pitch := 0.0
var _bob_t := 0.0

func _ready() -> void:
	add_to_group("player")
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * MOUSE_SENSITIVITY)
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-80.0), deg_to_rad(80.0))
		head.rotation.x = _pitch
	elif event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED else Input.MOUSE_MODE_CAPTURED

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

	var hspeed := Vector2(velocity.x, velocity.z).length()
	var amount := clampf(hspeed / RUN_SPEED, 0.0, 1.0)
	if is_on_floor() and hspeed > 0.1:
		_bob_t += delta * hspeed * BOB_FREQ
	camera.position = Vector3(cos(_bob_t * 0.5) * BOB_AMP * 0.5, sin(_bob_t) * BOB_AMP, 0.0) * amount
	var running := Input.is_action_pressed("run") and hspeed > 0.1
	camera.fov = lerpf(camera.fov, RUN_FOV if running else WALK_FOV, delta * 6.0)
