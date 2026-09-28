shader_type canvas_item;
// Calm-state stand-in for screen_fx (danger = 0, shift = 0): the same
// vignette and grain, but done with blending instead of reading the screen,
// so no backbuffer copy (~2.7 ms per frame on an integrated GPU).
// Premultiplied blend: out = src.rgb + dst * (1 - src.a)
//   positive grain -> dst * (1 - vig) + n  (identical to screen_fx)
//   negative grain -> dst * (1 - vig - |n|) (screen_fx subtracts |n|; same on dark pixels)
render_mode blend_premul_alpha;

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	float vig = smoothstep(0.3, 0.85, length((SCREEN_UV - 0.5) * vec2(1.25, 1.0))) * 0.6;
	float n = (hash(SCREEN_UV * 911.0 + fract(TIME) * 37.0) - 0.5) * 0.045;
	COLOR = vec4(vec3(max(n, 0.0)), vig + max(-n, 0.0));
}
