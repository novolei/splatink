// Generated from source material boss_steel; original authored color/detail equations.
shader_type spatial;
render_mode diffuse_lambert,cull_disabled;
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

  float cls = floor(vM.x + 0.5), pid = floor(vM.y + 0.5), ao = vM.z, ex = floor(vM.w + 0.5);
  vec3 P = vB; vec2 uv = vU;
  float n1 = bFbm(P * 0.9 + 1.7), n2 = bFbm(P * 5.5 + 3.1), n3 = bNoise(P * 29.0);
  bool inner = !FRONT_FACING && cls < 1.5 && (pid < 4.5 || cls > 0.5);
  bool backLeaf = !FRONT_FACING && cls < 0.5 && pid > 4.5;
  vec3 c = vec3(0.5);
  vec3 RUST = vec3(0.24, 0.066, 0.02), RUSTD = vec3(0.065, 0.02, 0.008), PRIMER = vec3(0.25, 0.24, 0.215), BARE = vec3(0.3, 0.32, 0.34);
  if (cls < 1.5) {
    // ---------------- painted panels / frame
    vec3 paint = cls < 0.5 ? vec3(0.04, 0.26, 0.23) : vec3(0.022, 0.1, 0.095);
    vec3 faded = cls < 0.5 ? vec3(0.2, 0.46, 0.41) : vec3(0.07, 0.2, 0.19);
    float fade = smoothstep(0.35, 0.8, n1) * 0.55 + smoothstep(-0.2, 1.6, P.y - 3.3) * 0.35;
    c = mix(paint, faded, clamp(fade, 0.0, 1.0));
    c *= 0.9 + 0.2 * bNoise(P * 3.0);
    bool wall = cls < 0.5 && (pid < 4.5 || pid > 4.5 && pid < 8.5);
    float H = 2.36;
    // wear: bottom, top rail line, edges of panels, torn petals, flaps' rim
    float edgeW = 0.0;
    if (wall) edgeW = max(smoothstep(0.55, 0.0, uv.y), smoothstep(H - 0.25, H, uv.y) * 0.7);
    if (cls > 0.5) edgeW = 0.55;
    if (ex > 1.5) edgeW = 1.0;
    // stencils (paint on top of paint: chipped with it)
    float st = 0.0; vec3 stC = vec3(0.8, 0.77, 0.66);
    if (wall) {
      vec2 a = vec2(-1.0);
      if (pid < 1.5) a = vec2((uv.x - 1.2) / 4.0, (uv.y - 1.24) / 1.0);                 // left wall logo
      else if (pid < 2.5) a = vec2((uv.x - 0.65) / 4.0, (uv.y - 1.24) / 1.0);            // right wall logo
      if (a.x > 0.0 && a.x < 1.0 && a.y > 0.0 && a.y < 1.0) st = texture(uStencil, vec2(a.x, 0.5 + a.y * 0.5)).a;
      if (pid > 2.5 && pid < 3.5) {                                                      // rear wall: code + placard
        vec2 b = vec2((uv.x - 0.12) / 1.2, (uv.y - 1.72) / 0.6);
        if (b.x > 0.0 && b.x < 1.0 && b.y > 0.0 && b.y < 1.0) st = texture(uStencil, vec2(b.x * 0.5, b.y * 0.5)).a;
        vec2 d = vec2((uv.x - 1.42) / 0.62, (uv.y - 0.92) / 0.62);
        if (d.x > 0.0 && d.x < 1.0 && d.y > 0.0 && d.y < 1.0) { vec4 pl = texture(uStencil, vec2(0.5 + d.x * 0.25, d.y * 0.5)); st = pl.a; stC = mix(vec3(0.85, 0.62, 0.05), vec3(0.03), pl.r); }
      }
      if (pid > 4.5 && pid < 6.5) {                                                      // door leaves: code
        vec2 b = vec2((uv.x - 0.08) / 1.05, (uv.y - 1.62) / 0.52);
        if (b.x > 0.0 && b.x < 1.0 && b.y > 0.0 && b.y < 1.0) st = texture(uStencil, vec2(b.x * 0.5, b.y * 0.5)).a;
      }
      if (pid > 1.5 && pid < 2.5) {                                                      // right wall: sprayed warning
        vec2 d = vec2((uv.x - 2.2) / 1.35, (uv.y - 0.3) / 0.68);
        if (d.x > 0.0 && d.x < 1.0 && d.y > 0.0 && d.y < 1.0) { float sp = texture(uStencil, vec2(0.75 + d.x * 0.25, d.y * 0.5)).a; if (sp > 0.02) { st = sp; stC = vec3(0.62, 0.03, 0.02); } }
      }
    }
    if (!backLeaf) c = mix(c, stC, st * 0.92);
    // chips: concentrated where it's worn (bottom, top rail, frame edges, torn metal, big damage patches);
    // primer ring → bare steel → rust core
    float macro = bFbm(P * 0.5 + 4.0);
    float wear = clamp(edgeW * 0.85 + smoothstep(0.58, 0.8, macro) * 0.75 + (ex > 1.5 ? 0.6 : 0.0), 0.0, 1.0);
    float chipN = bFbm(P * 3.6 + 3.1) * 0.62 + bNoise(P * 12.0 + 1.3) * 0.38;
    float th = mix(0.82, 0.47, wear);
    float chip = smoothstep(th, th + 0.015, chipN), primer = smoothstep(th - 0.035, th - 0.02, chipN) - chip;
    float rustCore = smoothstep(th + 0.05, th + 0.1, chipN + 0.05 * n1);
    c = mix(c, PRIMER, primer * 0.85);
    c = mix(c, mix(BARE, RUST, 0.55 + 0.45 * n3), chip);
    c = mix(c, mix(RUST, RUSTD, n3), rustCore);
    // rust streaks running down from the top rail / seams
    if (wall && pid < 3.5) {
      float col = floor(uv.x * 6.0 + 0.5 * bN2(vec2(uv.y * 0.7, pid)));
      float len = 0.35 + 1.7 * bH2(vec2(col, pid * 3.1));
      float fromTop = H - uv.y;
      float streak = bN2(vec2(uv.x * 22.0, uv.y * 0.9 + pid)) * bN2(vec2(uv.x * 7.0, uv.y * 0.4));
      float sm = smoothstep(0.25, 0.55, streak) * smoothstep(len, len * 0.15, fromTop);
      c = mix(c, mix(RUST, vec3(0.34, 0.12, 0.04), n3), sm * 0.75);
      bRough = mix(bRough, 0.8, sm);
    }
    // grime + algae along the bottom
    float grime = wall ? smoothstep(0.85, 0.0, uv.y) * (0.55 + 0.45 * n1) : 0.0;
    c = mix(c, vec3(0.045, 0.05, 0.025), grime * 0.7);
    c = mix(c, vec3(0.05, 0.1, 0.03), smoothstep(0.35, 0.0, uv.y) * step(0.5, n2) * (wall ? 0.6 : 0.0));
    bRough = mix(0.5, 0.85, max(max(chip * 0.4, rustCore), grime));
    bMetal = chip * (1.0 - rustCore) * 0.65;
    bBumpH = (chip * 0.0012 + rustCore * 0.0015 * n3 + n3 * 0.0006) ;
    // ink drips down the walls from the roof hatches + pooled along the top rail
    if (wall && pid < 2.5) {
      float cw = uv.x * 3.2; float ci = floor(cw); float cf = fract(cw);
      float h0 = bH2(vec2(ci, pid + 9.0));
      float L = (0.25 + 1.4 * h0 * h0) * uDrip * (0.92 + 0.08 * sin(uTime * 0.7 + h0 * 20.0));
      float fromTop = H - uv.y;
      float w = 0.06 + 0.05 * h0;
      float xc = 0.3 + 0.4 * bH2(vec2(ci, pid + 3.0));
      float drip = step(0.35, h0) * (1.0 - smoothstep(w * 0.8, w, abs(cf - xc) * 3.2 / (1.0 + 0.8 * smoothstep(L - 0.12, L, fromTop)))) * step(fromTop, L);
      float pool = smoothstep(0.16, 0.05, fromTop) * uDrip * smoothstep(0.3, 0.6, bN2(vec2(uv.x * 2.0, pid)));
      float ink = max(drip, pool);
      c = mix(c, uInk * 0.55, ink);
      bRough = mix(bRough, 0.08, ink); bMetal = mix(bMetal, 0.0, ink); bCC = max(bCC, ink); bCCR = 0.04;
    }
    // phase-2+ glowing fracture around the tear flap outline (light from the abdomen leaks through)
    if (wall && pid < 2.5) {
      float uc = pid < 1.5 ? 3.145 : 2.715;
      vec2 d = vec2((uv.x - uc) / 0.535, (uv.y - 1.68) / 0.55);
      float r = pow(pow(abs(d.x), 4.0) + pow(abs(d.y), 4.0), 0.25);
      float ang = atan(d.y, d.x);
      float jag = 1.0 + 0.1 * sin(ang * 7.0 + (pid < 1.5 ? 1.0 : -1.0)) + 0.06 * sin(ang * 13.0 + 2.0) + 0.05 * sin(ang * 23.0);
      float edge = abs(r - jag) * 0.5;
      float near = exp(-max(0.0, r - jag) * 2.2);
      float vor = bVoro(uv * 2.6 + 11.0);
      float cracks = bLine(vor, 0.035) * near * smoothstep(0.2, 0.9, bN2(uv * 1.7)) * step(jag, r);
      float rim = bLine(edge, 0.018);
      float pulse = 0.75 + 0.25 * sin(uTime * 3.0 + uv.x * 2.0);
      float g = (rim + cracks) * uCrack * pulse;
      c = mix(c, vec3(0.01), g * 0.8);
      bEmis += uWeak * g * (2.5 + 3.0 * uOpen);
    }
    if (backLeaf) c *= 0.55;
    if (inner) { c = vec3(0.05, 0.04, 0.032) * (0.7 + 0.6 * n1); bRough = 0.9; bMetal = 0.0; bCC = 0.0; bEmis += uWeak * 0.12 * uOpen; }
    c *= mix(1.0, ao, 0.8);
  } else if (cls < 2.5) {
    // bare rusty steel (bars, chain, castings)
    float r = smoothstep(0.35, 0.7, n2 + 0.15 * n3);
    c = mix(BARE * (0.8 + 0.3 * n3), mix(RUST, RUSTD, n3), r);
    if (pid > 0.5 && pid < 1.5) c = mix(c, vec3(0.03, 0.09, 0.085), 0.6);     // castings: painted-over
    bRough = mix(0.38, 0.85, r); bMetal = mix(0.85, 0.1, r); bBumpH = r * n3 * 0.002;
  } else if (cls < 3.5) {
    // brass nozzle with verdigris; bore glows while the cannon charges
    vec3 brass = vec3(0.5, 0.29, 0.06);
    float vg = smoothstep(0.55, 0.75, n2 + 0.2 * (1.0 - ao));
    c = mix(brass * (0.85 + 0.3 * n3), vec3(0.09, 0.26, 0.2), vg);
    bRough = mix(0.28, 0.75, vg); bMetal = mix(1.0, 0.0, vg);
    if (pid > 0.5) { c = vec3(0.02); bMetal = 0.0; bEmis += uInk * (0.4 + 14.0 * uCannon) + vec3(3.0) * uCannon * uCannon; }
    else { float fl = uCannon * (0.75 + 0.25 * sin(uTime * 30.0)); bEmis += uInk * 0.6 * fl; bRimC += uInk * 2.5 * fl; bRimP = 2.0; }
  } else if (cls < 5.5) {
    // barnacles: chalky plates, purple-grey, a little algae
    float pl = bNoise(P * 60.0);
    c = mix(vec3(0.66, 0.61, 0.55), vec3(0.25, 0.19, 0.26), smoothstep(0.3, 0.8, n3 * 0.7 + pl * 0.5));
    c = mix(c, vec3(0.08, 0.14, 0.05), smoothstep(0.7, 0.85, n2) * 0.6);
    bRough = 0.92; bMetal = 0.0; bBumpH = pl * 0.004;
  } else if (cls < 6.5) {
    // weathered planks (deck along the length, crate boards)
    float pc = pid < 0.5 ? uv.x * 5.0 : P.y * 9.0 + P.x * 0.1;
    float seam = bLine(abs(fract(pc) - 0.5) - 0.47, 0.02);
    float grain = bNoise(vec3(fract(pc) * 3.0, P.y * 40.0 + P.z * 40.0, floor(pc)));
    vec3 wood = pid < 0.5 ? vec3(0.13, 0.09, 0.055) : vec3(0.33, 0.2, 0.09);
    c = mix(wood * (0.75 + 0.45 * grain), vec3(0.23, 0.22, 0.2), smoothstep(0.5, 0.8, n1) * 0.5);
    if (pid > 1.5) c = mix(c, BARE * 0.6, 0.8);
    c *= 1.0 - seam * 0.6; bRough = 0.85; bMetal = 0.0; bBumpH = -seam * 0.004 + grain * 0.0008;
  } else if (cls < 7.5) {
    // ink barrels: painted drums full of the boss's ink
    float band = step(0.9, abs(fract(P.y * 2.0 + 0.5) - 0.5) * 2.0);
    c = mix(uInk * 0.5, vec3(0.08), band); c = mix(c, RUST, smoothstep(0.7, 0.8, n2));
    bRough = 0.4; bMetal = 0.2; bCC = 0.6; bCCR = 0.1;
  } else {
    // cast-iron anchor
    float r = smoothstep(0.3, 0.6, n2);
    c = mix(vec3(0.045, 0.045, 0.05), mix(RUST, RUSTD, n3), r * 0.8);
    bRough = 0.7; bMetal = mix(0.6, 0.0, r); bBumpH = n3 * 0.003;
  }
  // phase-3 heat: steel near the tears glows faintly
  bEmis += uWeak * uHeat * 0.05 * smoothstep(0.6, 1.0, n1);
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
