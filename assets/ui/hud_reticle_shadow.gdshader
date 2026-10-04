shader_type canvas_item;
render_mode unshaded, blend_premul_alpha;
uniform sampler2D input_tex : filter_linear, repeat_disable;
uniform sampler2D original_tex : filter_linear, repeat_disable;
uniform vec2 texel_axis=vec2(0.0026041667,0.0);
uniform float weights[37];
uniform int radius=3;
uniform bool composite=false;
uniform vec2 offset_px=vec2(0.0);
uniform vec4 shadow_color : source_color=vec4(0.0,0.0,0.0,.95);
void fragment(){
 float alpha=0.0;
 vec2 uv=UV-offset_px/vec2(384.0);
 for(int i=-18;i<=18;i++){if(abs(i)>radius)continue;alpha+=texture(input_tex,uv+texel_axis*float(i)).a*weights[i+18];}
 if(composite){
  vec4 src=texture(original_tex,UV);float shadow_alpha=alpha*shadow_color.a;
  // Viewport transparent surfaces contain premultiplied RGB; keep that convention.
  COLOR=vec4(src.rgb+shadow_color.rgb*shadow_alpha*(1.0-src.a),src.a+shadow_alpha*(1.0-src.a));
 }else{COLOR=vec4(0.0,0.0,0.0,alpha);}
}
