// Original source ShaderMaterial 11.
shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled,blend_add,depth_draw_never;
varying vec3 source_camera;
varying float vF; varying vec3 vN; varying vec3 vV; 
uniform vec3 uCol;    
void vertex(){source_camera=CAMERA_POSITION_WORLD;vec2 sourceUv=vec2(UV.x,1.0-UV.y); vF = CUSTOM0.x; vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0); vN = normalize(mat3(MODEL_MATRIX) * NORMAL); vV = normalize(source_camera - w.xyz); POSITION = PROJECTION_MATRIX * VIEW_MATRIX * w; }
void fragment(){vec4 sourceOutput=vec4(0.0); float e = pow(abs(dot(normalize(vN), normalize(vV))), 2.0); float a = e * smoothstep(0.0, 0.15, vF) * (1.0 - vF * 0.85); sourceOutput = vec4(uCol * a, 1.0); ALBEDO=sourceOutput.rgb;}
