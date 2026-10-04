shader_type canvas_item;
uniform vec4 ink : source_color=vec4(1.0,.541,.078,1.0);
uniform vec2 viewport_size=vec2(1280.0,720.0);
uniform float reveal=1.0;
void fragment(){
 vec2 p=UV-vec2(.5,.45);float radial=clamp(length(p/vec2(.8,.7)),0.0,1.0);
 vec3 outer=mix(ink.rgb*.48,vec3(.047,.035,.086),.45);
 vec3 col=mix(ink.rgb,outer,smoothstep(.3,1.0,radial));
 float dots=1.0-smoothstep(2.0,2.5,length(mod(UV*viewport_size,vec2(16.0))-vec2(8.0)));
 col*=1.0-dots*.16;
 float angle=atan(p.y,p.x);float edge=1.0+.13*sin(angle*9.0)+.055*sin(angle*17.0);
 float alpha=1.0-smoothstep(reveal*edge-.01,reveal*edge+.01,length(p));
 COLOR=vec4(col,mix(.88,.76,radial)*alpha);
}
