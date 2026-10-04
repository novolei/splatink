shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture:hint_screen_texture,filter_linear_mipmap,repeat_disable;
void fragment(){
	vec3 c=textureLod(screen_texture,SCREEN_UV,2.35).rgb;
	float l=dot(c,vec3(.2126,.7152,.0722));c=mix(vec3(l),c,.8);
	float dim=mix(.84,.5,UV.x);c=mix(c,vec3(.03137,.02353,.05490),dim);
	COLOR=vec4(c,1.0);
}
