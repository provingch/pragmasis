shader_type spatial;

// ESTÁTICA's trembling pieces. Room writes each box's index into UV.x, so a
// whole piece jumps as one: on a stepped clock it's displaced a few frames,
// then snaps back. No per-room script, no per-frame CPU.

uniform vec3 albedo : source_color = vec3(0.02);
uniform vec3 emission : source_color = vec3(0.85, 0.98, 1.0);
uniform float emission_energy = 0.6;
uniform float rate = 12.0;     // clock steps per second
uniform float chance = 0.1;    // fraction of steps a piece is displaced
uniform float amount = 0.35;   // metres

float hash(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void vertex() {
	float piece = UV.x + floor(MODEL_MATRIX[3].x * 0.37 + MODEL_MATRIX[3].z * 0.71);
	float t = floor(TIME * rate);
	if (hash(piece * 7.13 + t) < chance) {
		VERTEX += (vec3(hash(piece + t + 1.3), hash(piece + t + 2.7), hash(piece + t + 4.1)) - 0.5) * amount;
	}
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.4;
	EMISSION = emission * emission_energy;
}
