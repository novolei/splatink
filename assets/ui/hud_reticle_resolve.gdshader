shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform sampler2D source_tex : filter_linear, repeat_disable;
void fragment(){
 vec4 tint=COLOR;
 vec4 src=texture(source_tex,UV);
 // CSS opacity applies after all filters, including their blurred shadows.
 COLOR=vec4(src.rgb*tint.rgb*tint.a,src.a*tint.a);
}
