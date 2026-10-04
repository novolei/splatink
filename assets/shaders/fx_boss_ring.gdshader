shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, fog_disabled;
uniform vec3 uColor:source_color=vec3(1.0,0.3,0.3);
uniform float uAlpha=1.0;
uniform float uTime=0.0;
uniform float uR=2.4;
uniform float uW=0.65;
varying float vSide;
varying float vCut;
varying float vA;
void vertex(){
	float a=CUSTOM0.r;float side=CUSTOM0.g;
	float r=max(0.0,uR+side*uW);vSide=side;vCut=CUSTOM0.b-uR;vA=a;
	VERTEX=vec3(sin(a)*r,0.0,cos(a)*r);
}
void fragment(){
	if(vCut<0.0)discard;float x=vSide*0.5+0.5;
	float band=smoothstep(0.0,0.35,x)*(1.0-smoothstep(0.8,1.0,x));
	float crest=smoothstep(0.55,0.9,x)*(1.0-smoothstep(0.9,1.0,x));
	float a=max(band*(0.75+0.25*sin(vA*70.0+uTime*10.0)),crest);
	ALBEDO=mix(uColor,vec3(1.0),crest*0.45)*1.4;
	ALPHA=a*uAlpha*smoothstep(0.0,0.7,vCut);
}
