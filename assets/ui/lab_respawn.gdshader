shader_type canvas_item;
uniform float progress=0.0;
void fragment(){vec2 p=UV-.5;float r=length(p);float a=1.0-smoothstep(.455,.465,r);vec3 c=vec3(.055,.043,.086);float ring=smoothstep(.385,.395,r)*(1.0-smoothstep(.45,.46,r));c=mix(c,vec3(.3,.28,.36),ring);float angle=mod(atan(p.y,p.x)+1.5707963+6.2831853,6.2831853)/6.2831853;c=mix(c,vec3(1.0),ring*step(angle,progress));COLOR=vec4(c,.9*a)*COLOR;}
