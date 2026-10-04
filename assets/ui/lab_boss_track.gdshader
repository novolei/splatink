shader_type canvas_item;
render_mode unshaded;
uniform vec2 panel_size=vec2(510.0,28.0);
uniform vec4 boss:source_color=vec4(.184,.357,1.0,1.0);
uniform float hp:hint_range(0.0,1.0)=1.0;
uniform float chip:hint_range(0.0,1.0)=1.0;
uniform float flash:hint_range(0.0,1.0)=0.0;
uniform vec4 flash_color:source_color=vec4(1.0);
uniform bool enraged=false;
uniform bool shield=false;
void fragment(){
	vec2 q=abs(UV*panel_size-panel_size*.5)-(panel_size*.5-vec2(7.0));float d=min(max(q.x,q.y),0.0)+length(max(q,vec2(0.0)))-7.0;
	vec3 fill=vec3(.043,.035,.063);
	if(UV.x<=chip)fill=mix(vec3(1.0),vec3(1.0,.914,.84),UV.y);
	if(UV.x<=hp){
		vec3 ink=boss.rgb;if(enraged)ink=mix(ink,vec3(1.0,.176,.333),.38);
		fill=ink*mix(1.32,.57,UV.y);float stripes=step(.5,fract((UV.x*panel_size.x+UV.y*panel_size.y*.577-TIME*20.7)/17.9));fill=mix(fill,vec3(1.0),.17*stripes);
		float gloss=(1.0-smoothstep(.1,.44,UV.y))*step(.1,UV.y);fill=mix(fill,vec3(1.0),.5*gloss);
		if(hp<=.2)fill*=1.0+.45*(.5+.5*sin(TIME*TAU/.7));
		if(shield){float gray=dot(fill,vec3(.299,.587,.114));fill=mix(vec3(gray),fill,.3)*.85;}
		fill=mix(fill,flash_color.rgb,flash*.55);
		if(abs(UV.x-hp)*panel_size.x<2.0)fill=vec3(1.0);
	}
	COLOR=vec4(fill,1.0-smoothstep(-.5,.6,d));
}
