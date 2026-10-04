shader_type canvas_item;
uniform vec4 light:source_color=vec4(1.0,.949,.659,1.0);
uniform vec4 metal:source_color=vec4(.949,.698,.180,1.0);
uniform vec4 dark:source_color=vec4(.604,.361,.031,1.0);
uniform float age=0.0;
void fragment(){
 vec2 p=UV-.5;float r=length(p);
 float a=1.0-smoothstep(.47,.485,r);
 float grad=clamp(length(UV-vec2(.35,.28))/0.75,0.0,1.0);
 vec3 c=mix(light.rgb,metal.rgb,smoothstep(0.0,.55,grad));c=mix(c,dark.rgb,smoothstep(.55,1.0,grad));
 c=mix(c,vec3(.082,.071,.11),smoothstep(.45,.465,r));
 c=mix(c,vec3(1.0),smoothstep(.425,.435,r)*(1.0-smoothstep(.44,.45,r))*.35);
 float shine=1.0-abs(UV.x+UV.y*.3-(mod(TIME+age,3.4)*1.1-1.3));c+=vec3(.65)*smoothstep(.85,1.0,shine);
 COLOR=vec4(c,a)*COLOR;
}
