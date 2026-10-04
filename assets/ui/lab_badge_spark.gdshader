shader_type canvas_item;
render_mode unshaded;
uniform vec4 ink:source_color=vec4(1.,.54,.078,1.);
void fragment(){vec2 p=UV-.5;float r=length(p);float a=fract(atan(p.y,p.x)/6.2831853-TIME/1.6);float rays=(1.-smoothstep(.02,.05,abs(a-.25)))+(1.-smoothstep(.02,.05,abs(a-.75)));float mask=smoothstep(.24,.31,r)*(1.-smoothstep(.41,.47,r));COLOR=vec4(mix(ink.rgb,vec3(1.),step(.5,a)),mask*rays);}
