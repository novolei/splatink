shader_type canvas_item;
render_mode unshaded;
// Original ui.css News ticket: outside white/ink rings, hard offset shadow, tiled print grain.
uniform vec2 body_size=vec2(1126.4,499.2);
uniform vec2 quad_size=vec2(1166.4,555.2);
uniform vec2 padding=vec2(20.0);
uniform float pixel_scale=1.0;
uniform float radius=30.72;
uniform float white_spread=4.48;
uniform float ink_spread=8.96;
uniform float shadow_drop=12.8;
uniform float shadow_alpha=.45;
uniform vec4 ink_color:source_color=vec4(.08235,.07059,.10980,1.0);
uniform vec4 top_color:source_color=vec4(.16863,.13725,.25882,1.0);
uniform vec4 bottom_color:source_color=vec4(.09020,.07059,.12157,1.0);
uniform bool print_grain=true;
uniform bool image_face=false;
uniform sampler2D grain_tex:filter_nearest,repeat_enable;
uniform sampler2D image_tex:source_color,filter_linear;
float rounded_box(vec2 p,vec2 half_size,float r){vec2 q=abs(p)-half_size+vec2(r);return min(max(q.x,q.y),0.0)+length(max(q,vec2(0.0)))-r;}
float cover(float distance){float aa=.5/max(pixel_scale,.01);return 1.0-smoothstep(-aa,aa,distance);}
vec4 over(vec4 below,vec4 above){float a=above.a+below.a*(1.0-above.a);return vec4(a>.00001?(above.rgb*above.a+below.rgb*below.a*(1.0-above.a))/a:vec3(0.0),a);}
void fragment(){
	vec4 tint=COLOR;
 vec2 p=UV*quad_size-padding;
 float d=rounded_box(p-body_size*.5,body_size*.5,radius);
 float shadow=rounded_box(p-body_size*.5-vec2(0.0,shadow_drop),body_size*.5,radius)-ink_spread;
 vec4 result=vec4(0.0,0.0,0.0,cover(shadow)*shadow_alpha);
 result=over(result,vec4(ink_color.rgb,cover(d-ink_spread)));
 result=over(result,vec4(1.0,1.0,1.0,cover(d-white_spread)));
 vec2 direction=vec2(.173648,.984808); // CSS 170 degrees.
 float progress=clamp(dot(p-body_size*.5,direction)/dot(body_size,abs(direction))+.5,0.0,1.0);
 vec4 face=mix(top_color,bottom_color,progress);
 if(image_face){face=texture(image_tex,clamp(p/body_size,vec2(0.0),vec2(1.0)));}
 if(print_grain){
  vec2 physical=p*pixel_scale;
  vec4 grain=texture(grain_tex,physical/140.0);
  face.rgb=mix(face.rgb,grain.rgb,grain.a);
  float dot_alpha=(1.0-smoothstep(1.1,1.5,length(mod(physical,vec2(9.0))-vec2(4.5))))*.06;
  float fade=1.0-clamp((p.x+p.y)/(body_size.x+body_size.y)/.55,0.0,1.0);
  face.rgb=mix(face.rgb,vec3(1.0),dot_alpha*fade);
 }
 result=over(result,vec4(face.rgb,face.a*cover(d)));
	COLOR=result*tint;
}
