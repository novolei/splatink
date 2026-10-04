shader_type canvas_item;
render_mode unshaded;
void fragment(){float alpha=mix(.45,.72,smoothstep(0.,1.,length((UV-.5)*vec2(1.4,1.4))));COLOR=vec4(.039,.031,.071,alpha)*COLOR;}
