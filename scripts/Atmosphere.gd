extends WorldEnvironment

## Fog, ambient and glow in the active world's palette; blends on shift.

const BLEND_TIME := 0.9

func _ready() -> void:
	environment = Environment.new()
	var env := environment
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	# Depth fog, fully opaque at RoomGenerator.fog_end() (see _apply_settings).
	env.fog_enabled = true
	env.fog_mode = Environment.FOG_MODE_DEPTH
	env.fog_density = 1.0
	env.fog_sky_affect = 1.0
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.1
	_apply(DimensionState.player_w, 0.0)
	DimensionState.layer_changed.connect(_apply.bind(BLEND_TIME))
	_apply_settings()
	Settings.changed.connect(_apply_settings)

## SSAO, glow and fog reach follow the graphics options, live.
func _apply_settings() -> void:
	environment.ssao_enabled = Settings.ssao
	environment.glow_enabled = Settings.glow
	environment.fog_depth_end = RoomGenerator.fog_end()

func _apply(w: int, time: float) -> void:
	var s := Worlds.def(w)
	var env := environment
	if time <= 0.0:
		env.fog_light_color = s.fog_color
		env.fog_depth_begin = s.fog_begin
		env.background_color = s.fog_color
		env.ambient_light_color = s.light_color
		env.ambient_light_energy = s.ambient
		return
	var tw := create_tween().set_parallel()
	tw.tween_property(env, "fog_light_color", s.fog_color, time)
	tw.tween_property(env, "fog_depth_begin", s.fog_begin, time)
	tw.tween_property(env, "background_color", s.fog_color, time)
	tw.tween_property(env, "ambient_light_color", s.light_color, time)
	tw.tween_property(env, "ambient_light_energy", s.ambient, time)
