// Original caustic filaments/wet band, adapted to Godot premultiplied blending.
shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled,blend_premul_alpha,depth_draw_never;

uniform float uTime;
uniform vec3 uSunDir;
uniform vec3 uSunLight;
uniform vec4 uStripK;      // x caustic strength, y wet-band darkening
varying vec3 vP;
varying vec3 vPw;
varying vec3 vN;
varying vec4 vInfo;
vec2 hash22s(vec2 p) { vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973)); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.xx + p3.yz) * p3.zy); }
// distance to the nearest cell border of a jittered grid whose points wander (F2 − F1): 0 on the borders
float cellEdge(vec2 p, float t) {
  vec2 i = floor(p), f = fract(p);
  float d1 = 8.0, d2 = 8.0;
  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec2 g = vec2(float(x), float(y));
    vec2 h = hash22s(i + g);
    vec2 o = 0.5 + 0.4 * sin(t * (0.7 + 0.6 * h) + 6.2831 * h.yx);
    float d = length(g + o - f);
    if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) { d2 = d; }
  }
  return d2 - d1;
}
// focused-light network of a rippled surface (mean ≈ 1)
float caustic(vec2 p, float t, float blur) {
  vec2 w = p + 0.3 * vec2(sin(p.y * 1.1 + t * 0.8), sin(p.x * 0.9 - t * 0.7));
  float c1 = 1.0 - smoothstep(0.0, 0.08 + blur, cellEdge(w * 2.2, t * 1.2));
  float c2 = 1.0 - smoothstep(0.0, 0.08 + blur * 1.4, cellEdge(w * 3.3 + 7.3, t * 1.5));
  return (c1 * 0.8 + c2 * 0.5 + c1 * c2 * 1.4) * 2.4;
}
float swellH(vec2 p, float t) {
  return 0.45 * sin(dot(p, vec2(0.110, 0.047)) + t * 0.95) + 0.35 * sin(dot(p, vec2(-0.052, 0.097)) + t * 1.13 + 1.7) + 0.20 * sin(dot(p, vec2(0.173, -0.141)) + t * 1.61 + 4.1);
}

void vertex(){vP=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vN=normalize(mat3(MODEL_MATRIX)*NORMAL);vInfo=CUSTOM0;float h=max(vP.y+1.6,0.0);vec2 k=uSunDir.xz/max(uSunDir.y,0.08);vPw=vec3(vP.x+k.x*h,-1.6,vP.z+k.y*h);}
void fragment(){
  vec3 n = normalize(vN);
  float h = vP.y - -1.600;
  // cosine between the face and the light bouncing up off the water (away from the sun)
  float facing = max(dot(n, vec3(uSunDir.x, -uSunDir.y, uSunDir.z)), 0.0);
  vec3 add = vec3(0.0);
  if (facing > 0.002) {
    float lit = 1.0;
    if (lit > 0.002) {
      float c = caustic(vPw.xz, uTime, 0.02 + max(h, 0.0) * 0.1);
      float fall = exp(-max(h, 0.0) * 0.8) * smoothstep(-0.02, 0.05, h);
      vec3 alb = max(vInfo.rgb, vec3(0.12));
      add = uSunLight * alb * (c * 0.06) * facing * lit * fall * uStripK.x;
    }
  }
  float mul = 1.0;
  if (vInfo.a > 0.5) {
    // hull in the water: the line bobs with the swell; a dark wet band above it, freshest right at the line
    float wl = -1.600 + 0.035 * swellH(vP.xz, uTime) + 0.018 * sin(uTime * 1.7 + (vP.x + vP.z) * 1.3);
    float top = 0.22 + 0.07 * sin(vP.x * 1.7 + vP.z * 1.3) + 0.04 * sin(vP.x * 5.1 - vP.z * 4.3);
    float band = smoothstep(wl + top, wl + top - 0.14, vP.y);
    float fresh = smoothstep(wl + 0.05, wl + 0.004, vP.y);
    mul = 1.0 - uStripK.y * (0.75 * band + 0.25 * fresh);
    add *= 1.0 - 0.5 * band;
  }
  ALBEDO=vec3(0.0);EMISSION=add;ALPHA=clamp(1.0-mul,0.0,1.0);
PREMUL_ALPHA_FACTOR=1.0;}
