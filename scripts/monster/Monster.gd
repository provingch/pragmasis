extends CharacterBody3D
class_name Monster

## 4D entity. Its real position is (global_position, entity_w); what the
## player sees is a tesseract projection: the closer entity_w is to the
## player's w, the more "coherent" (solid, red, faster) it looks; far away
## it's a thin glitching ghost tinted with its own layer's color. Spawns
## more often when near in w. Only catches the player on the same w.

enum State { IDLE, CHASE }

const CHASE_SPEED := 5.0
const MIN_SPAWN_DELAY := 45.0
const MAX_SPAWN_DELAY := 90.0
const SPAWN_DISTANCE := 20.0
const PHASE_SPIN_SPEED := 1.5
const HUNT_COLOR := Color(1.0, 0.12, 0.1)

var state: State = State.IDLE
var entity_w := 0
var _phase_angle := 0.0
var _player: Node3D

@onready var catch_area: Area3D = $CatchArea
@onready var tesseract: Tesseract = $Tesseract
@onready var core: MeshInstance3D = $Core
@onready var glow: OmniLight3D = $Glow

func _ready() -> void:
	add_to_group("monster")
	visible = false
	set_physics_process(false)
	catch_area.monitoring = false
	_player = get_tree().get_first_node_in_group("player") as Node3D
	catch_area.body_entered.connect(_on_catch_area_body_entered)
	_schedule_next_spawn()

## 1.0 when on the player's layer, 0.0 at max w distance.
func coherence() -> float:
	return 1.0 - float(absi(entity_w - DimensionState.player_w)) / float(DimensionState.W_SPAN)

func spawn_delay() -> float:
	# ponytail: linear in w-distance; reshape the curve if tuning needs it
	return lerpf(MAX_SPAWN_DELAY, MIN_SPAWN_DELAY, coherence())

func _schedule_next_spawn() -> void:
	entity_w = randi_range(DimensionState.W_MIN, DimensionState.W_MAX)
	get_tree().create_timer(spawn_delay()).timeout.connect(_activate)

func _activate() -> void:
	if GameManager.is_game_over or _player == null:
		return
	global_position = _pick_spawn_position()
	visible = true
	state = State.CHASE
	set_physics_process(true)
	catch_area.monitoring = true
	AudioManager.start_chase()
	# Manifest: unfolds out of nothing.
	tesseract.scale = Vector3.ZERO
	create_tween().tween_property(tesseract, "scale", Vector3.ONE, 1.2) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _pick_spawn_position() -> Vector3:
	var away := Vector2.from_angle(randf_range(0.0, TAU))
	return _player.global_position + Vector3(away.x, 0.0, away.y) * SPAWN_DISTANCE

func _process(delta: float) -> void:
	if not visible:
		return
	var c := coherence()
	# Spins faster when it's closing in on your layer.
	_phase_angle += delta * PHASE_SPIN_SPEED * lerpf(0.6, 1.4, c)
	var col: Color = (DimensionState.LAYERS[entity_w].trim as Color).lerp(HUNT_COLOR, c)
	tesseract.phase = _phase_angle
	tesseract.coherence = c
	tesseract.color = col
	core.scale = Vector3.ONE * lerpf(0.3, 1.0, c) * (0.9 + 0.1 * sin(_phase_angle * 5.0))
	glow.light_color = col
	glow.light_energy = lerpf(0.4, 3.0, c) * (0.75 + 0.25 * sin(_phase_angle * 3.0))

func _physics_process(_delta: float) -> void:
	if state != State.CHASE:
		return
	var speed := CHASE_SPEED * lerpf(0.4, 1.0, coherence()) * (0.85 + 0.15 * sin(_phase_angle))
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	velocity = to_player.normalized() * speed
	move_and_slide()

func _on_catch_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and entity_w == DimensionState.player_w:
		GameManager.trigger_game_over()
