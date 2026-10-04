shader_type canvas_item;
render_mode unshaded;
uniform vec4 ink_color : source_color=vec4(1.0,.54,.08,1.0);
uniform float level=1.0;
uniform float slosh=0.0;
uniform float slosh_velocity=0.0;
uniform float wobble=0.0;
uniform float clock=0.0;
uniform float sub_cost=.7;
uniform bool short_ink=false;
uniform bool low_ink=false;
uniform int bubble_count=0;
uniform vec4 bubbles[14];
float rounded(vec2 p,vec2 half_size,float radius){vec2 q=abs(p)-half_size+radius;return min(max(q.x,q.y),0.0)+length(max(q,0.0))-radius;}
float wave(float u,float liquid){float amp=1.2+wobble*3.0+abs(slosh_velocity)*2.2;return liquid+(u-.5)*slosh*12.0*.9+sin(u*6.5+clock*7.0)*amp*.5+sin(u*11.0-clock*9.5)*amp*.25;}
void fragment(){
 vec2 p=UV*vec2(18.0,76.0);float aa=max(fwidth(p.x),.45);float distance=rounded(p-vec2(9.0,38.0),vec2(6.0,35.0),6.0);
 vec4 color=vec4(.055,.043,.086,.62);float liquid=3.0+70.0*(1.0-level);float u=clamp((p.x-3.0)/12.0,0.0,1.0);
 // Original canvas has ten line segments; interpolation preserves the same liquid edge.
 float segment=floor(u*10.0);float surface=mix(wave(segment/10.0,liquid),wave(min(10.0,segment+1.0)/10.0,liquid),fract(u*10.0));
 if(p.y>=surface){
  vec3 deep=mix(ink_color.rgb,vec3(.070588,.054902,.109804),.55);vec3 dark=mix(ink_color.rgb,vec3(.070588,.054902,.109804),.3);vec3 light=mix(ink_color.rgb,vec3(1.0),.42);vec3 mid=ink_color.rgb;
  vec3 fill=p.x<8.4?mix(dark,mid,clamp((p.x-3.0)/5.4,0.0,1.0)):mix(mid,light,clamp((p.x-8.4)/6.6,0.0,1.0));
  float depth=clamp((p.y-liquid)/max(1.0,76.0-liquid),0.0,1.0);
  fill=mix(fill,vec3(1.0),.18*(1.0-smoothstep(0.0,.15,depth)));fill=mix(fill,deep,.4*depth);
  color=vec4(fill,1.0);
  for(int i=0;i<14;i++){if(i>=bubble_count)break;vec4 b=bubbles[i];vec2 center=vec2(3.0+b.x*12.0+sin(b.y*20.0),73.0-b.y*70.0);float k=1.0-smoothstep(b.z-aa,b.z+aa,length(p-center));color.rgb=mix(color.rgb,vec3(1.0),k*.6);}
 }
 color.a*=1.0-smoothstep(-aa,aa,distance);
 // Cost stripe is drawn after the liquid and before the gloss/rim in source.
 if(sub_cost>0.0&&p.x>=2.0&&p.x<=16.0){float cost_y=3.0+70.0*(1.0-sub_cost);float stripe=1.0-smoothstep(1.2-aa,1.2+aa,abs(p.y-cost_y));vec3 cost_color=short_ink?vec3(1.0,.302,.369):vec3(1.0);color=mix(color,vec4(cost_color,1.0),stripe);float shadow=step(cost_y+1.2,p.y)*(1.0-step(cost_y+2.2,p.y));color=mix(color,vec4(0.0,0.0,0.0,.55),shadow);}
 float gloss=1.0-smoothstep(-aa,aa,rounded(p-vec2(6.36,21.9),vec2(.96,14.0),.96));color.rgb=mix(color.rgb,vec3(1.0),gloss*.5);
 // Canvas body rim: 3.4px dark under-stroke, then 1.8px white/red.
 float outer=1.0-smoothstep(1.7-aa,1.7+aa,abs(distance));color=mix(color,vec4(.047,.035,.078,.8),outer);
 float rim=1.0-smoothstep(.9-aa,.9+aa,abs(distance));vec3 rim_color=low_ink&&sin(clock*14.0)>0.0?vec3(1.0,.239,.369):vec3(1.0);color=mix(color,vec4(rim_color,1.0),rim);
 COLOR=color;
}
