// Original source ShaderMaterial 4.
shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled;
varying vec3 source_camera;

      varying vec3 vN; varying vec3 vV; varying vec3 vNe; varying vec3 vLsW;
      

      uniform vec3 uColA; uniform vec3 uColB; uniform vec3 uColC; uniform vec4 uI;   
      

uniform vec3 uHzA; uniform vec3 uHzB; uniform vec4 uHzK; uniform float uHzStart;
float lsHazeAmt(vec3 w) {
  float d = max(distance(w, source_camera) - uHzStart, 0.0);
  float h = exp(-max(w.y, 0.0) * uHzK.y);
  return 1.0 - exp(-d * uHzK.x * (0.3 + 0.7 * h));
}
vec3 lsHazeCol(vec3 w) { return mix(uHzA, uHzB, smoothstep(uHzK.z, uHzK.w, -w.z) * (0.55 + 0.45 * exp(-max(w.y, 0.0) * 0.08))); }

      
void vertex(){source_camera=CAMERA_POSITION_WORLD;vec2 sourceUv=vec2(UV.x,1.0-UV.y); vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0); vLsW = w.xyz; vN = normalize(mat3(MODEL_MATRIX) * NORMAL); vV = source_camera - w.xyz; vNe = CUSTOM0.xyz;
        POSITION = PROJECTION_MATRIX * VIEW_MATRIX * w; }
void fragment(){vec4 sourceOutput=vec4(0.0);
        vec3 n = normalize(vN), v = normalize(vV); float f = abs(dot(n, v));
        vec3 c = vNe.x > 1.5 ? uColC : (vNe.x > 0.5 ? uColB : uColA); c /= max(max(c.r, c.g), max(c.b, 1e-3));
        float I = vNe.x > 1.5 ? uI.w : (vNe.x > 0.5 ? uI.y : uI.x); if (vNe.y > 0.5) I *= uI.z;
        vec3 col = c * I * (0.45 + 0.55 * f) + vec3(1.0) * I * 0.4 * pow(f, 4.0) + c * 0.06;
        col *= 1.0 - lsHazeAmt(vLsW) * 0.6;
        sourceOutput = vec4(col, 1.0);
      ALBEDO=sourceOutput.rgb;}
