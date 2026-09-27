shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never;

// Destination layer's signal color, set per portal.
instance uniform vec4 tint : source_color = vec4(0.5, 0.8, 1.0, 1.0);
uniform float band_density = 40.0;

float hash(float n) { return fract(sin(n) * 43758.5453); }

void vertex() {
	// Stepped glitch: ~8 times a second, a few horizontal bands jump sideways.
	float step_t = floor(TIME * 8.0);
	float band = floor(VERTEX.y * 6.0);
	float jump = step(0.82, hash(band + step_t * 13.1)) * (hash(band * 7.0 + step_t) - 0.5) * 0.35;
	float wobble = sin(VERTEX.y * 9.0 + TIME * 5.0) * 0.04 + sin(VERTEX.x * 7.0 - TIME * 3.0) * 0.04;
	VERTEX += NORMAL * wobble;
	VERTEX.x += jump;
}

void fragment() {
	float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 2.5);
	float bands = 0.5 + 0.5 * sin(UV.y * band_density - TIME * 6.0);
	ALBEDO = tint.rgb * (fresnel * 2.8 + bands * 0.3);
	ALPHA = clamp(fresnel * 1.2 + 0.08, 0.0, 1.0);
}
