// Original source ShaderMaterial 12.
shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled,blend_add,depth_draw_never;
varying vec3 source_camera;

      varying vec2 vUv; varying vec3 vCol; varying vec3 vLsW;
      
 
      

uniform vec3 uHzA; uniform vec3 uHzB; uniform vec4 uHzK; uniform float uHzStart;
float lsHazeAmt(vec3 w) {
  float d = max(distance(w, source_camera) - uHzStart, 0.0);
  float h = exp(-max(w.y, 0.0) * uHzK.y);
  return 1.0 - exp(-d * uHzK.x * (0.3 + 0.7 * h));
}
vec3 lsHazeCol(vec3 w) { return mix(uHzA, uHzB, smoothstep(uHzK.z, uHzK.w, -w.z) * (0.55 + 0.45 * exp(-max(w.y, 0.0) * 0.08))); }

      
void vertex(){source_camera=CAMERA_POSITION_WORLD;vec2 sourceUv=vec2(UV.x,1.0-UV.y);
        vec3 c = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
        float r = length(MODEL_MATRIX[0].xyz);
        vLsW = c; vUv = VERTEX.xy; vCol = COLOR.rgb;
        vec4 mv = VIEW_MATRIX * vec4(c, 1.0);
        vec3 toCam = normalize(-mv.xyz);
        mv.xyz += toCam * min(r * 0.8, 0.6);
        mv.xy += VERTEX.xy * r;
        POSITION = PROJECTION_MATRIX * mv;
      }
void fragment(){vec4 sourceOutput=vec4(0.0); float d = length(vUv); float g = exp(-d * d * 7.0) * 0.8 + exp(-d * d * 60.0) * 1.2; g *= smoothstep(1.0, 0.7, d);
        sourceOutput = vec4(vCol * g * (1.0 - lsHazeAmt(vLsW) * 0.8), 1.0); ALBEDO=sourceOutput.rgb;}
