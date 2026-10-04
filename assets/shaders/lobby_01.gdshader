// Original source ShaderMaterial 1.
shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled,blend_add,depth_draw_never;
varying vec3 source_camera;
varying vec2 vUv; varying vec3 vLsW; 
uniform sampler2D map:filter_linear_mipmap; uniform vec3 uCol; uniform float uI; 
      

uniform vec3 uHzA; uniform vec3 uHzB; uniform vec4 uHzK; uniform float uHzStart;
float lsHazeAmt(vec3 w) {
  float d = max(distance(w, source_camera) - uHzStart, 0.0);
  float h = exp(-max(w.y, 0.0) * uHzK.y);
  return 1.0 - exp(-d * uHzK.x * (0.3 + 0.7 * h));
}
vec3 lsHazeCol(vec3 w) { return mix(uHzA, uHzB, smoothstep(uHzK.z, uHzK.w, -w.z) * (0.55 + 0.45 * exp(-max(w.y, 0.0) * 0.08))); }

      
void vertex(){source_camera=CAMERA_POSITION_WORLD;vec2 sourceUv=vec2(UV.x,1.0-UV.y); vUv = sourceUv; vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0); vLsW = w.xyz; POSITION = PROJECTION_MATRIX * VIEW_MATRIX * w; }
void fragment(){vec4 sourceOutput=vec4(0.0); float g = texture(map, vUv).r; vec3 c = uCol / max(max(uCol.r, uCol.g), max(uCol.b, 1e-3));
        sourceOutput = vec4(c * g * g * uI * (1.0 - lsHazeAmt(vLsW)), 1.0); ALBEDO=sourceOutput.rgb;}
