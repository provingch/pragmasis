shader_type spatial;

// The background universe of cubes (CubeField): one instance per cell
// around the built rooms, placed on the cell grid. Which cells stand empty,
// how big each cube is and how far it's nudged off its cell's centre all
// come from a hash of the cell, here: the node only moves when the player
// changes cell, the CPU never touches an instance. Dark, with light edges
// in the stratum's signal color. They lie beyond the rooms' own fog, so
// they fade to the fog's color on a longer curve of their own, already
// half gone at the nearest: silhouettes in the haze, not holes in it.
// Edges widen with distance so they still read far off.

render_mode cull_back, shadows_disabled, fog_disabled;

uniform vec3 albedo : source_color = vec3(0.03);
uniform vec3 edge_color : source_color = vec3(0.8, 0.9, 1.0);
uniform float edge_energy = 1.4;
// Share of cells left empty (never all: the universe keeps some cubes).
uniform float gaps = 0.35;
uniform float cell = 10.0;
uniform vec3 fog_color : source_color = vec3(0.0);
uniform float fade_begin = 30.0;
uniform float fade_end = 110.0;
// Fog already on the nearest cubes.
uniform float haze = 0.5;

varying vec3 local;
varying float size;
varying float fade;
varying float dist;

float hash(vec3 p) {
	p = fract(p * vec3(0.1031, 0.1030, 0.0973));
	p += dot(p, p.yxz + 33.33);
	return fract((p.x + p.y) * p.z);
}

void vertex() {
	vec3 at = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
	vec3 c = floor(at / cell + 0.5);
	float h = hash(c);
	local = VERTEX;
	if (h < gaps) {
		VERTEX = vec3(0.0); // an empty cell: collapse the whole cube
	} else {
		float h2 = hash(c + 17.0);
		size = mix(0.3, 0.9, h2 * h2);
		vec3 nudge = (vec3(hash(c + 3.1), hash(c + 5.7), hash(c + 9.3)) - 0.5) * (1.0 - size) * cell;
		VERTEX = VERTEX * size + nudge / cell;
	}
	dist = length((MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).xyz);
	fade = mix(haze, 1.0, smoothstep(fade_begin, fade_end, dist));
}

void fragment() {
	// Near two faces at once: an edge. Width in metres, whatever the size.
	vec3 d = 0.5 - abs(local);
	float w = max(0.06, dist * 0.004) / (size * cell);
	float n = step(d.x, w) + step(d.y, w) + step(d.z, w);
	float edge = step(2.0, n);
	// Unshaded look: its own color, the fog's, the edges' light.
	ALBEDO = vec3(0.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	EMISSION = mix(mix(albedo, edge_color * edge_energy, edge), fog_color, fade);
}
