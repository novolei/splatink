shader_type canvas_item;
render_mode unshaded;
uniform sampler2D base_map : filter_linear, repeat_disable;
uniform sampler2D cells : filter_nearest, repeat_disable;
uniform sampler2D grid_now : filter_nearest, repeat_disable;
uniform sampler2D grid_before : filter_nearest, repeat_disable;
uniform vec2 grid_size = vec2(512.0,512.0);
uniform vec2 map_size = vec2(350.0,616.0);
uniform vec3 team_a = vec3(1.0,.541176,.07843);
uniform vec3 team_b = vec3(.18431,.35686,1.0);
uniform float flash = 0.0;

float field_cell(sampler2D grid_tex,float index){
	vec2 p=vec2(mod(index,grid_size.x),floor(index/grid_size.x));
	return round(texture(grid_tex,(p+.5)/grid_size).r*255.0);
}
vec3 field(sampler2D grid_tex,vec2 uv){
	vec4 m=texture(cells,uv);
	float k=round(m.r);
	if(k<0.0)return vec3(0.0,0.0,1.0);
	float g00=field_cell(grid_tex,k),g10=field_cell(grid_tex,k+m.b),g01=field_cell(grid_tex,k+m.a),g11=field_cell(grid_tex,k+m.b+m.a);
	if(g00==g10&&g00==g01&&g00==g11)return vec3(g00>0.0?1.0:0.0,g00,g00>0.0?g00:1.0);
	vec2 fraction=vec2(floor(m.g/256.0),mod(m.g,256.0))/255.0;
	vec4 w=vec4((1.0-fraction.x)*(1.0-fraction.y),fraction.x*(1.0-fraction.y),(1.0-fraction.x)*fraction.y,fraction.x*fraction.y);
	vec4 g=vec4(g00,g10,g01,g11);
	float fa=dot(w,vec4(g.x==1.0?1.0:0.0,g.y==1.0?1.0:0.0,g.z==1.0?1.0:0.0,g.w==1.0?1.0:0.0));
	float fb=dot(w,vec4(g.x==2.0?1.0:0.0,g.y==2.0?1.0:0.0,g.z==2.0?1.0:0.0,g.w==2.0?1.0:0.0));
	float team=fa>=fb?1.0:2.0;
	float alpha=smoothstep(.34,.62,max(fa,fb));
	return vec3(alpha,alpha>.5?team:0.0,team);
}
void fragment(){
	vec4 base=texture(base_map,UV);
	vec3 current=field(grid_now,UV);
	float a=current.r;
	vec3 col=base.rgb;
	if(a>.003){
		vec2 px=1.0/map_size;
		float up=(UV.x>px.x*.5&&UV.y>px.y*.5)?field(grid_now,UV-px).r:a;
		float dn=(UV.x<1.0-px.x*.5&&UV.y<1.0-px.y*.5)?field(grid_now,UV+px).r:a;
		float lit=max(0.0,a-up),dark=max(0.0,a-dn);
		vec3 ink=(current.b>1.5?team_b:team_a)*(.94-dark*.32)+lit*(150.0/255.0);
		col=mix(col,clamp(ink,vec3(0.0),vec3(1.0)),a);
		if(flash>.001&&current.g>0.0&&current.g!=field(grid_before,UV).g)col=mix(col,vec3(1.0),flash*(170.0/255.0));
	}
	COLOR=vec4(col,1.0);
}
