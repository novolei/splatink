shader_type canvas_item;
render_mode unshaded;
void fragment(){float y=UV.y;float alpha=y<.16?mix(.38,.0,y/.16):y<.40?0.0:y<.54?mix(.0,.72,(y-.40)/.14):mix(.72,.9,(y-.54)/.46);COLOR=vec4(.039,.031,.071,alpha);}
