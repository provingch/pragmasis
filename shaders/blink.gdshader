shader_type spatial;

// INTERFERENCIA's lines: light that drops out and spikes, each piece on
// its own stepped clock (Room writes each box's index into UV.x). Pieces
// take one of three colors by hash.

uniform vec3 emission : source_color = vec3(0.25, 1.0, 0.9);
uniform vec3 emission2 : source_color = vec3(0.3, 1.0, 0.45);
uniform float energy = 2.4;
uniform float rate = 9.0;          // clock steps per second
uniform float off_chance = 0.22;   // steps a piece is dark
uniform float spike_chance = 0.07; // steps a piece flares

varying float level;
varying vec3 tint;

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float piece = UV.x + floor(MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.71);
	float t = floor(TIME * rate + hash(piece) * 5.0);
	float h = hash(piece * 3.1 + t);
	level = h < off_chance ? 0.03 : (h > 1.0 - spike_chance ? 3.0 : 1.0);
	float c = hash(piece * 1.7);
	tint = c < 0.4 ? emission : (c < 0.75 ? emission2 : vec3(1.0));
}

void fragment() {
	ALBEDO = vec3(0.0);
	ROUGHNESS = 0.5;
	EMISSION = tint * energy * level;
}
