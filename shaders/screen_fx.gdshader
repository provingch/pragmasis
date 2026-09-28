shader_type canvas_item;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear; // no mipmaps: only level 0 is read, and building the screen's mip chain cost ~2.4 ms per frame (integrated GPU)
uniform float danger : hint_range(0.0, 1.0) = 0.0; // entity proximity * coherence
uniform float shift : hint_range(0.0, 1.0) = 0.0;  // phase-jump transition
uniform vec4 tint : source_color = vec4(1.0);      // destination layer color

float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }

void fragment() {
	vec2 uv = SCREEN_UV;

	// Phase tearing: horizontal slices jump sideways while shifting.
	float slice = floor(uv.y * 24.0);
	float t = floor(TIME * 30.0);
	float torn = step(1.0 - shift * 0.8, hash(vec2(t, slice * 3.1)));
	uv.x += (hash(vec2(slice, t)) - 0.5) * torn * shift * 0.14;

	// Chromatic split: faint always, strong on shift, creeps up with danger.
	float ca = 0.0015 + shift * 0.025 + danger * 0.007;
	vec3 col;
	col.r = texture(screen_tex, uv + vec2(ca, 0.0)).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - vec2(ca, 0.0)).b;

	col = mix(col, tint.rgb, shift * 0.35);

	// Heartbeat vignette: quickens and bleeds red as danger rises.
	float rate = mix(1.0, 2.8, danger);
	float beat = pow(max(sin(TIME * rate * 6.2831), 0.0), 8.0);
	vec2 d = SCREEN_UV - 0.5;
	float vig = smoothstep(0.3, 0.85, length(d * vec2(1.25, 1.0)));
	col *= 1.0 - vig * (0.6 + danger * 0.25);
	col = mix(col, vec3(0.55, 0.0, 0.02), vig * danger * (0.45 + 0.55 * beat));

	col += (hash(SCREEN_UV * 911.0 + fract(TIME) * 37.0) - 0.5) * (0.045 + danger * 0.06);
	COLOR = vec4(col, 1.0);
}
