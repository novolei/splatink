shader_type canvas_item;
uniform vec2 panel_size = vec2(640.0,160.0);
uniform vec4 top_color: source_color = vec4(0.18,0.14,0.29,1.0);
uniform vec4 bottom_color: source_color = vec4(0.11,0.08,0.19,1.0);
uniform vec4 border_color: source_color = vec4(1.0);
uniform float radius = 16.0;
uniform float border = 2.5;
uniform bool stripes = false;
uniform bool notches = false;
uniform sampler2D squids: repeat_enable, filter_linear;
float box(vec2 p,vec2 b,float r){vec2 q=abs(p)-b+r;return min(max(q.x,q.y),0.0)+length(max(q,0.0))-r;}
void fragment(){
 vec2 px=UV*panel_size;
 float d=box(px-panel_size*.5,panel_size*.5-vec2(border),radius);
 vec4 col=mix(top_color,bottom_color,clamp(UV.y+UV.x*.12,0.0,1.0));
 if(stripes){float stripe=step(.5,fract((px.x+px.y+TIME*13.58)/43.445));col.rgb*=1.0-stripe*.13;}
 vec4 pat=texture(squids,px/69.12);col.rgb=mix(col.rgb,pat.rgb,pat.a);
 col.rgb=mix(col.rgb,border_color.rgb,smoothstep(-border-1.0,-border+1.0,d));
 float a=1.0-smoothstep(-1.0,1.0,d);
 if(notches){float h=panel_size.y*.62;float hole=min(length(px-vec2(0.0,h)),length(px-vec2(panel_size.x,h)));a*=smoothstep(12.16,13.0,hole);}
 COLOR=vec4(col.rgb,col.a*a)*COLOR;
}
