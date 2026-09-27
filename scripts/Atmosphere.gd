extends WorldEnvironment

## Fog, ambient and glow in the active layer's palette; blends on shift.

const BLEND_TIME := 0.9

func _ready() -> void:
	environment = Environment.new()
	var env := environment
	env.background_mode = Environment.BG_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_energy = 0.4
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_exposure = 1.1
	env.glow_enabled = true
	env.glow_intensity = 0.9
	env.glow_bloom = 0.12
	env.glow_hdr_threshold = 0.9
	env.fog_enabled = true
	env.fog_sky_affect = 1.0
	env.ssao_enabled = true
	env.adjustment_enabled = true
	env.adjustment_saturation = 0.85
	env.adjustment_contrast = 1.1
	_apply(DimensionState.player_w, 0.0)
	DimensionState.layer_changed.connect(_apply.bind(BLEND_TIME))

func _apply(w: int, time: float) -> void:
	var s: Dictionary = DimensionState.LAYERS[w]
	var env := environment
	if time <= 0.0:
		env.fog_light_color = s.fog
		env.fog_density = s.fog_density
		env.background_color = s.fog
		env.ambient_light_color = s.light
		return
	var tw := create_tween().set_parallel()
	tw.tween_property(env, "fog_light_color", s.fog, time)
	tw.tween_property(env, "fog_density", s.fog_density, time)
	tw.tween_property(env, "background_color", s.fog, time)
	tw.tween_property(env, "ambient_light_color", s.light, time)
