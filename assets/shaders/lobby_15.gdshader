// Original source ShaderMaterial 15.
shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled,blend_mix,depth_draw_never;
varying vec3 source_camera;

      varying vec2 vUv; varying float vSeed; varying vec3 vLsW;
      

      uniform float uTime; uniform vec3 uCol;  
      

uniform vec3 uHzA; uniform vec3 uHzB; uniform vec4 uHzK; uniform float uHzStart;
float lsHazeAmt(vec3 w) {
  float d = max(distance(w, source_camera) - uHzStart, 0.0);
  float h = exp(-max(w.y, 0.0) * uHzK.y);
  return 1.0 - exp(-d * uHzK.x * (0.3 + 0.7 * h));
}
vec3 lsHazeCol(vec3 w) { return mix(uHzA, uHzB, smoothstep(uHzK.z, uHzK.w, -w.z) * (0.55 + 0.45 * exp(-max(w.y, 0.0) * 0.08))); }

      
float lsH(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float lsN(vec2 p) { vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(lsH(i), lsH(i + vec2(1, 0)), u.x), mix(lsH(i + vec2(0, 1)), lsH(i + vec2(1, 1)), u.x), u.y); }
float lsF(vec2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 4; i++) { s += a * lsN(p); p = mat2(vec2(1.6,1.2),vec2(-1.2,1.6)) * p + 7.1; a *= 0.5; } return s / 0.9375; }

      
void vertex(){source_camera=CAMERA_POSITION_WORLD;vec2 sourceUv=vec2(UV.x,1.0-UV.y); vUv = sourceUv; vSeed = CUSTOM0.x; vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0); vLsW = w.xyz; POSITION = PROJECTION_MATRIX * VIEW_MATRIX * w; }
void fragment(){vec4 sourceOutput=vec4(0.0);
        vec2 p = vUv * vec2(1.6, 3.0); float t = uTime * 0.35 + vSeed * 7.0;
        vec2 q = vec2(lsF(p + vec2(0.0, -t)), lsF(p * 1.3 + vec2(3.1, -t * 1.3)));
        float n = lsF(p * 1.1 + q * 1.4 + vec2(vSeed * 3.0, -t * 0.8));
        float edge = smoothstep(0.0, 0.3, vUv.x) * smoothstep(1.0, 0.7, vUv.x) * smoothstep(0.0, 0.12, vUv.y) * smoothstep(1.0, 0.35, vUv.y);
        float a = smoothstep(0.4, 0.85, n) * edge * 0.6;
        vec3 c = mix(uCol, lsHazeCol(vLsW), 0.3);
        sourceOutput = vec4(c, a);
      ALBEDO=sourceOutput.rgb;ALPHA=sourceOutput.a;}
