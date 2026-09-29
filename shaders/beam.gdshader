shader_type spatial;
// A shaft of light (Room's "beam" kind): added over the scene, brightest
// where you look through the most of it (faces seen head-on), fading to
// nothing at its silhouette, so a box reads as a soft volume.
render_mode blend_add, unshaded, cull_back, depth_draw_never, shadows_disabled, fog_disabled;

uniform vec4 color : source_color = vec4(1.0);
uniform float energy = 0.14;

void fragment() {
	float facing = abs(dot(NORMAL, VIEW));
	ALBEDO = color.rgb * energy * facing * facing;
}
