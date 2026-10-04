shader_type spatial;
render_mode cull_back;
varying vec4 ink;
// Original iw-blob-3: speed-stretched tail, pressure-flat nose, liquid wobble and near-camera dither.
void vertex() {
	ink=COLOR;
	vec4 shape=INSTANCE_CUSTOM;
	vec3 p=VERTEX, n=NORMAL;
	float back=step(p.z,0.0), u=clamp(-p.z,0.0,1.0);
	float taper=mix(1.0,1.0-0.42*pow(u,1.3),back);
	float axial=mix(1.0-0.22*shape.a,max(shape.r,1.0),back);
	vec3 wet=vec3(p.xy*taper,p.z*axial);
	NORMAL=normalize(vec3(n.xy/max(taper,0.15),n.z/axial));
	float wobble=shape.g*(0.6*sin(shape.b+2.3*p.x+1.7*p.y+0.9*p.z)+0.4*sin(1.63*shape.b-2.9*p.y+2.1*p.z));
	VERTEX=wet+n*wobble*(1.0-0.5*back*u);
}
void fragment() {
	float near=smoothstep(0.55,1.6,length(VERTEX));
	float dither=fract(52.9829189*fract(dot(FRAGCOORD.xy,vec2(0.06711056,0.00583715))));
	if(dither>near) discard;
	ALBEDO=ink.rgb;
	ROUGHNESS=0.12;
	CLEARCOAT=1.0; CLEARCOAT_ROUGHNESS=0.04;
	float rim=pow(1.0-clamp(dot(NORMAL,VIEW),0.0,1.0),3.0);
	EMISSION=ink.rgb*(0.16+0.55*rim);
}
