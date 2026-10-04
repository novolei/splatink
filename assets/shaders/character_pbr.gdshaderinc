#include "res://assets/shaders/character_dfg.gdshaderinc"
vec3 native_schlick(vec3 f0,float f90,float vh){
	float fresnel=exp2((-5.55473*vh-6.98316)*vh);
	return f0*(1.0-fresnel)+vec3(f90*fresnel);
}
float native_visibility(float alpha,float nl,float nv){
	float a2=alpha*alpha;
	float gv=nl*sqrt(a2+(1.0-a2)*nv*nv);
	float gl=nv*sqrt(a2+(1.0-a2)*nl*nl);
	return 0.5/max(gv+gl,0.000001);
}
vec3 native_ggx(vec3 f0,float f90,float rough,float nl,float nv,float nh,float vh){
	float alpha=rough*rough;
	float a2=alpha*alpha;
	float denom=nh*nh*(a2-1.0)+1.0;
	float distribution=a2/(PI*max(denom*denom,0.000000000001));
	return native_schlick(f0,f90,vh)*native_visibility(alpha,nl,nv)*distribution;
}
float native_sheen_albedo(float nv,float rough){
	float r2=rough*rough;
	float ri=1.0/(rough+0.1);
	float a=-1.9362+1.0678*rough+0.4573*r2-0.8469*ri;
	float b=-0.6014+0.5538*rough-0.4670*r2-0.1255*ri;
	return clamp(exp(a*nv+b),0.0,1.0);
}
vec3 native_sheen_brdf(vec3 color,float rough,float nl,float nv,float nh){
	float inverse_alpha=1.0/max(rough*rough,0.00000001);
	float sin2=max(1.0-nh*nh,0.0078125);
	float distribution=(2.0+inverse_alpha)*pow(sin2,inverse_alpha*0.5)/(2.0*PI);
	float visibility=clamp(1.0/max(4.0*(nl+nv-nl*nv),0.000001),0.0,1.0);
	return color*distribution*visibility;
}
vec3 native_indirect_diffuse_energy(vec2 fab,vec3 specular,float f90){
	vec3 single_scatter=specular*fab.x+vec3(f90*fab.y);
	float multi_energy=1.0-fab.x-fab.y;
	vec3 average=specular+(vec3(1.0)-specular)*0.047619;
	vec3 multi_scatter=single_scatter*average/(vec3(1.0)-multi_energy*average);
	return vec3(1.0)-single_scatter-multi_scatter*multi_energy;
}
