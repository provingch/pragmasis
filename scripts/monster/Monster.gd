extends CharacterBody3D
class_name Monster

## First-delivery AI: random spawn timer, then chases the player in a
## straight line until it catches them. No line-of-sight/hiding logic yet.

enum State { IDLE, CHASE }

const CHASE_SPEED := 5.0
const MIN_SPAWN_DELAY := 45.0
const MAX_SPAWN_DELAY := 90.0
const SPAWN_DISTANCE := 20.0

var state: State = State.IDLE
var _player: Node3D

@onready var catch_area: Area3D = $CatchArea

func _ready() -> void:
	visible = false
	set_physics_process(false)
	_player = get_tree().get_first_node_in_group("player") as Node3D
	catch_area.body_entered.connect(_on_catch_area_body_entered)
	_schedule_next_spawn()

func _schedule_next_spawn() -> void:
	var delay := randf_range(MIN_SPAWN_DELAY, MAX_SPAWN_DELAY)
	get_tree().create_timer(delay).timeout.connect(_activate)

func _activate() -> void:
	if GameManager.is_game_over or _player == null:
		return
	global_position = _pick_spawn_position()
	visible = true
	state = State.CHASE
	set_physics_process(true)
	AudioManager.start_chase()

func _pick_spawn_position() -> Vector3:
	var away := Vector2.from_angle(randf_range(0.0, TAU))
	return _player.global_position + Vector3(away.x, 0.0, away.y) * SPAWN_DISTANCE

func _physics_process(_delta: float) -> void:
	if state != State.CHASE:
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	velocity = to_player.normalized() * CHASE_SPEED
	move_and_slide()

func _on_catch_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player"):
		GameManager.trigger_game_over()
