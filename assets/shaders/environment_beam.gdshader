shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled,blend_add,depth_draw_never;
uniform float uNight=0.0;uniform vec3 uCol=vec3(1.0,0.76,0.39);varying float vA;varying vec3 vN;varying vec3 vV;
void vertex(){vA=clamp(VERTEX.x/150.0,0.0,1.0);vec3 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vN=normalize(mat3(MODEL_MATRIX)*NORMAL);vV=normalize(CAMERA_POSITION_WORLD-wp);}
void fragment(){float e=pow(clamp(abs(dot(normalize(vN),normalize(vV))),0.0,1.0),2.0);float a=e*pow(max(1.0-vA,0.0),1.6)*smoothstep(0.0,0.03,vA)*0.5*uNight;ALBEDO=uCol*a;ALPHA=1.0;}
