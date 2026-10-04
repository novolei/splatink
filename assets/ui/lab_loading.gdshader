shader_type canvas_item;
render_mode unshaded;
uniform bool title=false;
uniform vec2 viewport_size=vec2(1280.,720.);
float blob(vec2 p,vec2 center,float radius){return 1.-smoothstep(radius-70.,radius+100.,length(p-center));}
void fragment(){
 vec2 p=UV*viewport_size;
 if(title){float top=.38*(1.-smoothstep(0.,.26,UV.y));float bottom=.7*smoothstep(.58,1.,UV.y);float radial=.3*(1.-smoothstep(0.,.7,length((UV-vec2(.5,.4))/vec2(.6,.48))));COLOR=vec4(vec3(.047,.035,.086),max(top,bottom)+radial)*COLOR;}
 else{
  float d=length((UV-vec2(.5,.4))/vec2(1.2,.9));vec3 c=mix(vec3(.169,.125,.314),vec3(.086,.063,.161),smoothstep(0.,.58,d));c=mix(c,vec3(.043,.031,.078),smoothstep(.58,1.,d));
  float w=viewport_size.x,h=viewport_size.y;
  vec3 a=vec3(1.,.541,.078),b=vec3(.184,.357,1.);
  c=mix(c,a,blob(p,vec2(.09*w,.07*w),.21*w)*.5);
  c=mix(c,b,blob(p,vec2(.91*w,h-.03*w),.23*w)*.5);
  c=mix(c,a,blob(p,vec2(.79*w,.06*h+.09*w),.09*w)*.3);
  c=mix(c,b,blob(p,vec2(.21*w,.98*h-.11*w),.11*w)*.28);
  c=mix(c,b,blob(p,vec2(.49*w,.04*h+.05*w),.05*w)*.22);
  c=mix(c,a,blob(p,vec2(.66*w,.92*h-.06*w),.06*w)*.22);
  float dots=(1.-smoothstep(1.2,1.6,length(mod(p,vec2(12.))-vec2(6.))))*smoothstep(.30,.90,length((UV-.5)*2.));c=mix(c,vec3(1.),dots*.06);COLOR=vec4(c,1.)*COLOR;
 }
}
