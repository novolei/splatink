// Generated from source material boss_flesh; original authored color/detail equations.
shader_type spatial;
render_mode diffuse_lambert,cull_back;
uniform sampler2D source_data : filter_nearest, repeat_disable;
uniform vec4 data_min_0;
uniform vec4 data_max_0;
uniform vec4 data_min_1;
uniform vec4 data_max_1;
uniform vec4 data_min_2;
uniform vec4 data_max_2;
uniform vec4 data_min_3;
uniform vec4 data_max_3;
uniform vec4 data_min_4;
uniform vec4 data_max_4;
uniform vec4 data_min_5;
uniform vec4 data_max_5;
uniform vec4 data_min_6;
uniform vec4 data_max_6;
uniform vec4 data_min_7;
uniform vec4 data_max_7;
uniform vec4 data_min_8;
uniform vec4 data_max_8;
uniform vec4 data_min_9;
uniform vec4 data_max_9;
uniform vec4 data_min_10;
uniform vec4 data_max_10;
uniform vec4 data_min_11;
uniform vec4 data_max_11;
uniform vec3 skin_color=vec3(1.0,0.6939,0.5395);
uniform float hit_flash=0.0;
uniform float rim_strength=0.0;
uniform sampler2D uStencil : filter_linear_mipmap;

uniform float uTime = 0.0; uniform vec3 uInk = vec3(0.02842604,0.10461648,1.0); uniform vec3 uWeak = vec3(1.0,0.25415209,0.00699541); uniform float uFlash = 0.0; uniform float uWeakFlash = 0.0;
uniform float uCrack = 0.0; uniform float uOpen = 0.0; uniform float uEnrage = 0.0; uniform float uGlowL = 0.0; uniform float uCannon = 0.0; uniform float uBelly = 0.0;
uniform float uEyeMode = 0.0; uniform float uEyeSpin = 0.0; uniform float uEyeGlow = 1.0; uniform float uDrip = 0.6; uniform float uLamp = 1.0; uniform float uHeat = 0.0;
uniform mat4 uContInv = mat4(vec4(1.0,0.0,0.0,0.0),vec4(0.0,0.99280864,-0.11971221,0.0),vec4(0.0,0.11971221,0.99280864,0.0),vec4(0.0,-2.82280004,1.64978785,1.0)); uniform float uAO = 1.0;
varying vec4 vM; varying vec3 vB; varying vec2 vU;
float bHash(vec3 p){ p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3)); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float bNoise(vec3 x){ vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(bHash(i), bHash(i + vec3(1,0,0)), f.x), mix(bHash(i + vec3(0,1,0)), bHash(i + vec3(1,1,0)), f.x), f.y),
             mix(mix(bHash(i + vec3(0,0,1)), bHash(i + vec3(1,0,1)), f.x), mix(bHash(i + vec3(0,1,1)), bHash(i + vec3(1,1,1)), f.x), f.y), f.z); }
float bFbm(vec3 p){ return 0.52 * bNoise(p) + 0.3 * bNoise(p * 2.13 + 7.1) + 0.18 * bNoise(p * 4.37 + 3.7); }
float bH2(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float bN2(vec2 p){ vec2 i = floor(p), f = fract(p); f = f * f * (3.0 - 2.0 * f); return mix(mix(bH2(i), bH2(i + vec2(1, 0)), f.x), mix(bH2(i + vec2(0, 1)), bH2(i + vec2(1, 1)), f.x), f.y); }
// voronoi border distance (F2 − F1), 2D
float bVoro(vec2 p){ vec2 n = floor(p), f = fract(p); float d1 = 8.0, d2 = 8.0;
  for (int j = -1; j <= 1; j++) for (int i = -1; i <= 1; i++) { vec2 g = vec2(float(i), float(j)); vec2 o = vec2(bH2(n + g), bH2(n + g + 17.3)); vec2 r = g + o - f; float d = dot(r, r);
    if (d < d1) { d2 = d1; d1 = d; } else if (d < d2) d2 = d; }
  return sqrt(d2) - sqrt(d1); }
float bVoro3(vec3 p){ return bVoro(p.xy * 0.8 + p.z * 0.6) ; }
float bAA(float x){ return max(fwidth(x), 1e-4); }
float bLine(float d, float w){ float a = bAA(d); return 1.0 - smoothstep(w - a, w + a, d); }
vec3 bBumpN(vec3 n, float h, vec3 pos){
  vec3 dpx = dFdx(pos), dpy = dFdy(pos); vec3 r1 = cross(dpy, n), r2 = cross(n, dpx); float det = dot(dpx, r1);
  vec3 g = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2); return abs(det) > 1e-14 ? normalize(abs(det) * n - g) : n; }
vec3 bLin(vec3 c){ return pow(c, vec3(2.2)); }
// bind-space occlusion from the big masses: under the container floor, inside it, under the crab's head
float bMassAO(vec3 p){
  vec3 q = (uContInv * vec4(p, 1.0)).xyz;
  float fx = 1.0 - smoothstep(1.0, 1.9, abs(q.x)), fz = 1.0 - smoothstep(2.8, 3.7, abs(q.z));
  float below = max(0.0, -1.3 - q.y);
  float under = fx * fz * (q.y < -1.25 ? exp(-below * 0.55) : 0.0);
  float inside = step(abs(q.x), 1.2) * step(abs(q.z), 2.98) * step(abs(q.y), 1.28) * (1.0 - smoothstep(2.3, 3.05, q.z));
  float head = (1.0 - smoothstep(0.9, 1.6, abs(p.x))) * smoothstep(1.9, 1.3, p.y) * smoothstep(0.6, 1.6, p.z) * (1.0 - smoothstep(3.2, 4.2, p.z));
  return clamp(1.0 - 0.62 * under - 0.6 * inside - 0.35 * head, 0.12, 1.0);
}

uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);


vec4 source_read(vec2 coord,float slot,vec4 lo,vec4 hi){vec4 a=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0)/24.0))*255.0+0.5);vec4 b=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0+1.0)/24.0))*255.0+0.5);return mix(lo,hi,(a*256.0+b)/65535.0);}
void vertex(){
vec4 d0=source_read(UV2,float(0),data_min_0,data_max_0);
vec4 d2=source_read(UV2,float(2),data_min_2,data_max_2);
vec4 d4=source_read(UV2,float(4),data_min_4,data_max_4);
vB=d0.xyz;vU=d2.xy;vM=d4;


}
void fragment(){
vec4 diffuseColor=vec4(vec3(1.0),1.0); vec3 normal=NORMAL; vec3 vNormal=NORMAL; vec3 vViewPosition=-VERTEX; float roughnessFactor=0.5; float metalnessFactor=0.0; vec3 totalEmissiveRadiance=vec3(0.0);

float bRough = roughnessFactor, bMetal = metalnessFactor, bBumpH = 0.0, bCC = 0.0, bCCR = 0.2, bSheen = 0.0; vec3 bEmis = vec3(0.0); vec3 bSheenC = vec3(1.0);
  float bAO = mix(1.0, bMassAO(vB) * mix(1.0, vM.z, 0.85), uAO);
  vec3 bRimC = vec3(0.0); float bRimP = 3.0;

  float cls = floor(vM.x + 0.5), seg = vM.y;
  vec3 P = vB;
  float mot = bFbm(P * 3.8 + 1.0), vein = 1.0 - abs(bNoise(P * 4.5) * 2.0 - 1.0), vein2 = 1.0 - abs(bNoise(P * 9.0 + 4.0) * 2.0 - 1.0);
  float vm = smoothstep(0.9, 0.97, vein) + 0.5 * smoothstep(0.93, 0.985, vein2);
  vec3 PALE = vec3(0.74, 0.4, 0.38), PURP = vec3(0.26, 0.07, 0.17);
  vec3 c = mix(PALE, PURP, smoothstep(0.45, 0.85, mot) * 0.6);
  c = mix(c, PURP * 0.8, vm * 0.25);
  if (cls > 0.5 && cls < 1.5) {
    float fold = sin(P.z * 9.0 + P.y * 3.0);
    c = mix(PALE * 1.05, PURP, smoothstep(0.5, 0.85, mot) * 0.35) * (1.0 - 0.35 * smoothstep(0.7, 1.0, fold));
    vm = smoothstep(0.7, 1.0, fold) * 0.9 + 0.15 * vm; bBumpH = fold * 0.006;
  }
  if (cls > 2.5) c = mix(c, vec3(0.3, 0.08, 0.14), 0.4);
  if (cls < 0.5 && seg > 0.5) c = mix(c, vec3(0.12, 0.03, 0.07), 0.7);                 // joint membranes: dark, recessed
  if (cls > 1.5 && cls < 2.5) {
    // hermit-crab abdomen: soft transverse folds, not veins
    vec3 q = (uContInv * vec4(P, 1.0)).xyz;
    float fold = sin(q.z * 7.5 + sin(q.x * 2.0) * 0.6);
    float groove = smoothstep(0.75, 1.0, fold);
    c = mix(PALE * 0.95, PURP * 0.9, smoothstep(0.4, 0.8, mot) * 0.45);
    c *= 1.0 - 0.45 * groove;
    vm = groove * 0.8 + 0.2 * vm;
    bBumpH = fold * 0.01;
  }
  c *= mix(1.0, vM.z, 0.35);
  bRough = 0.42; bCC = 0.85; bCCR = 0.22; bSheen = 1.0; bSheenC = vec3(1.0, 0.5, 0.5) * 0.7;
  bBumpH += mot * 0.004 + vm * 0.0015;
  // fake subsurface: a little self-lit warmth
  bEmis += c * 0.07;
  float pulse = 0.8 + 0.2 * sin(uTime * 4.0 + P.z * 2.0);
  if (cls > 0.5 && cls < 1.5) bEmis += uWeak * uBelly * (0.8 + 4.0 * vm) * pulse * (1.0 + 2.0 * uWeakFlash);
  if (cls > 1.5 && cls < 2.5) bEmis += uWeak * (uOpen * (0.22 + 3.2 * vm + 0.5 * smoothstep(0.55, 0.9, mot)) * pulse + uCrack * 0.18) * (1.0 + 2.0 * uWeakFlash);
  if (cls > 2.5) bEmis += uInk * uCannon * (1.2 + 3.0 * vm);
  if (cls > 0.5 && cls < 1.5) c = mix(c, uWeak * 0.45, 0.3 * uBelly);
  if (cls > 1.5 && cls < 2.5) c = mix(c, uWeak * 0.25 + vec3(0.05, 0.0, 0.02), 0.45 * min(1.0, uOpen));
  diffuseColor.rgb = c;

  bEmis += vec3(1.0, 0.97, 0.92) * uFlash * 0.07; bRimC += vec3(1.0, 0.97, 0.92) * uFlash * 1.1; bRimP = min(bRimP, 2.0);
roughnessFactor = bRough;
metalnessFactor = bMetal;
normal = bBumpN(normal, bBumpH, -vViewPosition);
totalEmissiveRadiance += bEmis + bRimC * pow(1.0 - abs(dot(normal, normalize(vViewPosition))), bRimP);
ALBEDO=max(diffuseColor.rgb,vec3(0.0)); ROUGHNESS=clamp(roughnessFactor,0.04,1.0); METALLIC=clamp(metalnessFactor,0.0,1.0); NORMAL=normal; SPECULAR=0.5;

AO=clamp(bAO,0.0,1.0);CLEARCOAT=clamp(bCC,0.0,1.0);CLEARCOAT_ROUGHNESS=bCCR;

EMISSION=totalEmissiveRadiance+vec3(hit_flash)+ALBEDO*rim_strength*pow(1.0-clamp(dot(normal,VIEW),0.0,1.0),3.2);

float hemi_mix=clamp((INV_VIEW_MATRIX[0].y*normal.x+INV_VIEW_MATRIX[1].y*normal.y+INV_VIEW_MATRIX[2].y*normal.z)*0.5+0.5,0.0,1.0);EMISSION+=ALBEDO*(1.0-METALLIC)*mix(hemi_ground,hemi_sky,hemi_mix)*AO;
}
