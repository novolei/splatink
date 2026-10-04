shader_type canvas_item;
render_mode unshaded;
uniform vec2 panel_size=vec2(150.,250.);
uniform float radius=18.;
void fragment(){vec2 q=abs((UV-.5)*panel_size)-panel_size*.5+radius;float d=min(max(q.x,q.y),0.)+length(max(q,0.))-radius;vec4 c=texture(TEXTURE,UV);COLOR=vec4(c.rgb,c.a*(1.-smoothstep(-.65,.65,d)));}
