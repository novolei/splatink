// Generated from source material cloth; original authored color/detail equations.
shader_type spatial;
render_mode diffuse_lambert,cull_back,ambient_light_disabled;
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
uniform vec4 uIwRim=vec4(0.075,0.08125,0.09375,3.4);
uniform vec3 uIwRimL=vec3(0.2981424,0.5962848,-0.745356);
uniform vec3 uIwFill=vec3(0.0);
uniform bool native_rim_world=false;
uniform vec4 uHurt = vec4(0.0,0.0,0.0,0.0); uniform float uHurtSeed = 0.0; uniform vec3 uFlash = vec3(0.0,0.0,0.0);
varying vec3 vBindPos; varying float vEx;

float iwHash(vec3 p){ p = fract(p * 0.3183099 + vec3(0.1, 0.2, 0.3)); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float iwNoise(vec3 x){ vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
  return mix(mix(mix(iwHash(i), iwHash(i + vec3(1,0,0)), f.x), mix(iwHash(i + vec3(0,1,0)), iwHash(i + vec3(1,1,0)), f.x), f.y),
             mix(mix(iwHash(i + vec3(0,0,1)), iwHash(i + vec3(1,0,1)), f.x), mix(iwHash(i + vec3(0,1,1)), iwHash(i + vec3(1,1,1)), f.x), f.y), f.z); }
float iwFbm(vec3 p){ return 0.56 * iwNoise(p) + 0.29 * iwNoise(p * 2.07 + 7.1) + 0.15 * iwNoise(p * 4.31 + 3.7); }
float iwBand(float x, float a, float b){ float w = max(fwidth(x) * 0.8, 1e-4); return smoothstep(a - w, a + w, x) - smoothstep(b - w, b + w, x); }
float iwHash2(vec2 p){ return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123); }
float iwAAw(float d){ return max(fwidth(d), 1e-5); }
// filled SDF (d < 0 inside) and stroke of half-width hw, both antialiased
float iwFill(float d){ float w = iwAAw(d); return 1.0 - smoothstep(-w, w, d); }
float iwStroke(float d, float hw){ float w = iwAAw(d); return 1.0 - smoothstep(hw - w, hw + w, abs(d)); }
// 1 while a pattern of spatial period P (same units as coord) is resolvable (>= ~3 px), fading to 0 when sub-pixel
float iwLod(float coord, float P){ float px = fwidth(coord) / P; return 1.0 - smoothstep(0.22, 0.55, px); }
// dashed stitch along s (period P, duty 0..1)
float iwDash(float s, float P, float duty){ float x = s / P; float f = fract(x); float w = min(max(fwidth(x), 1e-4) * 1.2, 0.3); return smoothstep(0.0, w, f) * (1.0 - smoothstep(duty - w, duty, f)); }
float iwSdBox(vec2 p, vec2 b, float r){ vec2 q = abs(p) - b + r; return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r; }
float iwSdSeg(vec2 p, vec2 a, vec2 b){ vec2 pa = p - a, ba = b - a; float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0); return length(pa - ba * h); }
float iwSmin(float a, float b, float k){ float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0); return mix(b, a, h) - k * h * (1.0 - h); }


vec3 iwBumpN(vec3 n, float h, vec3 pos){
  vec3 dpx = dFdx(pos), dpy = dFdy(pos);
  vec3 r1 = cross(dpy, n), r2 = cross(n, dpx);
  float det = dot(dpx, r1);
  vec3 g = sign(det) * (dFdx(h) * r1 + dFdy(h) * r2);
  return abs(det) > 1e-14 ? normalize(abs(det) * n - g) : n;
}


uniform vec3 uTeam = vec3(1.0,0.25415209,0.00699541); uniform vec3 uShirt = vec3(0.89626935,0.8796224,0.83879901); uniform vec3 uShorts = vec3(0.02315337,0.03310477,0.08021982); uniform vec3 uShoe = vec3(0.02315337,0.02624122,0.03688945); uniform vec3 uSole = vec3(0.90466117,0.88792312,0.83879901); uniform vec3 uSock = vec3(0.93011086,0.93011086,0.90466117); uniform vec3 uStrap = vec3(0.03310477,0.03688945,0.04970657); uniform float uPattern = 0.0;
varying vec3 vCloth; varying vec2 vIwUv; varying float vOcc;
float iwLum(vec3 c){ return dot(c, vec3(0.299, 0.587, 0.114)); }
vec3 iwContrast(vec3 c){ return iwLum(c) > 0.42 ? c * 0.74 : c * 1.55 + 0.05; }
// ---- tee fine creases: complements the sculpted fold field of character-outfit.js ------------------------
float iwTeeCrease(vec3 p, float th) {
  float ax = abs(p.x), h = 0.0;
  float side = pow(abs(sin(th * 6.2831)), 2.0);
  float wy = (p.y - 0.705) / 0.0105 + 0.6 * sin(th * 6.2831 * 9.0 + p.y * 40.0);
  h += 0.00032 * side * exp(-pow((p.y - 0.765) / 0.035, 2.0)) * (0.5 + 0.5 * sin(wy * 6.2831));
  vec2 q = vec2(ax - 0.114, p.y - 0.884);
  float r = length(q), ang = atan(q.y, -q.x);
  h += 0.00011 * sin(ang * 17.0 + 1.3 + (p.z > 0.0 ? 0.0 : 2.1) + 2.5 * iwNoise(vec3(ang * 3.0, r * 60.0, p.z * 20.0))) * exp(-pow(r / 0.045, 2.0)) * smoothstep(0.006, 0.02, r) * (0.4 + 0.6 * iwNoise(p * 90.0));
  h += 0.00028 * sin(th * 6.2831 * 23.0 + 2.0 * sin(th * 30.0)) * (1.0 - smoothstep(0.698, 0.726, p.y));
  return h;
}
// ---- tee graphics -------------------------------------------------------------------------------
float iwShirtPattern(vec3 p) {
  float ax = abs(p.x);
  float m = 0.0;
  if (uPattern < 0.5) {            // ringer: no body pattern (trim + big emblem)
    m = 0.0;
  } else if (uPattern < 1.5) {     // double pinstripe
    m = iwBand(p.y, 0.842, 0.852) + iwBand(p.y, 0.866, 0.876);
  } else if (uPattern < 2.5) {     // raglan sleeves + side panel
    float sleeve = smoothstep(0.108, 0.115, ax) * step(0.86, p.y);
    m = max(sleeve, iwBand(ax, 0.098, 0.2) * step(p.y, 0.86) * step(0.74, p.y) * step(abs(p.z + 0.012), 0.05));
  } else {                         // chevron + hem band
    float y0 = 0.925 - 0.55 * ax;
    m = iwBand(p.y - y0, -0.022, 0.0) * step(0.0, p.z);
    m = max(m, iwBand(p.y, 0.726, 0.738));
  }
  return clamp(m, 0.0, 1.0);
}
// ---- outfit patterns 4+ (appended; 0–3 above stay byte-identical so saved looks keep their graphics) -------------
// collar rib / sleeve cuff colours per pattern
vec3 iwTrimCol() {
  float pat = floor(uPattern + 0.5);
  if (pat < 0.5 || pat == 3.0) return uTeam;
  if (pat < 2.5) return iwContrast(uShirt);
  if (pat == 6.0) return uShirt * 0.55;            // camo: dark olive rib
  if (pat == 7.0) return uShirt;                   // dip-dye: undyed collar
  return uTeam;                                    // breton, splatter, jersey, track
}
vec3 iwCuffCol() {
  float pat = floor(uPattern + 0.5);
  if (pat < 0.5 || pat == 3.0) return uTeam;
  if (pat < 2.5) return iwContrast(uShirt);
  if (pat == 4.0 || pat == 5.0) return uShirt;     // breton / splatter: plain cuff
  if (pat == 6.0) return uShirt * 0.55;
  if (pat == 7.0) return uTeam * 0.9;              // dip-dyed ends
  return uTeam;                                    // jersey, track
}
// ink splat stamped on the (roughly cylindrical) torso/sleeve around surface point c: wobbly rim + satellite drops
float iwSplat3(vec3 p, vec3 c, float R, float seed) {
  vec3 d = p - c;
  vec3 n = normalize(vec3(c.x, 0.0, c.z + 0.012));
  vec3 u = normalize(cross(vec3(0.0, 1.0, 0.0), n));
  vec2 q = vec2(dot(d, u), d.y);
  float a = atan(q.y, q.x);
  float wob = 1.0 + 0.13 * sin(5.0 * a + seed) + 0.07 * sin(9.0 * a + seed * 2.3) + 0.04 * sin(15.0 * a + seed * 0.7);
  float sd = length(q) - R * wob;
  for (int k = 0; k < 4; k++) {
    float fk = float(k); float aa = seed * 1.7 + fk * 1.9;
    vec2 o = vec2(cos(aa), sin(aa)) * R * (1.28 + 0.4 * fract(fk * 0.37 + seed));
    sd = min(sd, length(q - o) - R * (0.08 + 0.07 * fract(fk * 0.71 + seed * 0.3)));
  }
  sd = max(sd, abs(dot(d, n)) - 0.045);            // stay on this side of the body
  return iwFill(sd);
}
// athletic block digit (seven segments, rounded); q in digit units (half-width 0.5, half-height 1); SDF in units
float iwDigitSD(vec2 q, int dgt) {
  const int SEG[10] = {0x3F, 0x06, 0x5B, 0x4F, 0x66, 0x6D, 0x7D, 0x07, 0x7F, 0x6F};
  int bits = SEG[clamp(dgt, 0, 9)];
  float d = 1e3;
  if ((bits & 1) != 0) d = min(d, iwSdBox(q - vec2(0.0, 0.86), vec2(0.4, 0.14), 0.07));
  if ((bits & 2) != 0) d = min(d, iwSdBox(q - vec2(0.36, 0.44), vec2(0.14, 0.42), 0.07));
  if ((bits & 4) != 0) d = min(d, iwSdBox(q - vec2(0.36, -0.44), vec2(0.14, 0.42), 0.07));
  if ((bits & 8) != 0) d = min(d, iwSdBox(q - vec2(0.0, -0.86), vec2(0.4, 0.14), 0.07));
  if ((bits & 16) != 0) d = min(d, iwSdBox(q - vec2(-0.36, -0.44), vec2(0.14, 0.42), 0.07));
  if ((bits & 32) != 0) d = min(d, iwSdBox(q - vec2(-0.36, 0.44), vec2(0.14, 0.42), 0.07));
  if ((bits & 64) != 0) d = min(d, iwSdBox(q, vec2(0.36, 0.13), 0.07));
  return d;
}
/** Base colour of shirt-slot fragments (tee body = part 1, sleeves = part 2). */
vec3 iwShirtCol(vec3 p, vec2 uv, float part) {
  if (uPattern < 3.5) return mix(uShirt, uTeam, iwShirtPattern(p));
  float pat = floor(uPattern + 0.5);
  vec3 c = uShirt;
  float ax = abs(p.x), zc = p.z + 0.012;
  if (pat == 4.0) {                        // BRETON: team stripes on the body and around the sleeves, plain yoke
    float sy, P, lo, hi;
    if (part < 1.5) { sy = p.y; P = 0.026; lo = 0.703; hi = 0.938; }
    else { sy = uv.y; P = 0.0235; lo = 0.036; hi = vCloth.z - 0.024; }
    float f = abs(fract((sy - lo) / P) - 0.5);
    float band = iwFill((f - 0.21) * P) * step(lo, sy) * step(sy, hi);
    float m = mix(0.42 * step(lo, sy) * step(sy, hi), band, iwLod(sy, P));
    c = mix(uShirt, uTeam, m);
  } else if (pat == 5.0) {                 // SPLATTER: team ink splats, drips and speckles on a dark tee
    float m = 0.0;
    m = max(m, iwSplat3(p, vec3(0.062, 0.93, 0.072), 0.042, 1.3));
    m = max(m, iwSplat3(p, vec3(-0.058, 0.768, 0.086), 0.025, 4.1));
    m = max(m, iwSplat3(p, vec3(-0.096, 0.952, -0.052), 0.04, 2.2));
    m = max(m, iwSplat3(p, vec3(0.03, 0.742, -0.088), 0.027, 5.7));
    m = max(m, iwSplat3(p, vec3(0.2, 0.872, 0.004), 0.028, 3.3));
    if (part < 1.5 && p.z > 0.0) {
      for (int k = 0; k < 3; k++) {
        float fk = float(k);
        float x0 = 0.04 + 0.019 * fk; float y1 = 0.905 - 0.018 * fk; float y0 = y1 - (0.07 + 0.04 * fract(fk * 0.618 + 0.3));
        float w = 0.0056 - 0.0012 * fk;
        float dd = iwSdSeg(vec2(p.x, p.y), vec2(x0, y0), vec2(x0, y1)) - w * mix(1.0, 0.7, (y1 - p.y) / (y1 - y0));
        dd = min(dd, length(vec2(p.x - x0, (p.y - y0) * 0.85)) - w * 1.5);
        m = max(m, iwFill(dd));
      }
    }
    vec3 cp = p * 75.0; vec3 cell = floor(cp); vec3 fr = fract(cp) - 0.5;
    float rnd = iwHash(cell);
    m = max(m, iwFill((length(fr) - 0.24 * rnd) / 75.0) * step(0.87, rnd) * iwLod(p.y * 75.0, 1.0));
    c = mix(uShirt, uTeam, m);
  } else if (pat == 6.0) {                 // SPLAT CAMO: sand + shadow blobs over olive, with a few team-ink patches
    vec3 q = p * vec3(15.0, 11.0, 15.0);
    float n1 = iwFbm(q + 3.1), n2 = iwFbm(q * 1.15 + 11.7), n3 = iwFbm(q * 0.85 + 27.3);
    c = mix(c, mix(uShirt, vec3(0.8, 0.76, 0.62), 0.5), iwFill(0.585 - n2));
    c = mix(c, uShirt * 0.5, iwFill(0.575 - n1));
    c = mix(c, uTeam, iwFill(0.655 - n3));
  } else if (pat == 7.0) {                 // DIP-DYE: team dye soaked up from the hem with a bleeding waterline
    float wav = 0.011 * sin(uv.x * 6.2831 * 3.0 + 1.1) + 0.024 * (iwFbm(p * 26.0) - 0.5);
    vec3 pale = mix(uTeam, uShirt, 0.42);
    if (part < 1.5) {
      float line = 0.792 + wav;
      float k = 1.0 - smoothstep(line - 0.026, line + 0.004, p.y);
      c = mix(uShirt, mix(pale, uTeam * 0.92, 1.0 - smoothstep(0.7, line, p.y)), k);
      float streak = smoothstep(0.62, 0.9, iwNoise(vec3(p.x * 170.0, p.y * 7.0, p.z * 170.0))) * (1.0 - smoothstep(line, line + 0.04, p.y)) * step(line - 0.004, p.y);
      c = mix(c, mix(uShirt, uTeam, 0.3), streak * 0.65);
    } else {
      float L = vCloth.z;
      float k = smoothstep(L - 0.075 + wav, L - 0.035 + wav, uv.y);
      c = mix(uShirt, mix(pale, uTeam * 0.92, smoothstep(L - 0.05, L, uv.y)), k);
    }
  } else if (pat == 8.0) {                 // JERSEY: team side panels with white piping, V-neck insert, shoulder yoke
    if (part < 1.5) {
      float side = step(0.07, ax);
      float panel = iwFill(abs(zc) - 0.043) * side * step(p.y, 0.95);
      float pipe = iwStroke(abs(zc) - 0.043, 0.0017) * side * step(p.y, 0.95);
      float vneck = iwSdSeg(vec2(ax, p.y), vec2(0.056, 1.0), vec2(0.0, 0.93));
      float v = iwFill(vneck - 0.0085) * step(0.0, p.z);
      float vpipe = iwStroke(vneck - 0.0085, 0.0015) * step(0.0, p.z);
      float yoke = smoothstep(0.962, 0.966, p.y) * (1.0 - v);
      c = mix(c, uTeam, max(max(panel, v), yoke));
      c = mix(c, vec3(0.96), max(pipe, vpipe));
    } else {
      float L = vCloth.z;
      float pipe = iwStroke(uv.y - (L - 0.03), 0.0016);
      c = mix(c, uTeam, smoothstep(0.02, 0.024, uv.y) * (1.0 - smoothstep(0.034, 0.038, uv.y)));   // shoulder yoke continues
      c = mix(c, vec3(0.96), pipe);
    }
  } else {                                 // TRACK TOP: twin white stripes down the sides and sleeves, team yoke
    vec3 sc = vec3(0.95);
    if (part < 1.5) {
      float st = (iwStroke(zc - 0.0085, 0.0032) + iwStroke(zc + 0.0085, 0.0032)) * step(0.07, ax);
      float yoke = smoothstep(0.955, 0.959, p.y);
      c = mix(c, uTeam, yoke);
      c = mix(c, sc, clamp(st, 0.0, 1.0));
      c = mix(c, sc, iwStroke(p.y - 0.957, 0.0014));
    } else {
      float dx = (fract(uv.x + 0.5) - 0.5) * 0.31;
      float st = iwStroke(dx - 0.0085, 0.0032) + iwStroke(dx + 0.0085, 0.0032);
      c = mix(c, uTeam, 1.0 - smoothstep(0.03, 0.034, uv.y));
      c = mix(c, sc, clamp(st, 0.0, 1.0) * smoothstep(0.03, 0.034, uv.y));
    }
  }
  return c;
}

// squid badge: ink splat with a white squid glyph; returns (splat coverage, glyph coverage)
vec2 iwEmblem(vec2 q, float R) {
  float a = atan(q.y, q.x); float r = length(q);
  float wob = 1.0 + 0.1 * sin(5.0 * a + 0.6) + 0.06 * sin(9.0 * a + 2.1) + 0.035 * sin(14.0 * a + 1.0);
  float splat = r - R * wob;
  splat = min(splat, length(q - vec2(R * 1.18, R * 0.62)) - R * 0.13);
  splat = min(splat, length(q - vec2(-R * 1.12, -R * 0.7)) - R * 0.1);
  splat = min(splat, length(q - vec2(R * 0.5, -R * 1.22)) - R * 0.08);
  // glyph: one silhouette — arrowhead mantle with swept fins flowing into a tall body, low oval eyes, four tentacles
  vec2 g = q / R;
  float fins = max(abs(g.x) * 1.02 + (g.y - 0.7) * 0.95, -(g.y - 0.22));
  float body = iwSdBox(g - vec2(0.0, 0.06), vec2(0.17, 0.3), 0.15);
  float glyph = iwSmin(fins, body, 0.08);
  float tent = 1e3;
  for (int i = 0; i < 4; i++) {
    float fi = float(i) - 1.5;
    vec2 tq = g - vec2(fi * 0.1, -0.2);
    tq.x -= fi * 0.1 * smoothstep(0.0, -0.3, tq.y) + 0.03 * sin(tq.y * 13.0 + fi) * smoothstep(-0.05, -0.3, tq.y);
    float w = mix(0.052, 0.03, smoothstep(-0.02, -0.3, tq.y));
    tent = min(tent, iwSdBox(tq - vec2(0.0, -0.15), vec2(w, 0.15), 0.028));
  }
  glyph = iwSmin(glyph, tent, 0.05);
  vec2 e1 = (g - vec2(0.075, 0.0)) / vec2(0.04, 0.062), e2 = (g - vec2(-0.075, 0.0)) / vec2(0.04, 0.062);
  float eyes = (min(length(e1), length(e2)) - 1.0) * 0.04;
  glyph = max(glyph, -eyes);
  return vec2(iwFill(splat), iwFill(glyph * R));
}

uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);
#include "res://assets/shaders/character_lighting.gdshaderinc"
#include "res://assets/shaders/source_cube_uv.gdshaderinc"
#include "res://assets/shaders/character_indirect.gdshaderinc"

vec4 source_read(vec2 coord,float slot,vec4 lo,vec4 hi){vec4 a=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0)/24.0))*255.0+0.5);vec4 b=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0+1.0)/24.0))*255.0+0.5);return mix(lo,hi,(a*256.0+b)/65535.0);}
void vertex(){
vec4 d0=source_read(UV2,float(0),data_min_0,data_max_0);
vec4 d1=source_read(UV2,float(1),data_min_1,data_max_1);
vec4 d2=source_read(UV2,float(2),data_min_2,data_max_2);
vec4 d5=source_read(UV2,float(5),data_min_5,data_max_5);
vBindPos=d0.xyz; vEx=d0.w; vCloth=d5.xyz; vIwUv=d2.xy; vOcc=d1.w; COLOR=vec4(d1.rgb,1.0);


}
void fragment(){
vec4 diffuseColor=vec4(COLOR.rgb,1.0); vec3 normal=NORMAL; vec3 vNormal=NORMAL; vec3 vViewPosition=-VERTEX; float roughnessFactor=0.82; float metalnessFactor=0.0; vec3 totalEmissiveRadiance=vec3(0.0);

float iwH = 0.0; float iwAO = 1.0 - clamp(vOcc, 0.0, 0.95); float iwCls = floor(vCloth.y + 0.5); float iwPart = floor(vCloth.x + 0.5);
        float iwGloss = 0.0; float iwShine = 0.0; // extra clearcoat / sheen tweaks from decorations
        {
          float slot = floor(vEx + 0.5);
          vec3 p = vBindPos; vec2 uv = vIwUv;
          vec3 base = vec3(1.0);
          if (slot == 1.0) base = uTeam;
          else if (slot == 2.0) base = iwShirtCol(p, uv, iwPart);
          else if (slot == 3.0) base = uShorts;
          else if (slot == 4.0) base = uShoe;
          else if (slot == 5.0) base = uSock;
          else if (slot == 6.0) base = uSole;
          else if (slot == 7.0) base = uStrap;
          else if (slot == 8.0) base = iwContrast(uShoe);
          else if (slot == 9.0) base = mix(uSole * 0.3 + vec3(0.035), vec3(0.09, 0.09, 0.1), 0.35);
          else if (slot == 10.0) base = vec3(0.78, 0.8, 0.84);
          else if (slot == 11.0) base = uStrap * 0.55 + vec3(0.02);
          else if (slot == 12.0) base = mix(uSock, vec3(0.96), 0.6);
          else if (slot == 13.0) base = uTeam * 0.62;
          else if (slot == 14.0) base = iwTrimCol();

          // ---------------- part decorations ----------------
          if (iwPart == 1.0) { // TEE body: uv = (theta/2pi, y)
            float circ = 0.68;
            float th = uv.x;
            // side seams (x = +-90 deg) with twin stitching
            for (int s = 0; s < 2; s++) {
              float c = s == 0 ? 0.25 : 0.75;
              float dx = (th - c) * circ;
              float seam = iwStroke(dx, 0.0008);
              iwH -= 0.0005 * exp(-pow(dx / 0.0016, 2.0));
              float st = iwStroke(abs(dx) - 0.004, 0.0005) * iwDash(p.y, 0.0055, 0.6);
              base *= 1.0 - 0.12 * seam;
              base = mix(base, base * 0.8, st * iwLod(p.y, 0.0055));
              iwH += 0.00025 * st;
            }
            // double-needle hem stitching + hem fold
            float hy = p.y - vCloth.z;
            float st2 = (iwStroke(hy - 0.013, 0.0005) + iwStroke(hy - 0.019, 0.0005)) * iwDash(th * circ, 0.0055, 0.62);
            base = mix(base, base * 0.8, st2 * iwLod(th * circ, 0.0055));
            iwH += 0.0003 * st2 - 0.0006 * exp(-pow((hy - 0.024) / 0.002, 2.0));
            // fine creases riding on the sculpted folds (geometry carries the big ones): waist compression, underarm
            // crease fans, short vertical hem creases — per pixel, faded with footprint
            iwH += iwTeeCrease(p, th) * iwLod(p.y, 0.012);
            // chest emblem (pattern-dependent placement)
            if (p.z > 0.0) {
              vec2 q; float R; float on = 1.0;
              if (uPattern < 0.5) { q = vec2(p.x, p.y - 0.826); R = 0.038; }
              else if (uPattern < 1.5) { q = vec2(p.x, p.y - 0.927); R = 0.0135; }
              else if (uPattern < 2.5) { q = vec2(p.x, p.y - 0.818); R = 0.032; }
              else if (uPattern < 3.5) { q = vec2(p.x, p.y - 0.8); R = 0.028; }
              else if (uPattern < 4.5) { q = vec2(p.x, p.y - 0.927); R = 0.0135; }          // breton: small logo under the collar
              else if (uPattern < 5.5) { q = vec2(0.0); R = 1.0; on = 0.0; }                  // splatter: the splats are the graphic
              else if (uPattern < 6.5) { q = vec2(p.x - 0.05, p.y - 0.905); R = 0.0125; }     // camo: chest patch
              else if (uPattern < 7.5) { q = vec2(p.x, p.y - 0.862); R = 0.03; }              // dip-dye: emblem above the dye line
              else if (uPattern < 8.5) { q = vec2(0.0); R = 1.0; on = 0.0; }                  // jersey: number instead
              else { q = vec2(p.x - 0.048, p.y - 0.925); R = 0.0115; }                        // track: small chest logo
              if (on > 0.5) {
                vec2 e = iwEmblem(q, R);
                vec3 ink = uTeam;
                base = mix(base, ink, e.x);
                base = mix(base, uShirt * 1.02 + 0.02, e.y * e.x);
                iwH += 0.00018 * e.x;             // screen print sits slightly proud
                iwShine += 0.35 * e.x;            // plastisol print: a touch glossier
              }
              if (uPattern > 7.5 && uPattern < 8.5) {
                // jersey number (stable per character: derived from the per-character seed), team fill + dark outline
                float no = floor(fract(uHurtSeed * 0.6180339 + 0.137) * 98.0) + 1.0;
                float d1 = floor(no / 10.0), d0 = no - d1 * 10.0;
                vec2 nq = vec2(p.x, p.y - 0.8) / 0.029;
                float sd = d1 > 0.5 ? min(iwDigitSD(nq - vec2(-0.6, 0.0), int(d1)), iwDigitSD(nq - vec2(0.6, 0.0), int(d0))) : iwDigitSD(nq, int(d0));
                sd *= 0.029;
                float nf = iwFill(sd), no2 = iwFill(sd - 0.0034);
                base = mix(base, vec3(0.09, 0.1, 0.12), no2);
                base = mix(base, uTeam, nf);
                iwH += 0.00016 * no2; iwShine += 0.3 * no2;
              } else if (uPattern > 8.5) {
                // track top: centre-front zip — dark tape, metal teeth, pull tab at the collar
                float zx = abs(p.x);
                float tape = iwFill(zx - 0.0046) * step(p.y, 0.994);
                base = mix(base, uShirt * 0.45 + 0.01, tape);
                float teeth = iwFill(zx - 0.0021) * mix(0.6, step(0.5, fract(p.y / 0.0034)), iwLod(p.y, 0.0034)) * step(p.y, 0.992);
                base = mix(base, vec3(0.74, 0.76, 0.8), teeth);
                float pull = iwFill(iwSdBox(vec2(p.x - 0.0036, p.y - 0.968), vec2(0.0034, 0.0088), 0.0022));
                base = mix(base, vec3(0.8, 0.82, 0.86), pull);
                iwH += 0.00025 * (teeth + pull) - 0.0002 * tape;
                iwShine += teeth + pull;
              }
            }
            // lower-back print (visible around the tank from the gameplay camera)
            if (p.z < 0.0 && uPattern > 0.5 && uPattern < 3.5) {
              float band = iwBand(p.y, 0.735, 0.748) * step(0.06, abs(p.x));
              base = mix(base, uTeam, band * 0.9);
            }
            // tank-strap pressure shading on the shoulders (strap sits on top)
            iwAO *= 1.0 - 0.18 * exp(-pow((abs(p.x) - 0.075) / 0.018, 2.0)) * smoothstep(0.9, 0.98, p.y);
          } else if (iwPart == 2.0) { // SLEEVE: uv = (theta, s along from shoulder)
            float s = uv.y, L = vCloth.z;
            float cuff = smoothstep(L - 0.02, L - 0.018, s);
            base = mix(base, slot == 2.0 ? iwCuffCol() : base, cuff);
            float circ = 0.3;
            float st = iwStroke(s - (L - 0.024), 0.0005) * iwDash(uv.x * circ, 0.005, 0.6);
            float st2 = iwStroke(s - 0.012, 0.0005) * iwDash(uv.x * circ, 0.005, 0.6);
            base = mix(base, base * 0.78, (st + st2) * iwLod(uv.x * circ, 0.005));
            iwH += 0.0003 * (st + st2);
            // rib on the cuff
            float rib = sin(uv.x * 6.2831 * 70.0);
            iwH += cuff * 0.00035 * rib * iwLod(uv.x * circ, circ / 70.0);
            // crease folds at the armpit side
            iwH += 0.0012 * sin(uv.x * 6.2831 * 3.0 + s * 60.0) * smoothstep(0.03, 0.0, s);
          } else if (iwPart == 3.0) { // COLLAR rib: uv = (theta, across)
            float rib = sin(uv.x * 6.2831 * 90.0);
            iwH += 0.0004 * rib * iwLod(uv.x * 0.3, 0.3 / 90.0);
            iwAO *= mix(0.8, 1.0, smoothstep(0.0, 0.35, uv.y));
          } else if (iwPart == 4.0 || iwPart == 5.0) { // SHORTS: uv = (theta, y | s)
            float circ = iwPart == 4.0 ? 0.66 : 0.46;
            float th = uv.x;
            // side seams + a team side stripe on some outfits
            float dx0 = (th - 0.25) * circ, dx1 = (th - 0.75) * circ;
            float dxs = iwPart == 4.0 ? min(abs(dx0), abs(dx1)) : abs(th - 0.5) * circ;   // legs: uv.x 0 = inseam, 0.5 = outer seam
            iwH -= 0.0005 * exp(-pow(dxs / 0.0016, 2.0));
            float stripe = 0.0; vec3 stripeC = uTeam;
            if (uPattern > 0.5 && uPattern < 2.5) stripe = iwStroke(dxs, 0.0065);
            else if (uPattern > 7.5 && uPattern < 8.5) stripe = iwStroke(dxs, 0.011);                                   // jersey: wide team panel
            else if (uPattern > 8.5) { stripe = iwStroke(dxs - 0.0075, 0.0026); stripeC = vec3(0.95); }                // track: twin white stripes
            base = mix(base, stripeC, stripe);
            float ss = iwStroke(dxs - 0.0045, 0.00045) * iwDash(p.y, 0.005, 0.6);
            base = mix(base, base * 0.75 + 0.02, ss * iwLod(p.y, 0.005));
            if (iwPart == 4.0) {
              vec2 f = vec2(p.x, p.y);
              // front: fly J-stitch + slant pocket openings
              if (p.z > 0.0) {
                float fly = iwSdSeg(f, vec2(0.012, 0.745), vec2(0.012, 0.64));
                fly = min(fly, iwSdSeg(f, vec2(0.012, 0.64), vec2(0.0, 0.625)));
                float fs = iwStroke(fly, 0.0005) * iwDash(p.y + p.x, 0.005, 0.6);
                base = mix(base, base * 0.72 + 0.02, fs * iwLod(p.y, 0.005));
                iwH -= 0.0006 * exp(-pow(abs(p.x) / 0.0018, 2.0)) * step(0.63, p.y);
                for (int s = -1; s <= 1; s += 2) {
                  float sx = float(s);
                  float pk = iwSdSeg(f, vec2(sx * 0.062, 0.752), vec2(sx * 0.112, 0.668));
                  iwH -= 0.0009 * exp(-pow(pk / 0.0018, 2.0));
                  float ps = iwStroke(pk - 0.004, 0.00045) * iwDash(p.y, 0.005, 0.6);
                  base = mix(base, base * 0.72 + 0.02, ps * iwLod(p.y, 0.005));
                  iwAO *= 1.0 - 0.25 * exp(-pow(pk / 0.003, 2.0));
                }
              } else {
                // back patch pockets with a little team label on the right one
                for (int s = -1; s <= 1; s += 2) {
                  float sx = float(s);
                  float pb = iwSdBox(f - vec2(sx * 0.058, 0.668), vec2(0.036, 0.04), 0.01);
                  iwH += 0.0008 * (1.0 - smoothstep(-0.002, 0.0015, pb));
                  float ps = (iwStroke(pb + 0.0035, 0.00045)) * iwDash(p.x + p.y, 0.005, 0.6);
                  base = mix(base, base * 0.72 + 0.02, ps * iwLod(p.y, 0.005));
                  iwAO *= 1.0 - 0.3 * exp(-pow(pb / 0.0022, 2.0)) * step(0.0, pb);
                  if (s < 0) { float lab = iwSdBox(f - vec2(sx * 0.03, 0.692), vec2(0.006, 0.012), 0.002); base = mix(base, uTeam, iwFill(lab)); }
                }
                // seat seam
                iwH -= 0.0006 * exp(-pow(p.x / 0.0017, 2.0));
              }
              // waistband stitch (mostly under the tee hem)
              float ws = iwStroke(p.y - 0.735, 0.0005) * iwDash(th * circ, 0.005, 0.6);
              base = mix(base, base * 0.75, ws);
            } else {
              // leg: inseam
              float dxi = min(th, 1.0 - th) * circ;
              iwH -= 0.0004 * exp(-pow(dxi / 0.0015, 2.0));
              // hem stitch above the cuff
              float L = vCloth.z;
              float hs = iwStroke(uv.y - (L - 0.02), 0.00045) * iwDash(th * circ, 0.005, 0.6);
              base = mix(base, base * 0.72 + 0.02, hs * iwLod(th * circ, 0.005));
              // relaxed folds
              iwH += 0.0013 * sin(th * 6.2831 * 5.0 + uv.y * 30.0) * smoothstep(0.02, 0.1, uv.y);
            }
          } else if (iwPart == 6.0) { // SOCK: uv = (theta, s from top)
            float rib = sin(uv.x * 6.2831 * 56.0);
            iwH += 0.00045 * rib * iwLod(uv.x * 0.22, 0.22 / 56.0);
            float s = uv.y;
            float stripes = iwBand(s, 0.018, 0.026) + iwBand(s, 0.033, 0.041);
            base = mix(base, uTeam, stripes);
            iwH += 0.0012 * sin(s * 190.0 + uv.x * 18.0) * smoothstep(0.05, 0.1, s) * smoothstep(0.14, 0.1, s); // scrunch
          } else if (iwPart == 7.0) { // SHOE UPPER (base layer): uv = (phi/2pi from the toe, t sole->collar, > 1 = lining)
            float phi = uv.x, t = uv.y;
            float front = cos(phi * 6.2831);
            // perforated toe box (vamp top, between the mudguard and the throat)
            float perfZ = smoothstep(0.72, 0.82, front) * smoothstep(0.47, 0.51, t) * smoothstep(0.62, 0.58, t);
            vec2 pp = vec2(p.x, p.z) * 260.0; pp.x += 0.5 * step(0.5, fract(pp.y * 0.5)); vec2 pc = fract(pp) - 0.5;
            float perf = iwFill(length(pc) - 0.16) * perfZ * iwLod(p.z * 260.0, 1.0) * iwLod(p.x * 260.0, 1.0);
            iwAO *= 1.0 - 0.55 * perf; iwH -= 0.00018 * perf;
            // fine pebbled grain, faded with pixel footprint (no shimmer)
            iwH += 0.00005 * (iwNoise(p * 1400.0) - 0.5) * iwLod(p.z * 1400.0, 2.0);
            iwAO *= mix(0.7, 1.0, smoothstep(0.0, 0.14, t));   // contact darkening at the sole line
            if (t > 1.001) iwAO *= 0.55;                       // lining inside the collar
          } else if (iwPart == 20.0) { // SHOE OVERLAYS (vCloth.z: 0 mudguard, 1 heel counter, 2 eyestay, 3 side panel); uv = patch (u, v)
            float ov = floor(vCloth.z + 0.5);
            vec2 q = uv;
            // twin-needle stitching inset from the free edges
            float st = 0.0;
            if (ov < 0.5) st = (iwStroke(q.y - 0.86, 0.018) + iwStroke(q.y - 0.79, 0.018)) * iwDash(q.x * 0.14, 0.0035, 0.6);
            else if (ov < 1.5) st = iwStroke(q.y - 0.88, 0.02) * iwDash(q.x * 0.12, 0.0035, 0.6);
            else if (ov < 2.5) st = (iwStroke(q.x - 0.84, 0.03) + iwStroke(q.x - 0.15, 0.03)) * iwDash(q.y * 0.06, 0.0035, 0.6);
            else st = (iwStroke(q.y - 0.8, 0.045) + iwStroke(q.y - 0.2, 0.045)) * iwDash(q.x * 0.1, 0.0035, 0.6) * step(0.06, q.x) * step(q.x, 0.97);
            st = clamp(st, 0.0, 1.0) * step(0.05, q.y) * iwLod(q.x * 0.1, 0.0035);
            base = mix(base, base * 0.62 + 0.04, st * 0.9);
            iwH += 0.00018 * st;
            iwH += 0.00004 * (iwNoise(p * 1600.0) - 0.5) * iwLod(p.z * 1600.0, 2.0);
            if (ov > 2.5) iwShine += 0.45;                     // glossy synthetic side panel
          } else if (iwPart == 8.0) { // MIDSOLE / cupsole wall: uv = (phi, h 0..1)
            float phi = uv.x, h = uv.y;
            float front = cos(phi * 6.2831), side = sin(phi * 6.2831);
            // thread in the sculpted stitch channel (h = 0.64)
            float st = iwStroke(h - 0.64, 0.035) * iwDash(phi * 0.62, 0.0042, 0.62) * iwLod(phi * 0.62, 0.0042);
            base = mix(base, base * 0.62 + vec3(0.02), st);
            iwH += 0.00018 * st;
            // team pinstripe near the top edge
            float pin = iwStroke(h - 0.82, 0.035) * step(abs(front), 0.96);
            base = mix(base, uTeam, pin * 0.95);
            // fine horizontal sidewall ribs (cupsole texture) below the channel
            iwH += 0.00016 * sin(h * 6.2831 * 9.0) * smoothstep(0.08, 0.2, h) * smoothstep(0.58, 0.5, h);
            // heel window (team) on both sides
            float win = iwSdBox(vec2(front + 0.64, h - 0.34), vec2(0.16, 0.14), 0.08);
            float wm = iwFill(win * 0.05) * step(0.3, abs(side));
            base = mix(base, uTeam * 0.85, wm);
            iwH -= 0.0005 * wm; iwShine += wm;
            // foam micro texture + grime near the ground and scuffs on the toe
            iwH += 0.00008 * (iwNoise(p * 700.0) - 0.5) * iwLod(p.z * 700.0, 1.0);
            float grime = (1.0 - smoothstep(0.0, 0.35, h)) * (0.55 + 0.45 * iwFbm(p * 90.0));
            float scuff = smoothstep(0.62, 0.8, iwFbm(p * 140.0 + 3.0)) * smoothstep(0.3, 0.9, front);
            base *= 1.0 - 0.13 * grime - 0.1 * scuff;
          } else if (iwPart == 9.0) { // OUTSOLE: uv = foot-local (x, z)
            vec2 f = uv;
            float edgeZone = step(0.5, vCloth.z);
            // herringbone traction pattern on the bottom
            float herr = abs(fract(f.y * 55.0 + abs(f.x) * 22.0) - 0.5);
            float lug = smoothstep(0.18, 0.26, herr);
            iwH += 0.0012 * lug * (1.0 - edgeZone) * iwLod(f.y * 55.0, 1.0);
            iwAO *= mix(0.6, 1.0, mix(lug, 1.0, edgeZone));
            // worn rubber: glazed at the toe + heel strike, dust on the wall
            float wear = smoothstep(0.05, 0.11, f.y) + smoothstep(-0.03, -0.07, f.y);
            base = mix(base, base * 1.35 + 0.04, 0.35 * wear * (1.0 - edgeZone) * lug);
            base = mix(base, base * 0.8 + vec3(0.03, 0.028, 0.025), edgeZone * (0.4 + 0.6 * iwFbm(p * 120.0)) * 0.5);
          } else if (iwPart == 10.0) { // STRAP webbing: uv = (along m, across -1..1)
            float edge = abs(uv.y);
            float st = iwStroke(edge - 0.72, 0.035) * iwDash(uv.x, 0.005, 0.62);
            base = mix(base, base * 0.6 + 0.06, st * iwLod(uv.x, 0.005));
            iwH += 0.00025 * st;
            iwAO *= mix(1.0, 0.8, smoothstep(0.8, 1.0, edge));
          } else if (iwPart == 11.0) { // TONGUE: uv = (across -1..1, along 0..1); team tab + logo at the top
            float tab = smoothstep(0.78, 0.8, uv.y);
            base = mix(base, uTeam, tab);
            vec2 e = iwEmblem(vec2(uv.x * 0.018, (uv.y - 0.9) * 0.02), 0.0065);
            base = mix(base, vec3(0.97), e.x * tab);
            float st = iwStroke(abs(uv.x) - 0.82, 0.03) * iwDash(uv.y * 0.05, 0.004, 0.6);
            base = mix(base, base * 0.7, st);
            vec2 mp = vec2(uv.x * 0.02, uv.y * 0.05) * 700.0; // mesh
            float mh = iwFill(length(fract(mp) - 0.5) - 0.2) * (1.0 - tab) * iwLod(uv.y * 0.05 * 700.0, 1.0);
            iwAO *= 1.0 - 0.35 * mh;
          } else if (iwPart == 12.0) { // TANK CAP: uv = (theta, h); knurled grip band
            float kn = sin(uv.x * 6.2831 * 48.0);
            float band = step(0.18, uv.y) * step(uv.y, 0.82);
            iwH += 0.0005 * kn * band * iwLod(uv.x * 0.42, 0.42 / 48.0);
          } else if (iwPart == 13.0) { // GAUGE face: uv = polar (angle 0..1, r 0..1)
            float a = uv.x, r = uv.y;
            vec3 face = vec3(0.95, 0.94, 0.9);
            float ticks = iwStroke(fract(a * 24.0) - 0.5, 0.06) * step(0.72, r) * step(r, 0.9) * step(0.1, a) * step(a, 0.9);
            float red = step(0.72, r) * step(r, 0.9) * step(0.78, a) * step(a, 0.9);
            face = mix(face, vec3(0.1), ticks);
            face = mix(face, vec3(0.85, 0.15, 0.12), red);
            base = mix(face, vec3(0.05), smoothstep(0.93, 0.97, r));
          } else if (iwPart == 15.0) { // shorts CUFF: rolled hem, rib-less twill + stitch
            float st = iwStroke(uv.y - 0.5, 0.05) * iwDash(uv.x * 0.46, 0.005, 0.6);
            base = mix(base, base * 0.75, st);
          } else if (iwPart == 17.0) { // COLLAR PAD: soft quilting lines
            iwH += 0.0005 * sin(uv.x * 6.2831 * 14.0);
          } else if (iwPart == 18.0) { // PLATE: quilted back pad
            vec2 q = vec2(uv.x, uv.y) * 38.0;
            float quilt = iwStroke(fract(q.x + q.y) - 0.5, 0.03) + iwStroke(fract(q.x - q.y) - 0.5, 0.03);
            iwH -= 0.0004 * quilt; iwAO *= 1.0 - 0.18 * quilt;
          } else if (iwPart == 16.0) { // drawcord: twisted
            iwH += 0.0003 * sin(uv.x * 900.0 + uv.y * 6.2831 * 3.0);
          }

          // ---------------- material-class micro detail ----------------
          if (iwCls == 0.0) {        // jersey knit: columns of tiny V loops (~1.1 mm wales), gone before it can shimmer
            float wale = (atan(p.x, p.z + 0.012) * 0.105 + p.x * 0.0) * 900.0, course = p.y * 1150.0;
            float v = abs(fract(wale) - 0.5) * 2.0;
            float k = sin((course + v * 0.9) * 6.2831);
            iwH += 0.000028 * k * iwLod(course, 1.0) * iwLod(wale, 1.0);
          } else if (iwCls == 1.0) { // twill: fine 45-degree wales (~1 mm) over a slubby yarn, faded with footprint
            float w = (p.y * 0.8 + (p.x + p.z) * 0.6) * 6400.0;
            float k = sin(w + 1.3 * iwNoise(p * 420.0));
            iwH += 0.000035 * k * iwLod(w, 6.2831);
            iwH += 0.00004 * (iwNoise(p * 260.0) - 0.5) * iwLod(p.y * 260.0, 1.0);
          } else if (iwCls == 8.0) { // webbing: cross ribs
            float k = sin(uv.x * 2600.0);
            iwH += 0.00004 * k * iwLod(uv.x * 2600.0, 6.2831);
          } else if (iwCls == 10.0) { // lace braid
            iwH += 0.00012 * sin(uv.x * 1800.0) * iwLod(uv.x * 1800.0, 6.2831);
          }
          diffuseColor.rgb *= base;
        }
      
  float iwHurtM = 0.0;
  if (uHurt.w > 0.002) {
    vec3 hp = vBindPos * vec3(10.0, 6.5, 10.0) + vec3(uHurtSeed);
    hp.y += 0.35 * iwNoise(vBindPos * 23.0);
    float n = iwFbm(hp);
    float th = mix(1.0, 0.47, clamp(uHurt.w, 0.0, 1.0));
    float w = max(fwidth(n) * 0.9, 0.004);
    iwHurtM = smoothstep(th - w, th + w, n);
    float rim = smoothstep(th - 0.05, th - w, n) * (1.0 - iwHurtM);
    diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * 0.8, rim * 0.6);
    diffuseColor.rgb = mix(diffuseColor.rgb, uHurt.rgb, iwHurtM);
  }
{
          float r = 0.84;
          if (iwCls == 1.0) r = 0.8; else if (iwCls == 2.0) r = 0.86; else if (iwCls == 3.0) r = 0.46; else if (iwCls == 4.0) r = 0.62;
          else if (iwCls == 5.0) r = 0.86; else if (iwCls == 6.0) r = 0.3; else if (iwCls == 7.0) r = 0.28; else if (iwCls == 8.0) r = 0.7;
          else if (iwCls == 9.0) r = 0.74; else if (iwCls == 10.0) r = 0.8; else if (iwCls == 11.0) r = 0.78; else if (iwCls == 12.0) r = 0.5;
          roughnessFactor = mix(r, r * 0.55, clamp(iwShine, 0.0, 1.0));
          roughnessFactor = mix(roughnessFactor, 0.16, iwHurtM);
        }
metalnessFactor = iwCls == 7.0 ? 1.0 : 0.0;
normal = iwBumpN(normal, iwH, -vViewPosition);
totalEmissiveRadiance += uFlash;
ALBEDO=max(diffuseColor.rgb,vec3(0.0)); ROUGHNESS=clamp(roughnessFactor,0.04,1.0); METALLIC=clamp(metalnessFactor,0.0,1.0); NORMAL=normal; SPECULAR=0.5;


AO=clamp(iwAO,0.0,1.0);
EMISSION=totalEmissiveRadiance+vec3(hit_flash)+ALBEDO*rim_strength*pow(1.0-clamp(dot(normal,VIEW),0.0,1.0),3.2);
vec3 source_dxy=max(abs(dFdx(vNormal)),abs(dFdy(vNormal)));float geometryRoughness=max(source_dxy.x,max(source_dxy.y,source_dxy.z));
native_specularColor=vec3(0.04);native_specularColorBlended=mix(native_specularColor,diffuseColor.rgb,metalnessFactor);native_specularF90=mix(1.0,1.0,metalnessFactor);
native_clearcoat=1.0;native_clearcoatRoughness=clamp(max(0.3,0.0525)+geometryRoughness,0.0525,1.0);
native_sheenColor=vec3(1.0,1.0,1.0);native_sheenRoughness=0.6;
{
          float cc = 0.0, ccr = 0.3, sh = 0.0, shr = 0.6;
          if (iwCls == 0.0) { sh = 0.55; shr = 0.55; }        // jersey
          else if (iwCls == 1.0) { sh = 0.35; shr = 0.5; }    // twill
          else if (iwCls == 2.0) { sh = 0.6; shr = 0.45; }    // rib knit
          else if (iwCls == 3.0) { cc = 0.35; ccr = 0.28; sh = 0.1; }
          else if (iwCls == 4.0) { cc = 0.05; ccr = 0.5; }
          else if (iwCls == 6.0) { cc = 1.0; ccr = 0.12; }
          else if (iwCls == 7.0) { cc = 0.4; ccr = 0.15; }
          else if (iwCls == 8.0) { sh = 0.45; shr = 0.4; }
          else if (iwCls == 9.0) { sh = 0.4; shr = 0.4; }
          else if (iwCls == 10.0) { sh = 0.5; shr = 0.4; }
          else if (iwCls == 11.0) { sh = 0.7; shr = 0.35; }
          cc = max(cc, iwShine * 0.6); ccr = mix(ccr, 0.15, clamp(iwShine, 0.0, 1.0));
          cc = mix(cc, 1.0, iwHurtM);

            native_clearcoat = cc; native_clearcoatRoughness = max(ccr, 0.06);


            native_sheenColor = mix(vec3(1.0), diffuseColor.rgb * 1.3 + 0.12, 0.6) * sh * (1.0 - iwHurtM);
            native_sheenRoughness = shr;

        }
native_clearcoat=clamp(native_clearcoat,0.0,1.0);native_clearcoatRoughness=clamp(native_clearcoatRoughness,0.0525,1.0);native_sheenRoughness=clamp(native_sheenRoughness,0.0001,1.0);
ROUGHNESS=clamp(max(roughnessFactor,0.0525)+geometryRoughness,0.0525,1.0);SPECULAR=0.5;CLEARCOAT=native_clearcoat;CLEARCOAT_ROUGHNESS=native_clearcoatRoughness;
float source_nv=clamp(dot(normalize(normal),normalize(VIEW)),0.0,1.0);vec2 source_fab=native_dfg(vec2(ROUGHNESS,source_nv));native_energy_comp=vec3(1.0)+native_specularColorBlended*(1.0/max(source_fab.x+source_fab.y,0.000001)-1.0);
native_coat_normal=normalize(vNormal);float source_cc_nv=clamp(dot(native_coat_normal,normalize(VIEW)),0.0,1.0);native_coat_attenuation=vec3(1.0)-native_clearcoat*native_schlick(vec3(0.04),1.0,source_cc_nv);
native_sss=0.0;native_thin=0.0;
native_gum_on=0.0;native_gum_thin=0.0;native_gum_trans=vec3(0.0);native_direct_ao=mix(1.0,iwAO,0.35);

vec3 source_world_normal=normalize((INV_VIEW_MATRIX*vec4(normal,0.0)).xyz);vec3 source_world_view=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);float hemi_mix=clamp(source_world_normal.y*0.5+0.5,0.0,1.0);vec3 source_hemi=mix(hemi_ground,hemi_sky,hemi_mix);
EMISSION*=native_coat_attenuation;
vec3 source_coat_world_normal=normalize((INV_VIEW_MATRIX*vec4(native_coat_normal,0.0)).xyz);
EMISSION+=native_source_indirect_coated(ALBEDO,METALLIC,native_specularColor,native_specularF90,ROUGHNESS,native_sheenColor,native_sheenRoughness,native_clearcoat,native_clearcoatRoughness,source_world_normal,source_world_view,source_hemi,AO,mix(1.0,AO,0.7),source_coat_world_normal);


vec3 rim_view=normalize(VIEW);
vec3 rim_direction=native_rim_world?normalize((VIEW_MATRIX*vec4(uIwRimL,0.0)).xyz):uIwRimL;
float rim_fresnel=pow(1.0-clamp(dot(normal,rim_view),0.0,1.0),uIwRim.w);
float rim_side=clamp(dot(normal,rim_direction)*0.5+0.5,0.0,1.0);
EMISSION+=uIwRim.rgb*(0.7*rim_fresnel*(0.3+0.7*rim_side*rim_side));
float rim_fill=clamp(dot(normal,normalize(vec3(0.25,0.45,1.0)))*0.6+0.4,0.0,1.0);
EMISSION+=uIwFill*diffuseColor.rgb*rim_fill*rim_fill;
}
