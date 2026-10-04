shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
varying vec4 ink;
varying vec4 state;
float hash(vec2 p) {
	vec3 p3=fract(vec3(p.x,p.y,p.x)*0.1031);
	p3+=dot(p3,p3.yzx+33.33);
	return fract((p3.x+p3.y)*p3.z);
}
float noise(vec2 p) {
	vec2 i=floor(p), f=fract(p), u=f*f*(3.0-2.0*f);
	return mix(mix(hash(i),hash(i+vec2(1,0)),u.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),u.x),u.y);
}
void vertex() { ink=COLOR; state=INSTANCE_CUSTOM; }
void fragment() {
	vec2 q=vec2(UV.x*2.0-1.0,1.0-UV.y*2.0);
	float r=length(q), seed=state.g*37.0, angle=atan(q.y,q.x), t=state.r;
	float n=noise(vec2(cos(angle),sin(angle))*2.2+seed)*0.6+noise(q*3.1+seed+t*1.5)*0.4;
	float kind=state.b, alpha=0.0;
	vec3 col=ink.rgb;
	if(kind>3.5) {
		float n2=noise(q*4.0+seed+t*2.0), edge=0.55+(n-0.5)*0.6;
		alpha=(1.0-smoothstep(edge*0.4,1.0,r+(n2-0.5)*0.35))*(0.72+0.28*n2);
		col*= (0.86+0.24*clamp(q.y*0.8+0.2,-1.0,1.0))*(0.92+0.12*n2);
	} else if(kind>2.5) {
		q.y*=1.05;
		float mt=clamp((q.y-0.05)/0.9,0.0,1.0), width=mix(0.46,0.0,pow(mt,0.9));
		float fin=0.22*exp(-pow((q.y-0.3)/0.12,2.0));
		float mantle=step(0.02,q.y)*step(q.y,0.95)*(1.0-smoothstep(width+fin-0.025,width+fin+0.025,abs(q.x)));
		float head=1.0-smoothstep(0.39,0.43,length(q-vec2(0,-0.12))), tent=0.0;
		for(int i=0;i<4;i++) {
			float fi=float(i), wx=-0.27+0.18*fi+0.05*sin(q.y*9.0+t*14.0+fi*1.7);
			tent=max(tent,(1.0-smoothstep(0.045,0.07,abs(q.x-wx)))*smoothstep(-0.95,-0.85,q.y)*step(q.y,-0.25));
		}
		alpha=max(max(mantle,head),tent);
		float eyes=max(1.0-smoothstep(0.085,0.105,length(q-vec2(-0.15,-0.1))),1.0-smoothstep(0.085,0.105,length(q-vec2(0.15,-0.1))));
		float shine=(1.0-smoothstep(0.02,0.035,length(q-vec2(-0.17,-0.07))))+(1.0-smoothstep(0.02,0.035,length(q-vec2(0.13,-0.07))));
		col=mix(col,vec3(1),0.3)*(0.88+0.22*clamp(q.y+0.4,0.0,1.0));
		col=mix(col,vec3(0.06,0.06,0.1),eyes*0.9); col=mix(col,vec3(1),clamp(shine,0.0,1.0));
	} else if(kind>1.5) {
		float y=q.y, xv=q.x-0.07*(1.0-y*y);
		float half_width=0.3*sqrt(max(0.0,1.0-y*y))*(1.0-0.25*y);
		float vane=(1.0-smoothstep(half_width-0.07,half_width,abs(xv)))*step(-0.78,y);
		float notch=1.0-(1.0-smoothstep(0.0,0.03,abs(y-0.2-xv*0.7)))*step(0.0,xv)*0.85;
		float shaft=(1.0-smoothstep(0.0,0.035,abs(xv)))*step(y,0.98);
		float barbs=0.84+0.16*sin(y*34.0+abs(xv)*24.0+(xv>0.0?0.0:1.7));
		alpha=max(vane*notch,shaft);
		col=ink.rgb*barbs*(0.88+0.14*y);
		col=mix(col,ink.rgb*0.78,shaft);
	} else if(kind>0.5) {
		float rr=r+(n-0.5)*0.16;
		alpha=1.0-smoothstep(0.84,1.0,rr);
		float top=smoothstep(-0.85,0.75,q.y+(n-0.5)*0.2);
		col=mix(col*0.45,mix(col,vec3(1),0.32),top);
		col+=vec3(0.18)*smoothstep(0.6,0.95,rr)*smoothstep(0.0,0.6,q.y);
	} else {
		float edge=0.62+(n-0.5)*0.5;
		alpha=1.0-smoothstep(edge*0.55,1.0,r+(n-0.5)*0.25);
		col*=0.78+0.32*clamp(q.y*0.8+0.25,-1.0,1.0)+(n-0.5)*0.18;
	}
	ALBEDO=col; ALPHA=alpha*ink.a*state.a;
	if(ALPHA<0.004) discard;
}
