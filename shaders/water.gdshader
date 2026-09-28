shader_type spatial;

// Still or ankle-deep water, opaque: no refraction, no reflection probe.
// Slow interfering ripples shade the albedo and tilt the normal, so the
// room light's highlight wobbles across it.

uniform vec3 albedo : source_color = vec3(0.1, 0.18, 0.2);
uniform float ripple = 0.12;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float a = sin(p.x * 2.3 + TIME * 0.9) * sin(p.y * 1.9 - TIME * 0.7);
	float b = sin((p.x + p.y) * 4.1 + TIME * 1.6);
	vec2 slope = vec2(cos(p.x * 2.3 + TIME * 0.9), cos(p.y * 1.9 - TIME * 0.7)) + b * 0.4;
	ALBEDO = albedo * (0.9 + 0.1 * (a + 0.5 * b));
	ROUGHNESS = 0.06;
	SPECULAR = 0.7;
	NORMAL = normalize(NORMAL + (VIEW_MATRIX * vec4(slope.x, 0.0, slope.y, 0.0)).xyz * ripple);
}
