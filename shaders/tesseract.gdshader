shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_always;

// Per-edge color/alpha come from the MultiMesh instance color (HDR allowed).
uniform float energy = 1.6;

void fragment() {
	ALBEDO = COLOR.rgb * energy;
	ALPHA = COLOR.a;
}
