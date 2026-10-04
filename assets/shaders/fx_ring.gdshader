shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
varying vec4 ink;
varying vec4 state;
void vertex() { ink = COLOR; state = INSTANCE_CUSTOM; }
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float radius = length(p);
	float angle = atan(p.y, p.x);
	float wave = state.r;
	float wobble = sin(angle * 9.0 + state.b * 6.28) * 0.015 + sin(angle * 17.0 - wave * 9.0) * 0.008;
	float width = mix(0.10, 0.028, wave) * state.g;
	float edge = abs(radius - (0.72 + wave * 0.20 + wobble));
	float alpha = 1.0 - smoothstep(width, width + 0.018, edge);
	ALBEDO = mix(ink.rgb, vec3(1.0), pow(max(0.0, 1.0 - edge / max(width, 0.001)), 12.0) * 0.30);
	ALPHA = alpha * ink.a * state.a;
}
