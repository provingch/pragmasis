shader_type spatial;

// Geometry turning slowly about the room's vertical axis (the mesh origin
// is the room's centre). Anything within `split` metres of the axis turns
// the other way: nested frames counter-rotate like a tesseract folding.

uniform vec3 albedo : source_color = vec3(0.1, 0.0, 0.0);
uniform vec3 emission : source_color = vec3(1.0, 0.1, 0.1);
uniform float energy = 1.4;
uniform float speed = 0.12;
uniform float split = 1.6;

void vertex() {
	float dir = max(abs(VERTEX.x), abs(VERTEX.z)) < split ? -1.0 : 1.0;
	float a = TIME * speed * dir + MODEL_MATRIX[3].x * 0.05 + MODEL_MATRIX[3].z * 0.07;
	mat3 r = mat3(vec3(cos(a), 0.0, -sin(a)), vec3(0.0, 1.0, 0.0), vec3(sin(a), 0.0, cos(a)));
	VERTEX = r * VERTEX;
	NORMAL = r * NORMAL;
}

void fragment() {
	ALBEDO = albedo;
	ROUGHNESS = 0.5;
	EMISSION = emission * energy;
}
