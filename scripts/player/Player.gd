extends CharacterBody3D
class_name Player

const WALK_SPEED := 3.8
const RUN_SPEED := 7.0
## Stamina runs 0..1. A full bar sprints SPRINT_TIME seconds; it refills in
## REGEN_TIME once REGEN_DELAY has passed without sprinting. Emptying it
## leaves you EXHAUST_TIME seconds at EXHAUSTED_SPEED, panting.
const SPRINT_TIME := 4.0
const REGEN_TIME := 7.0
const REGEN_DELAY := 1.0
const EXHAUST_TIME := 2.5
const EXHAUSTED_SPEED := 2.4
## Hideouts: stable this long, then unstable, then they throw you out.
const HIDE_MAX := 20.0
const HIDE_UNSTABLE := 14.0
const MOUSE_SENSITIVITY := 0.0025
const GRAVITY := 9.8
const BOB_FREQ := 1.6
const BOB_AMP := 0.07
const WALK_FOV := 75.0
const RUN_FOV := 86.0
## Foot strike = the head-bob's low point (sin(_bob_t) == -1), once per cycle.
const STEP_PHASE := PI * 1.5
## Flashlight (worlds with WorldDef.flashlight): a full battery lasts
## BATTERY_TIME seconds on; it recharges only while off, from empty in
## RECHARGE_TIME. Emptying it switches it off; F turns it back on.
const BATTERY_TIME := 50.0
const RECHARGE_TIME := 110.0
## Below this charge it starts to stutter.
const BATTERY_LOW := 0.15
const FLASH_ENERGY := 6.0

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

## Off in harnesses, so a test run never grabs the real mouse.
static var capture_mouse := true

@onready var head: Node3D = $Head
@onready var camera: Camera3D = $Head/Camera3D
@onready var steps_walk: AudioStreamPlayer = $StepsWalk
@onready var steps_run: AudioStreamPlayer = $StepsRun
@onready var breath: AudioStreamPlayer = $Breath
## Your own body: casts your shadow, shows your legs when you look down.
@onready var avatar: PlayerAvatar = $Avatar

var stamina := 1.0
var exhausted := 0.0
## Inside a hideout: frozen, looking out through its slit, undetectable.
var hidden := false
## Seconds spent in the current hideout.
var hide_t := 0.0
var _since_sprint := 0.0
var _hide_room: Room
var battery := 1.0
var flashlight_on := true
var _flash: SpotLight3D

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
	if capture_mouse:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_flash = SpotLight3D.new()
	_flash.spot_range = 16.0
	_flash.spot_angle = 26.0
	_flash.spot_attenuation = 0.5
	_flash.light_energy = FLASH_ENERGY
	_flash.light_color = Color(1.0, 0.95, 0.85)
	_flash.visible = false
	camera.add_child(_flash)
	_flash_shadow()
	Settings.changed.connect(_flash_shadow)

## Its shadow re-renders the scene once: only if the preset has shadows.
func _flash_shadow() -> void:
	_flash.shadow_enabled = Settings.shadow_radius >= 0

## The floor (the cube's y in the grid) you're on.
func floor_index() -> int:
	return RoomGenerator.cell_of(global_position).y

## How high your feet are over your cube's floor (m): up a platform or a
## spiral, down a pit (negative).
func height_in_cube() -> float:
	return global_position.y - 0.9 - floor_index() * Room.CELL_H

## Whether the world you're in hands you a flashlight.
func has_flashlight() -> bool:
	return Worlds.def(DimensionState.player_w).flashlight

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("flashlight") and has_flashlight():
		flashlight_on = not flashlight_on and battery > 0.0
	if event.is_action_pressed("interact"):
		if hidden:
			leave_hideout()
		elif hideout_in_reach():
			enter_hideout(hideout_in_reach())
	if hidden:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var yaw: float = event.relative.x * MOUSE_SENSITIVITY
		rotate_y(-yaw)
		_yaw_accum += yaw
		_pitch = clamp(_pitch - event.relative.y * MOUSE_SENSITIVITY, deg_to_rad(-80.0), deg_to_rad(80.0))
		head.rotation.x = _pitch

func _physics_process(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= GRAVITY * delta

	_tick_flashlight(delta)
	if hidden:
		_tick_hideout(delta)
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	var world := Worlds.def(DimensionState.player_w)
	var sprinting := Input.is_action_pressed("run") and direction != Vector3.ZERO and exhausted <= 0.0 and stamina > 0.0
	_tick_stamina(delta * world.stamina_drain if sprinting else delta, sprinting)
	var speed := (RUN_SPEED if sprinting else (EXHAUSTED_SPEED if exhausted > 0.0 else WALK_SPEED)) * world.player_speed
	var room := RoomGenerator.room_at(global_position, DimensionState.player_w)
	if room:
		speed *= room.speed_at(global_position - room.global_position)

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
	var running := sprinting and hspeed > 0.1
	avatar.move_speed = hspeed if is_on_floor() else 0.0
	avatar.running = running
	if is_on_floor() and hspeed > 0.1:
		var before := _bob_t
		_bob_t += delta * hspeed * BOB_FREQ
		if floori((_bob_t - STEP_PHASE) / TAU) != floori((before - STEP_PHASE) / TAU):
			var steps := steps_run if running else steps_walk
			steps.volume_db = (-3.0 if running else -6.0) + linear_to_db(world.noise)
			steps.play()
	camera.fov = lerpf(camera.fov, RUN_FOV if running else WALK_FOV, delta * 6.0)

func _tick_stamina(delta: float, sprinting: bool) -> void:
	exhausted = maxf(exhausted - delta, 0.0)
	if sprinting:
		_since_sprint = 0.0
		stamina = maxf(stamina - delta / SPRINT_TIME, 0.0)
		if stamina <= 0.0:
			exhausted = EXHAUST_TIME
			breath.play()
	else:
		_since_sprint += delta
		if _since_sprint >= REGEN_DELAY:
			stamina = minf(stamina + delta / REGEN_TIME, 1.0)
	# Panting outlasts the slowdown a little, fading as you recover.
	if breath.playing:
		breath.volume_db = linear_to_db(clampf(exhausted / EXHAUST_TIME + (1.0 - stamina) * 0.5, 0.0, 1.0))
		if exhausted <= 0.0 and stamina > 0.5:
			breath.stop()

func _tick_flashlight(delta: float) -> void:
	var lit := has_flashlight() and flashlight_on
	if lit:
		battery = maxf(battery - delta / BATTERY_TIME, 0.0)
		flashlight_on = battery > 0.0
	else:
		battery = minf(battery + delta / RECHARGE_TIME, 1.0)
	_flash.visible = lit
	# Low battery stutters; so does something folding in nearby.
	var monster := get_tree().get_first_node_in_group("monster") as Monster
	var omen := monster != null and monster.omen_left > 0.0
	_flash.light_energy = FLASH_ENERGY
	if (battery < BATTERY_LOW and randf() < 0.08) or (omen and randf() < 0.3):
		_flash.light_energy = randf_range(0.0, 1.2)

# --- hideouts -------------------------------------------------------------------------

## The hideout of the room you're in, if you're at its door.
func hideout_in_reach() -> Room:
	var room := RoomGenerator.room_at(global_position, DimensionState.player_w)
	if room == null or not room.hideout:
		return null
	var door := room.global_position + Room.HIDE_EXIT
	return room if Vector2(global_position.x - door.x, global_position.z - door.z).length() <= Room.HIDE_REACH else null

func enter_hideout(room: Room) -> void:
	var monster := get_tree().get_first_node_in_group("monster") as Monster
	if monster and monster.saw_hiding():
		GameManager.trigger_game_over("TE VIO ESCONDERTE")
		return
	if monster:
		monster.lose_track()
	hidden = true
	hide_t = 0.0
	_hide_room = room
	collision_layer = 0 # nothing detects you in there
	velocity = Vector3.ZERO
	global_position = room.global_position + Room.HIDE_POS
	rotation.y = Room.HIDE_YAW
	_pitch = 0.0
	head.rotation.x = 0.0
	_bob_amount = 0.0
	AudioManager.play_sfx(&"hide_in")

func leave_hideout() -> void:
	if not hidden:
		return
	hidden = false
	collision_layer = 2
	if is_instance_valid(_hide_room):
		global_position = _hide_room.global_position + Room.HIDE_EXIT
	AudioManager.play_sfx(&"hide_out")

## The clock keeps running in there; after HIDE_UNSTABLE it starts giving
## way, at HIDE_MAX it throws you out.
func _tick_hideout(delta: float) -> void:
	var before := hide_t
	hide_t += delta
	stamina = minf(stamina + delta / REGEN_TIME, 1.0)
	if before < HIDE_UNSTABLE and hide_t >= HIDE_UNSTABLE:
		AudioManager.play_sfx(&"hide_unstable")
	if hide_t >= HIDE_UNSTABLE and is_instance_valid(_hide_room):
		_hide_room.disturb(0.2)
	if hide_t >= HIDE_MAX:
		leave_hideout()

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
