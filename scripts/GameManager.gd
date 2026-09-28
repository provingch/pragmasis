extends Node

## Autoload. The run: sequences (reach the anchor before the clock runs
## out), collapse when it does. Each anchor lies one stratum deeper than
## the last; score = the deepest stratum reached through an anchor, best
## score persisted. Difficulty rises per sequence.

signal game_over
## World regenerates around the player on this (emitted from a process
## step, never from the physics callback that touched the anchor).
signal sequence_completed(completed: int)
signal collapsed

const RECORD_PATH := "user://record.cfg"
## Sequence 1 gets FIRST_TIME seconds, each next one TIME_STEP less, down
## to MIN_TIME.
const FIRST_TIME := 180.0
const TIME_STEP := 15.0
const MIN_TIME := 90.0
const BANNER_TIME := 3.0

var is_game_over := false
## Why the run ended, shown on the game over screen.
var cause := ""
## 1-based: the sequence being played.
var sequence := 1
## Deepest stratum reached through an anchor (0 = still at the surface).
var depth := 0
var time_left := 0.0
var is_collapsed := false
## Best depth ever (persisted).
var best := 0
## A run is in progress (Main is loaded).
var running := false
## Centre-screen announcement (HUD draws it while banner_t > 0).
var banner := ""
var banner_t := 0.0

func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(RECORD_PATH) == OK:
		best = cfg.get_value("run", "depth", 0)

func _process(delta: float) -> void:
	banner_t = maxf(banner_t - delta, 0.0)
	if not running or is_game_over:
		return
	time_left = maxf(time_left - delta, 0.0)
	if time_left <= 0.0 and not is_collapsed:
		is_collapsed = true
		_announce("COLAPSO")
		AudioManager.play_sfx(&"collapse")
		collapsed.emit()

func start_run() -> void:
	is_game_over = false
	sequence = 1
	depth = 0
	time_left = time_limit()
	is_collapsed = false
	running = true

func score() -> int:
	return depth

## Where this sequence's anchor goes: one stratum deeper than the last
## (or the deepest there is).
func anchor_stratum() -> int:
	return mini(depth + 1, Worlds.deepest_stratum())

# --- difficulty per sequence ----------------------------------------------------

func time_limit() -> float:
	return maxf(FIRST_TIME - TIME_STEP * (sequence - 1), MIN_TIME)

## Divides the entity's spawn delay.
func threat_scale() -> float:
	return 1.0 + 0.12 * (sequence - 1)

## Multiplies the entity's speed.
func speed_scale() -> float:
	return minf(1.0 + 0.04 * (sequence - 1), 1.25)

# --- events -------------------------------------------------------------------------

func complete_sequence() -> void:
	if is_game_over or not running:
		return
	var done := sequence
	sequence += 1
	depth = maxi(depth, Worlds.stratum(RoomGenerator.anchor_w))
	if depth > best:
		best = depth
		var cfg := ConfigFile.new()
		cfg.set_value("run", "depth", best)
		cfg.save(RECORD_PATH)
	time_left = time_limit()
	is_collapsed = false
	_announce("ESTRATO %d ALCANZADO" % (depth + 1))
	AudioManager.play_sfx(&"sequence_done")
	get_tree().process_frame.connect(func() -> void: sequence_completed.emit(done), CONNECT_ONE_SHOT)

func trigger_game_over(why := "CAPTURADO") -> void:
	if is_game_over:
		return
	is_game_over = true
	running = false
	cause = why
	get_tree().paused = true
	game_over.emit()

func restart() -> void:
	# Before reload, so every _ready() in the new scene sees w=0.
	DimensionState.reset()
	AudioManager.reset()
	is_game_over = false
	get_tree().paused = false
	get_tree().reload_current_scene()

func _announce(text: String) -> void:
	banner = text
	banner_t = BANNER_TIME
