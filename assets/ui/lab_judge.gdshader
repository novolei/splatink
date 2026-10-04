shader_type canvas_item;
void fragment(){float d=length((UV-vec2(.5,.55))*vec2(1.0,1.3));vec3 c=mix(vec3(.133,.102,.235),vec3(.031,.024,.055),smoothstep(0.0,.7,d));float dots=1.0-smoothstep(1.3,1.8,length(mod(FRAGCOORD.xy,14.0)-7.0));c+=vec3(.06)*dots;COLOR=vec4(c,.96)*COLOR;}
