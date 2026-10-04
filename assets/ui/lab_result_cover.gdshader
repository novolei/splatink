shader_type canvas_item;
render_mode unshaded;
uniform vec2 panel_size=vec2(1200.0,40.0);
uniform vec4 team_a:source_color=vec4(1.0,.54,.08,1.0);
uniform vec4 team_b:source_color=vec4(.184,.357,1.0,1.0);
uniform float percent_a=0.5;
uniform float percent_b=0.5;
uniform float progress:hint_range(0.0,1.0)=0.0;
float rounded(vec2 p,vec2 half_size,float radius){vec2 q=abs(p)-half_size+radius;return min(max(q.x,q.y),0.0)+length(max(q,vec2(0.0)))-radius;}
void fragment(){
	vec2 p=UV*panel_size;float pad=7.0;vec2 extent=panel_size-vec2(2.0*pad,2.0*pad+4.0);float radius=extent.y*.5;
	float d=rounded(p-vec2(panel_size.x*.5,pad+extent.y*.5),extent*.5,radius);
	float shadow=1.0-smoothstep(0.0,1.2,rounded(p-vec2(panel_size.x*.5,pad+extent.y*.5+5.0),extent*.5+vec2(6.0),radius+6.0));
	vec4 color=vec4(.0,.0,.0,.3*shadow);
	float outer=1.0-smoothstep(5.0,6.4,d);float white=1.0-smoothstep(2.0,3.4,d);float inside=1.0-smoothstep(-.8,.4,d);
	color=mix(color,vec4(.082,.071,.110,1.0),outer);color=mix(color,vec4(1.0),white);
	vec4 fill=vec4(.17,.15,.21,.8);float x=(p.x-pad)/extent.x;float y=clamp((p.y-pad)/extent.y,0.0,1.0);
	if(x<=percent_a*progress)fill=vec4(team_a.rgb*mix(1.25,.65,smoothstep(-.3,1.0,y)),1.0);
	if(x>=1.0-percent_b*progress)fill=vec4(team_b.rgb*mix(1.25,.65,smoothstep(-.3,1.0,y)),1.0);
	fill.rgb=mix(fill.rgb,vec3(1.0),.3*(1.0-smoothstep(0.0,.45,y)));
	fill.rgb=mix(fill.rgb,vec3(1.0),1.0-smoothstep(1.0,1.8,abs(p.x-panel_size.x*.5)));
	color=mix(color,fill,inside);COLOR=color;
}
