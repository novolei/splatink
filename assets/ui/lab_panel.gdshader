shader_type canvas_item;
render_mode unshaded;
uniform vec2 panel_size=vec2(300.,150.);
uniform float radius=19.2;
uniform vec4 top_color:source_color=vec4(.149,.122,.227,.90);
uniform vec4 bottom_color:source_color=vec4(.071,.055,.118,.92);
uniform vec4 border_color:source_color=vec4(1.,1.,1.,.08);
uniform float border=1.2;
uniform float dots=1.;
float sdf(vec2 p,vec2 b,float r){vec2 q=abs(p)-b+r;return min(max(q.x,q.y),0.)+length(max(q,0.))-r;}
void fragment(){vec2 p=UV*panel_size;float d=sdf(p-panel_size*.5,panel_size*.5,radius);float mask=1.-smoothstep(-.65,.65,d);vec4 c=mix(top_color,bottom_color,UV.y*.85+UV.x*.15);float dot_mask=(1.-smoothstep(1.1,1.5,length(mod(p,vec2(5.33))-vec2(2.66))))*clamp(1.-(UV.x+UV.y),0.,1.)*.07*dots;c.rgb+=dot_mask;float rim=1.-smoothstep(border-.4,border+.4,-d);c.rgb=mix(c.rgb,border_color.rgb,rim*border_color.a);COLOR=vec4(c.rgb,max(c.a,border_color.a*rim)*mask);}
