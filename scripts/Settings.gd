extends Node

## Autoload. Graphics options: persisted in user://settings.cfg, applied live.
## The same file doubles as the engine's project-settings override (see
## application/config/project_settings_override), which is how the
## rendering method, readable only at startup, gets switched.

signal changed

const PATH := "user://settings.cfg"
const SECTION := "graphics"
const CUSTOM := "PERSONALIZADO"
## Engine key read at startup from PATH's [rendering] section.
const METHOD_KEY := "renderer/rendering_method"

## Quality fields. Picking a preset sets all of them; touching any one after
## that turns the preset into CUSTOM. shadow_radius: -1 = no real-time
## shadows at all, 0 = only the room you're in, 1..2 = rings around it.
## gen_radius: rooms streamed around you (free radius and fog follow it).
const PRESETS := {
	"BAJA": {"render_scale": 0.6, "ssao": false, "glow": false, "shadow_radius": -1, "gen_radius": 2},
	"MEDIA": {"render_scale": 0.75, "ssao": false, "glow": true, "shadow_radius": 0, "gen_radius": 3},
	"ALTA": {"render_scale": 1.0, "ssao": true, "glow": true, "shadow_radius": 0, "gen_radius": 4},
}
## First run, no file yet: the preset that holds 60 fps on an integrated GPU
## (Intel UHD G1 at 1366x768: ~12 ms GPU; MEDIA ~22 ms).
const DEFAULT_PRESET := "BAJA"
## Free radius per gen radius. The gap avoids churn when pacing across a
## cell border.
const FREE_FOR_GEN := {2: 4, 3: 6, 4: 7}

var preset := DEFAULT_PRESET
var render_scale := 0.6
var ssao := false
var glow := false
var shadow_radius := -1
var gen_radius := 2
var vsync := true
var fullscreen := false
## Saved choice; takes effect on next launch. Compare with running_method().
var rendering_method := "forward_plus"

func _ready() -> void:
	_assign(PRESETS[DEFAULT_PRESET])
	rendering_method = running_method()
	load_settings()
	apply()

func apply_preset(p: String) -> void:
	_assign(PRESETS[p])
	preset = p
	_commit()

## Setter for every field; re-applies and saves.
func set_option(key: String, value: Variant) -> void:
	set(key, value)
	if PRESETS[DEFAULT_PRESET].has(key):
		preset = CUSTOM
	_commit()

func running_method() -> String:
	return RenderingServer.get_current_rendering_method()

func needs_restart() -> bool:
	return rendering_method != running_method()

func free_radius() -> int:
	return FREE_FOR_GEN[gen_radius]

func apply() -> void:
	apply_viewport(get_tree().root)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if vsync else DisplayServer.VSYNC_DISABLED)
	var mode := DisplayServer.WINDOW_MODE_FULLSCREEN if fullscreen else DisplayServer.WINDOW_MODE_WINDOWED
	if DisplayServer.window_get_mode() != mode:
		DisplayServer.window_set_mode(mode)
	RoomGenerator.set_radii(gen_radius, free_radius(), shadow_radius)
	changed.emit()

## FSR 1: one upscale+sharpen pass (~1 ms measured), Forward+ only in 4.5;
## Mobile falls back to bilinear. FSR 2 also exists (Forward+) but its
## temporal pass measured ~14 ms on an integrated GPU, more than it saves.
func apply_viewport(vp: Viewport) -> void:
	vp.scaling_3d_scale = render_scale
	var fsr := render_scale < 1.0 and running_method() == "forward_plus"
	vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR if fsr else Viewport.SCALING_3D_MODE_BILINEAR

func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		save() # first run: write the defaults
		return
	for key in _keys():
		set(key, cfg.get_value(SECTION, key, get(key)))
	render_scale = clampf(render_scale, 0.5, 1.0)
	shadow_radius = clampi(shadow_radius, -1, 2)
	if not FREE_FOR_GEN.has(gen_radius):
		gen_radius = PRESETS[DEFAULT_PRESET].gen_radius
	if not PRESETS.has(preset):
		preset = CUSTOM
	rendering_method = cfg.get_value("rendering", METHOD_KEY, rendering_method)

func save() -> void:
	var cfg := ConfigFile.new()
	for key in _keys():
		cfg.set_value(SECTION, key, get(key))
	cfg.set_value("rendering", METHOD_KEY, rendering_method)
	cfg.save(PATH)

func _keys() -> Array:
	return ["preset"] + PRESETS[DEFAULT_PRESET].keys() + ["vsync", "fullscreen"]

func _assign(values: Dictionary) -> void:
	for key in values:
		set(key, values[key])

func _commit() -> void:
	apply()
	save()
