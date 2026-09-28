extends CharacterBody3D
class_name Monster

## 4D entity. Its real position is (global_position, entity_w); what the
## player sees is a tesseract projection: the closer entity_w is to the
## player's w, the more "coherent" (solid, red, faster) it looks; far away
## it's a thin glitching ghost tinted with its own layer's color. Being 4D,
## 3D walls don't stop it. Hunts for CHASE_TIME, then folds away and waits
## again. Only catches the player on the same w.
##
## Each manifestation is foreshadowed OMEN_TIME ahead (the room's light
## fails, a distant sound, static on the scanner). A player hiding while it
## watches (same layer, in range, line of sight) is dragged out; unseen,
## it loses them and folds away early. After the sequence clock runs out
## (collapse) it hunts forever, faster, and follows the player across
## layers.

enum State { IDLE, CHASE }

## Metres per second at coherence 1. Beats a sprint-spamming player's
## sustained pace (~4.9 m/s, sprinting to just short of empty and walking
## it back) but not a fresh sprint (7.0): running buys time, not escape.
const CHASE_SPEED := 5.8
const MIN_SPAWN_DELAY := 20.0
const MAX_SPAWN_DELAY := 45.0
const SPAWN_DISTANCE := 16.0
const CHASE_TIME := 22.0
const OMEN_TIME := 4.0
const SEE_DISTANCE := 16.0
## After losing the player to a hideout it lingers this long, then folds.
const LOSE_TIME := 1.5
const COLLAPSE_SPEED := 1.2
## In collapse, seconds before it crosses to the player's new layer.
const FOLLOW_DELAY := 3.0
const PHASE_SPIN_SPEED := 1.5
const HUNT_COLOR := Color(1.0, 0.12, 0.1)

var state: State = State.IDLE
var entity_w := 0
## Seconds of omen still running (scanner static reads it).
var omen_left := 0.0
var _spawn_progress := 0.0
var _omened := false
var _chase_left := 0.0
var _follow_t := 0.0
var _phase_angle := 0.0
var _player: Player

@onready var catch_area: Area3D = $CatchArea
@onready var tesseract: Tesseract = $Tesseract
@onready var core: MeshInstance3D = $Core
@onready var glow: OmniLight3D = $Glow

func _ready() -> void:
	add_to_group("monster")
	visible = false
	_player = get_tree().get_first_node_in_group("player") as Player
	catch_area.body_entered.connect(_on_catch_area_body_entered)
	GameManager.collapsed.connect(_on_collapse)
	GameManager.sequence_completed.connect(func(_done: int) -> void:
		if state == State.CHASE:
			_deactivate()
		else:
			_begin_idle())
	_begin_idle()

## Still visible while folding away, but no longer a threat.
func is_hunting() -> bool:
	return state == State.CHASE

## 1.0 on the player's layer, halving per layer away: a neighbour stays a
## real threat (0.5, as it was with 3 layers) without matching your own,
## and far layers fade out instead of hitting a hard zero.
func coherence() -> float:
	return pow(0.5, absi(entity_w - DimensionState.player_w))

## Delay under current conditions: nearer in w and a more hostile world
## (the one the player is in right now) both shorten it.
func spawn_delay() -> float:
	var threat: float = DimensionState.LAYERS[DimensionState.player_w].threat
	return lerpf(MAX_SPAWN_DELAY, MIN_SPAWN_DELAY, coherence()) / threat / GameManager.threat_scale()

## The player slipped into a hideout: true if it saw them do it.
func saw_hiding() -> bool:
	if state != State.CHASE or entity_w != DimensionState.player_w:
		return false
	var eye := global_position + Vector3(0, 0.9, 0)
	var target := _player.global_position + Vector3(0, 0.6, 0)
	if eye.distance_to(target) > SEE_DISTANCE:
		return false
	var ray := PhysicsRayQueryParameters3D.create(eye, target, 1) # world geometry only
	return get_world_3d().direct_space_state.intersect_ray(ray).is_empty()

## Unseen hiding: it gives up soon (in collapse it only drifts off).
func lose_track() -> void:
	if state == State.CHASE and not GameManager.is_collapsed:
		_chase_left = minf(_chase_left, LOSE_TIME)

# Single entry to IDLE, so "not hunting => can't catch" holds by construction.
func _begin_idle() -> void:
	state = State.IDLE
	set_physics_process(false)
	catch_area.monitoring = false
	entity_w = randi_range(DimensionState.W_MIN, DimensionState.W_MAX)
	_spawn_progress = 0.0
	_omened = false

func _activate() -> void:
	_spawn_progress = 0.0
	if GameManager.is_game_over or _player == null:
		return
	global_position = _pick_spawn_position()
	if GameManager.is_collapsed:
		entity_w = DimensionState.player_w
	# Its light's omni shadow re-renders the scene 6x: only if the preset has shadows.
	glow.shadow_enabled = Settings.shadow_radius >= 0
	visible = true
	state = State.CHASE
	_chase_left = CHASE_TIME
	set_physics_process(true)
	catch_area.monitoring = true
	AudioManager.start_chase()
	AudioManager.play_sfx(&"monster")
	# Manifest: unfolds out of nothing.
	tesseract.scale = Vector3.ZERO
	create_tween().tween_property(tesseract, "scale", Vector3.ONE, 1.2) \
		.set_trans(Tween.TRANS_ELASTIC).set_ease(Tween.EASE_OUT)

func _deactivate() -> void:
	AudioManager.stop_chase()
	var tw := create_tween()
	tw.tween_property(tesseract, "scale", Vector3.ZERO, 0.4).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	tw.tween_callback(hide)
	_begin_idle()

func _pick_spawn_position() -> Vector3:
	var away := Vector2.from_angle(randf_range(0.0, TAU))
	return _player.global_position + Vector3(away.x, 0.0, away.y) * SPAWN_DISTANCE

func _process(delta: float) -> void:
	omen_left = maxf(omen_left - delta, 0.0)
	if state == State.IDLE:
		# Integrated every frame, so walking into a harsher world speeds up
		# the next manifestation immediately, not just the one after.
		var delay := spawn_delay()
		_spawn_progress += delta / delay
		if not _omened and (1.0 - _spawn_progress) * delay <= OMEN_TIME:
			_omen()
		if _spawn_progress >= 1.0:
			_activate()
		return

	if GameManager.is_collapsed:
		# Layers don't shake it off: it crosses after you.
		_follow_t = _follow_t + delta if entity_w != DimensionState.player_w else 0.0
		if _follow_t >= FOLLOW_DELAY:
			entity_w = DimensionState.player_w
	else:
		_chase_left -= delta
		if _chase_left <= 0.0:
			_deactivate()
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
	var world_speed: float = DimensionState.LAYERS[DimensionState.player_w].entity_speed
	var speed := CHASE_SPEED * world_speed * GameManager.speed_scale() * lerpf(0.4, 1.0, coherence())
	if GameManager.is_collapsed:
		speed *= COLLAPSE_SPEED
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	# Lost them in a hideout: drifts away, searching.
	velocity = to_player.normalized() * (speed if not _player.hidden else -speed * 0.3)
	move_and_slide()

func _omen() -> void:
	_omened = true
	omen_left = OMEN_TIME
	AudioManager.play_sfx(&"omen")
	var room := RoomGenerator.room_at(_player.global_position, DimensionState.player_w)
	if room:
		room.disturb(OMEN_TIME)

func _on_collapse() -> void:
	if state == State.IDLE:
		_activate()

func _on_catch_area_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and entity_w == DimensionState.player_w:
		GameManager.trigger_game_over()
