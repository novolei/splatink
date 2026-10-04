shader_type canvas_item;
render_mode unshaded, blend_add;
// Original LENS_FRAG: additive field stores enemy/own/water in separate RGB channels.
void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float d2 = dot(p, p);
	if (d2 >= 1.0) discard;
	float k = 1.0 - d2;
	COLOR = vec4(COLOR.rgb * k * k, 1.0);
}
