shader_type spatial;
render_mode unshaded;

// Stained glass: every pane (a box; Room writes its index into UV.x) glows
// in one of four hues turned from the world's signal colour. Unshaded:
// it's a light source, and one draw for every pane in the room.

uniform vec3 emission : source_color = vec3(1.0, 0.6, 0.2);
uniform float energy = 1.3;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

// Hue rotation (turns) about the grey axis.
vec3 hue(vec3 c, float turns) {
	float a = turns * 6.2831853;
	vec3 k = vec3(0.57735);
	return c * cos(a) + cross(k, c) * sin(a) + k * dot(k, c) * (1.0 - cos(a));
}

void fragment() {
	float pick = floor(hash(UV.x + 0.5) * 4.0);
	ALBEDO = max(hue(emission, pick * 0.25), vec3(0.0)) * energy;
}
