// Generated from source material boss_cara; original authored color/detail equations.
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

  float cls = floor(vM.x + 0.5), tone = vM.y, ex = vM.w;
  vec3 P = vB;
  float tub = bNoise(P * 9.0), pit = bNoise(P * 34.0 + 5.0), mot = bFbm(P * 3.3 + 2.0);
  vec3 TOP = vec3(0.1, 0.01, 0.022), MID = vec3(0.5, 0.055, 0.04), UNDER = vec3(0.86, 0.6, 0.38), TIP = vec3(0.018, 0.01, 0.016);
  float tn = clamp(tone + (tub - 0.5) * 0.22 + (mot - 0.5) * 0.18, 0.0, 1.0);
  vec3 c = mix(TOP, MID, smoothstep(0.12, 0.5, tn));
  c = mix(c, UNDER, smoothstep(0.58, 0.95, tn));
  c = mix(c, c * 1.55 + vec3(0.02, 0.005, 0.0), smoothstep(0.62, 0.82, tub) * (1.0 - tn) * 0.7);   // tubercle crowns
  c *= 1.0 - 0.32 * smoothstep(0.72, 0.9, bNoise(P * 15.0 + 11.0)) * (1.0 - tn);                     // speckles
  float wet = smoothstep(0.35, 0.7, bFbm(P * 1.6 + 7.0));
  bRough = mix(0.62, 0.34, wet); bCC = mix(0.35, 1.0, wet); bCCR = mix(0.22, 0.05, wet); bSheen = 0.6; bSheenC = vec3(1.0, 0.45, 0.35);
  c *= mix(0.86, 1.0, wet);                                                                             // dry patches go chalky-dull
  bBumpH = tub * 0.006 - smoothstep(0.75, 0.9, pit) * 0.0025 + bNoise(P * 70.0) * 0.0006;
  float legSeg = ex >= 9.5 ? floor(ex) : -1.0, lt = fract(ex);
  if (legSeg > 0.0) {
    // hermit-crab leg bands at the joints
    float band = legSeg < 10.5 ? smoothstep(0.86, 0.9, lt) : legSeg < 11.5 ? (1.0 - smoothstep(0.06, 0.1, lt)) + smoothstep(0.47, 0.5, lt) * (1.0 - smoothstep(0.55, 0.58, lt)) * 0.8 : 0.0;
    c = mix(c, vec3(0.78, 0.42, 0.3), band * 0.85);
  }
  if (cls > 0.5 && cls < 1.5) {
    // spines + dactyls: dark lacquered tips
    float k = legSeg > 11.5 ? smoothstep(0.25, 0.85, lt) : 0.75;
    c = mix(c * 0.6, TIP, k); bRough = 0.28; bCCR = 0.04;
  } else if (cls > 1.5 && cls < 2.5) {
    c = vec3(0.83, 0.76, 0.6) * (0.85 + 0.2 * tub); bRough = 0.3; bSheen = 0.2;       // teeth / molars
  } else if (cls < 0.5) {
    c = mix(c, TIP, smoothstep(0.91, 0.985, tone));                                     // claw fingers: lacquered black tips
  } else if (cls > 2.5) {
    float pl = bNoise(P * 60.0);
    c = mix(vec3(0.62, 0.58, 0.52), vec3(0.25, 0.19, 0.26), smoothstep(0.3, 0.8, pit * 0.7 + pl * 0.5)); bRough = 0.9; bCC = 0.1; bSheen = 0.0; bBumpH = pl * 0.004;
  }
  if (ex > 1.5 && ex < 3.5) { float v = ex - 2.0; c = mix(c, UNDER * 0.8, step(0.5, fract(v * 7.0)) * 0.6); }           // antenna rings
  // boss ink: dipped feet + splashes on the claws
  float inkM = 0.0;
  if (legSeg > 0.0) inkM = smoothstep(0.42, 0.3, P.y + (bNoise(P * 7.0) - 0.5) * 0.18 - smoothstep(0.6, 0.9, bNoise(vec3(P.x * 40.0, P.y * 3.0, P.z * 40.0))) * 0.25);
  inkM = max(inkM, smoothstep(0.78, 0.84, bFbm(P * 2.6 + 9.0)) * uDrip * step(0.5, 1.0 - step(9.5, ex)) * step(cls, 0.5));
  c = mix(c, uInk * 0.32, inkM); bRough = mix(bRough, 0.06, inkM); bCCR = mix(bCCR, 0.03, inkM); bSheen *= 1.0 - inkM;
  // crusher charge veins (slam telegraph) — ink colour
  float cw = (ex > 0.2 && ex < 1.5) ? ex : 0.0;
  if (cw > 0.0) {
    // a few fat fissures that light up (not a net): ridged noise at low frequency, masked to the upper carapace
    float rv = abs(bNoise(P * 2.3 + 5.0) * 2.0 - 1.0);
    float veins = bLine(rv, 0.03) * smoothstep(0.35, 0.65, bNoise(P * 1.1 + 2.0)) + 0.4 * bLine(abs(bNoise(P * 5.5 + 9.0) * 2.0 - 1.0), 0.02) * smoothstep(0.6, 0.8, bNoise(P * 1.7));
    float g = uGlowL * cw;
    c = mix(c, vec3(0.02, 0.01, 0.02), g * veins * 0.8);
    bEmis += uInk * (veins * 10.0 + 0.03) * g + vec3(1.0) * veins * g * g * 0.6; bRimC += uInk * 0.5 * g;
  }
  // phase cracks: carapace fracture lines glowing in the weak-point colour
  if (uCrack > 0.001 && cls < 0.5) {
    float vor = bVoro(P.xz * 1.7 + P.y * 1.1) + bVoro(P.yz * 1.9 + 3.0) * 0.5;
    float cr = bLine(vor, 0.03) * smoothstep(0.55, 0.3, tone) * smoothstep(0.45, 0.65, bFbm(P * 1.2));
    float pulse = 0.7 + 0.3 * sin(uTime * 3.2 + P.y * 3.0);
    c = mix(c, vec3(0.01), cr * uCrack);
    bEmis += uWeak * cr * uCrack * pulse * (2.2 + 2.5 * uOpen);
  }
  // enrage: hotter, redder, heat shimmer on the rims
  c = mix(c, c * vec3(1.35, 0.55, 0.5), uEnrage * 0.45);
  bRimC += uWeak * uEnrage * (0.25 + 0.2 * sin(uTime * 6.0));
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
