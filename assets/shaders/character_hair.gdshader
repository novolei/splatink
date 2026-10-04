// Generated from source material hair; original authored color/detail equations.
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
varying vec3 vBindPos; 

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

uniform vec3 uTeam = vec3(1.0,0.25415209,0.00699541); uniform vec3 uGlow = vec3(0.0,0.0,0.0); uniform vec3 uShirt = vec3(0.89626935,0.8796224,0.83879901); uniform vec3 uShorts = vec3(0.02315337,0.03310477,0.08021982); uniform vec3 uStrap = vec3(0.03310477,0.03688945,0.04970657); varying float vTint; varying vec4 vStrand; varying float vSinA; varying vec3 vGearCol; varying vec3 vHair;
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

void iwHatShade(float cls, vec2 uv, vec3 bp, inout vec3 col, inout float h, inout float ao) {
  vec3 hd = normalize(bp - vec3(0.0, 1.214, 0.012));
  float ce = max(length(hd.xz), 0.05);                     // cos(elevation): the panels converge toward the crown
  float u = uv.x, v = uv.y;
  bool under = v > 3.1; float s = under ? v - 3.2 : v - 2.0;
  if (cls < 4.5) {                                         // ---- SNAPBACK: twill, six panels, eyelets, logo, stitched bill
    float tw = sin((bp.y * 0.9 + (bp.x + bp.z) * 0.6) * 1500.0);
    h += 0.00007 * tw * iwLod(bp.y * 1500.0, 6.2831);
    if (v < 1.9) {
      float su = (u - 0.5) * 6.0;
      float md = abs(fract(su + 0.5) - 0.5) / 6.0 * 1.19 * ce;       // metres to the nearest panel seam
      float seam = iwStroke(md, 0.0009);
      float st = iwStroke(md - 0.0042, 0.00045) * iwDash(v * 0.19, 0.0045, 0.62);
      col *= 1.0 - 0.18 * seam; col = mix(col, col * 0.72 + 0.03, st * iwLod(v * 0.19, 0.0045));
      h += 0.0007 * exp(-pow(md / 0.003, 2.0)) - 0.0005 * seam + 0.0002 * st;
      // eyelets high on every panel
      float pu = (fract(su) - 0.5) / 6.0 * 1.19 * ce;
      float ey = length(vec2(pu, (v - 0.86) * 0.1)) ;
      float eyR = iwStroke(ey - 0.0034, 0.0011), eyH = iwFill(ey - 0.0024);
      col = mix(col, col * 0.6, eyR); col = mix(col, vec3(0.02), eyH * 0.9); h += 0.0003 * eyR - 0.0004 * eyH;
      // front logo: team squid badge embroidered over the centre seam
      vec2 lq = vec2((u - 0.5) * 1.19 * ce, (v < 0.32 ? v * 0.19 : (0.32 + (v - 0.32) * 0.55) * 0.19) - 0.058);
      vec2 e = iwEmblem(lq, 0.026);
      col = mix(col, uTeam, e.x); col = mix(col, vec3(0.97), e.x * e.y);
      h += 0.0004 * e.x;
      ao *= mix(0.78, 1.0, smoothstep(0.0, 0.03, v));      // the rim sits in its own shadow
    } else {
      float rows = 0.0;
      for (int k = 0; k < 4; k++) rows += iwStroke(s - (0.52 + 0.12 * float(k)), 0.008);
      col = mix(col, col * 0.7 + 0.03, clamp(rows, 0.0, 1.0) * 0.8);
      h += 0.0002 * rows;
      h -= 0.0012 * smoothstep(0.9, 1.02, s);              // rounded bill edge
    }
  } else if (cls < 5.5) {                                  // ---- BEANIE: rib knit, folded cuff with a team stripe
    float rib = sin(u * 6.2831 * 76.0);
    h += 0.00055 * rib * iwLod(u * 76.0 * ce, 1.0);
    col *= 1.0 - 0.07 * (rib * 0.5 + 0.5) * iwLod(u * 76.0 * ce, 1.0);
    h += 0.00022 * sin(v * 540.0) * iwLod(v * 540.0, 6.2831);          // knit loops
    if (v < 0.21) {
      float stripe = iwBand(v, 0.07, 0.112);
      col = mix(col, uTeam, stripe);
      col = mix(col, vec3(0.95), iwBand(v, 0.058, 0.066) + iwBand(v, 0.116, 0.124));
    }
    h -= 0.0011 * exp(-pow((v - 0.2) / 0.006, 2.0));                    // fold of the cuff
    ao *= 1.0 - 0.32 * exp(-pow((v - 0.206) / 0.012, 2.0));
  } else {                                                  // ---- BUCKET: canvas, team band, stitched brim
    float wv = sin(bp.x * 2600.0) * sin(bp.y * 2600.0 + bp.z * 1300.0);
    h += 0.00006 * wv * iwLod(bp.y * 2600.0, 6.2831);
    if (v < 1.9) {
      col = mix(col, uTeam, iwBand(v, 0.018, 0.08));
      float st = (iwStroke(v - 0.098, 0.0016) + iwStroke(v - 0.118, 0.0016)) * iwDash(u * 1.19 * ce, 0.004, 0.6);
      col = mix(col, col * 0.7 + 0.03, st);
      float su = u * 4.0; float md = abs(fract(su + 0.5) - 0.5) / 4.0 * 1.19 * ce;
      col *= 1.0 - 0.14 * iwStroke(md, 0.001) * step(0.08, v);
      h -= 0.0004 * iwStroke(md, 0.001) * step(0.08, v);
      ao *= mix(0.72, 1.0, smoothstep(0.0, 0.025, v));
    } else {
      float rows = 0.0;
      for (int k = 0; k < 6; k++) rows += iwStroke(s - (0.16 + 0.135 * float(k)), 0.01);
      col = mix(col, col * 0.68 + 0.03, clamp(rows, 0.0, 1.0) * iwDash(u * 3.4, 0.004, 0.62));
      h -= 0.00025 * rows;
      h -= 0.001 * smoothstep(0.92, 1.02, s);
    }
  }
}

  
vec3 iwSat(vec3 c, float k){ float l = dot(c, vec3(0.2126, 0.7152, 0.0722)); return max(mix(vec3(l), c, k), 0.0); }

uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);
#include "res://assets/shaders/character_lighting.gdshaderinc"
#include "res://assets/shaders/source_cube_uv.gdshaderinc"
#include "res://assets/shaders/character_indirect.gdshaderinc"

vec4 source_read(vec2 coord,float slot,vec4 lo,vec4 hi){vec4 a=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0)/24.0))*255.0+0.5);vec4 b=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0+1.0)/24.0))*255.0+0.5);return mix(lo,hi,(a*256.0+b)/65535.0);}
void vertex(){
vec4 d0=source_read(UV2,float(0),data_min_0,data_max_0);
vec4 d1=source_read(UV2,float(1),data_min_1,data_max_1);
vec4 d2=source_read(UV2,float(2),data_min_2,data_max_2);
vec4 d6=source_read(UV2,float(6),data_min_6,data_max_6);
vBindPos=d0.xyz; vTint=d2.z; vStrand=vec4(d1.r,d1.g,d2.x,d2.y); vSinA=d1.b*2.0-1.0; vGearCol=d1.rgb; vHair=d6.xyz;


}
void fragment(){
vec4 diffuseColor=vec4(vec3(1.0),1.0); vec3 normal=NORMAL; vec3 vNormal=NORMAL; vec3 vViewPosition=-VERTEX; float roughnessFactor=0.34; float metalnessFactor=0.0; vec3 totalEmissiveRadiance=vec3(0.0);
vec3 iwGumTrans = vec3(0.0);
float iwGumThin = 0.0;
float iwGumOn = 0.0;
float iwSuck = 0.0; float iwGear = 0.0; float iwGearCls = 0.0; float iwH = 0.0; float iwTipK = 0.0; float iwAO = 1.0; float iwCup = 0.0;
        {
          vec3 tc = uTeam;
          float lum = dot(tc, vec3(0.299, 0.587, 0.114));
          vec3 light = mix(tc, vec3(1.0), 0.55);
          vec3 dark = tc * mix(1.0, 0.45, clamp(lum * 1.4, 0.0, 1.0));
          vec3 tsat = iwSat(tc, 1.4);                                   // the jelly's own (saturated) tint
          vec3 core = pow(max(tc, vec3(1e-4)), vec3(1.35)) * mix(0.8, 0.9, clamp(lum * 1.2, 0.0, 1.0));  // deep interior (dye over a long path)
          float nv = clamp(dot(normalize(vNormal), normalize(vViewPosition)), 0.0, 1.0);
          if (vTint <= -1.5) {
            // ---------------- gear accessory ----------------
            iwGear = 1.0; iwGearCls = floor(-vTint - 2.0 + 0.5);
            // colour code in r: >= 0 literal rgb; -1 team, -2 shirt, -3 strap, -4 shorts (each × g)
            vec3 gc = vGearCol;
            if (gc.r < -0.5) { float code = floor(-gc.r + 0.5); gc = (code == 1.0 ? tc : code == 2.0 ? uShirt : code == 3.0 ? uStrap : uShorts) * gc.g; }
            diffuseColor.rgb = gc;
            if (iwGearCls == 2.0) { // terry / knit fabric
              iwH += 0.00018 * iwNoise(vBindPos * 1400.0) * iwLod(vBindPos.y * 1400.0, 1.0);
            } else if (iwGearCls > 3.5) { // headgear fabrics (uv: around, rim-relative height | bill / brim)
              iwHatShade(iwGearCls, vStrand.zw, vBindPos, diffuseColor.rgb, iwH, iwAO);
            }
          } else if (vGearCol.b >= 1.5) {
            // ---------------- scalp cap: tentacle bundles radiating from the crown (or the style's gather point) ----
            // uv = stereographic coords of the head direction about the groove pole → (az, el) about that pole
            float spr = dot(vStrand.zw, vStrand.zw);
            float az = atan(vStrand.z, vStrand.w), el = asin(clamp((1.0 - spr) / (1.0 + spr), -1.0, 1.0));
            float crown = smoothstep(1.45, 0.9, el);
            float bundles = sin(az * 9.0 + 0.35 * sin(el * 5.0));
            float groove = pow(1.0 - abs(bundles), 6.0) * crown;
            iwH -= 0.0016 * groove;
            iwAO *= (1.0 - 0.3 * groove) * vHair.z;
            float edge = smoothstep(0.0, 0.25, vGearCol.g); // g = distance above the hairline (0 at the rolled lip)
            diffuseColor.rgb = mix(mix(core, tc, 0.5), tc, 0.45 + 0.55 * edge);
            diffuseColor.rgb = mix(diffuseColor.rgb, mix(tc, light, 0.3), 0.3 * smoothstep(0.8, 1.5, el) * (1.0 - groove));
            diffuseColor.rgb *= mix(0.62, 1.0, vHair.z);
            iwGumOn = 1.0; iwGumThin = 0.12 * (1.0 - edge) + 0.05; iwGumTrans = tsat * 1.05;
          } else {
            // ---------------- strand / sculpted lock / modelled cup ----------------
            float t = vStrand.x, on = vStrand.y, dist = vStrand.z, cs = vStrand.w;
            float thick = vHair.x; iwCup = vHair.y;
            vec3 base = vTint >= 0.0 ? mix(tc, light, vTint) : mix(tc, dark, -vTint);
            // how much jelly the view ray crosses: deep, saturated core facing the viewer, lighter wet skin at grazing
            float path = thick * (0.25 + 0.75 * nv);
            float deep = smoothstep(0.002, 0.012, path);
            diffuseColor.rgb = mix(base, mix(base, core, 0.62), deep);
            // root → tip: denser at the root (in the cap's shade), clearer and brighter toward the tip
            iwTipK = smoothstep(0.55, 1.0, t);
            diffuseColor.rgb *= mix(0.8, 1.0, smoothstep(0.0, 0.3, t));
            diffuseColor.rgb = mix(diffuseColor.rgb, mix(base, light, 0.22), 0.4 * iwTipK);
            // defined strand edges: a slightly darker crease where the ribbon turns under
            float edgeK = smoothstep(0.7, 0.98, abs(vSinA)) * smoothstep(0.02, 0.12, t) * step(iwCup, 0.5);
            diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * mix(vec3(0.8), core / max(tc, vec3(1e-3)), 0.5), edgeK * 0.7);
            iwAO *= 1.0 - 0.25 * edgeK;
            // soft highlight ridge along the top, a slightly paler sucker side underneath
            float ridge = smoothstep(0.75, 1.0, cs) * (1.0 - smoothstep(0.2, 0.5, abs(vSinA)));
            diffuseColor.rgb = mix(diffuseColor.rgb, mix(diffuseColor.rgb, light, 0.3), ridge * 0.45);
            diffuseColor.rgb = mix(diffuseColor.rgb, mix(base, light, 0.2), 0.22 * smoothstep(-0.3, -0.85, cs) * step(iwCup, 0.5));
            // faint wet unevenness so the reflections wobble instead of sliding like on a pipe
            iwH += 0.00009 * (iwNoise(vBindPos * vec3(55.0, 70.0, 55.0)) - 0.5);
            iwAO *= vHair.z;
            iwGumOn = 1.0;
            iwGumThin = 1.0 - smoothstep(0.0015, 0.013, thick);
            iwGumTrans = mix(tsat, mix(tsat, vec3(1.0), 0.15), iwTipK);
            if (iwCup > 0.5) {
              // modelled suction cup: ring 0 = dish centre, 1 = rim top, → 1.4 = foot on the skin
              float ring = iwCup - 1.0;
              vec3 rimC = mix(tc, vec3(1.0), 0.42);
              vec3 dish = mix(core * 0.38, core * 0.8, smoothstep(0.15, 0.6, ring));   // dark mouth → deep dish wall
              vec3 cupC = ring < 1.0 ? mix(dish, rimC, smoothstep(0.55, 0.9, ring)) : mix(rimC, diffuseColor.rgb, smoothstep(1.02, 1.3, ring));
              // cups only a few pixels wide melt into the arm (no shimmering rims at mid distance)
              float cupLod = 1.0 - smoothstep(0.3, 0.7, fwidth(ring));
              diffuseColor.rgb = mix(mix(diffuseColor.rgb, rimC, 0.35), cupC, cupLod);
              iwAO *= mix(1.0, ring < 1.0 ? mix(0.55, 1.0, smoothstep(0.1, 0.8, ring)) : mix(1.0, 0.5, smoothstep(1.12, 1.4, ring)), cupLod);
              iwGumThin = ring < 1.0 ? 0.35 + 0.5 * smoothstep(0.4, 1.0, ring) : 0.6;
              iwSuck = 1.0;
            } else if (on > 0.75 && t > 0.3 && t < 0.97 && cs < -0.15) {
              // printed suction cups (low detail tiers only): two staggered rows along the underside
              float side = vSinA;
              float row = side > 0.0 ? 0.5 : 0.0;
              float fa = fract(dist / 0.021 + row) - 0.5;
              float lat = (abs(side) - 0.42) / 0.24;
              float size = mix(0.58, 0.34, smoothstep(0.35, 0.96, t));
              float d = length(vec2(fa * 1.2, lat));
              float w = max(fwidth(d), 1e-3);
              float under = smoothstep(-0.15, -0.5, cs);
              iwSuck = (1.0 - smoothstep(size - w, size + w, d)) * under;
              float ring = smoothstep(size * 0.35, size * 0.8, d) * iwSuck;
              float cup = (1.0 - smoothstep(size * 0.25, size * 0.6, d)) * iwSuck;
              diffuseColor.rgb = mix(diffuseColor.rgb, mix(tc, vec3(1.0), 0.45), iwSuck * 0.8);
              diffuseColor.rgb *= 1.0 - cup * 0.22;
              iwH += 0.0009 * ring - 0.0006 * cup;
            }
            // crevices: the baked occlusion also darkens the direct light a little (shadow maps miss them)
            diffuseColor.rgb *= mix(0.66, 1.0, vHair.z);
          }
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
roughnessFactor = iwGear > 0.5 ? (iwGearCls == 1.0 ? 0.26 : iwGearCls == 2.0 ? 0.85 : iwGearCls == 3.0 ? 0.7 : iwGearCls > 3.5 ? 0.84 : 0.3) : roughnessFactor; roughnessFactor = mix(roughnessFactor, 0.2, iwHurtM); roughnessFactor = mix(roughnessFactor, 0.42, iwSuck * (1.0 - step(0.5, iwCup)));
metalnessFactor = (iwGear > 0.5 && iwGearCls == 1.0) ? 1.0 : 0.0;
normal = iwBumpN(normal, iwH, -vViewPosition);
totalEmissiveRadiance += uFlash + (1.0 - iwGear) * uGlow * (0.6 + 0.4 * clamp(vTint + 0.5, 0.0, 1.0)) * (0.7 + 0.6 * iwGumThin);
ALBEDO=max(diffuseColor.rgb,vec3(0.0)); ROUGHNESS=clamp(roughnessFactor,0.04,1.0); METALLIC=clamp(metalnessFactor,0.0,1.0); NORMAL=normal; SPECULAR=0.5;
CLEARCOAT=0.8; CLEARCOAT_ROUGHNESS=0.12;

AO=clamp(iwAO,0.0,1.0);
EMISSION=totalEmissiveRadiance+vec3(hit_flash)+ALBEDO*rim_strength*pow(1.0-clamp(dot(normal,VIEW),0.0,1.0),3.2);
vec3 source_dxy=max(abs(dFdx(vNormal)),abs(dFdy(vNormal)));float geometryRoughness=max(source_dxy.x,max(source_dxy.y,source_dxy.z));
native_specularColor=vec3(0.04);native_specularColorBlended=mix(native_specularColor,diffuseColor.rgb,metalnessFactor);native_specularF90=mix(1.0,1.0,metalnessFactor);
native_clearcoat=1.0;native_clearcoatRoughness=clamp(max(0.05,0.0525)+geometryRoughness,0.0525,1.0);
native_sheenColor=vec3(1.0,1.0,1.0);native_sheenRoughness=0.4;

          if (iwGear > 0.5) { native_clearcoat = iwGearCls == 0.0 ? 1.0 : iwGearCls == 1.0 ? 0.3 : 0.0; native_clearcoatRoughness = 0.12; }
          else { native_clearcoat = mix(1.0, 0.55, iwSuck * (1.0 - step(0.5, iwCup))) * mix(0.35, 1.0, iwAO); native_clearcoatRoughness = min((iwCup > 0.5 ? 0.09 : 0.06) + geometryRoughness, 1.0); }

        // the soft base-layer lobe is light scattered back out of the jelly: tinted by it (the clearcoat stays white)
        if (iwGumOn > 0.5) { vec3 iwST = mix(vec3(1.0), iwGumTrans / max(max(iwGumTrans.r, max(iwGumTrans.g, iwGumTrans.b)), 1e-3), 0.6); native_specularColor *= iwST; native_specularColorBlended *= iwST; }

          native_sheenColor = iwGear > 0.5 ? (iwGearCls == 2.0 ? vec3(0.6) : iwGearCls > 3.5 ? mix(vec3(1.0), diffuseColor.rgb, 0.5) * 0.45 : vec3(0.0)) : mix(vec3(0.1), mix(uTeam, vec3(1.0), 0.6) * 0.22, iwTipK) * iwAO;
          native_sheenRoughness = 0.35;

native_clearcoat=clamp(native_clearcoat,0.0,1.0);native_clearcoatRoughness=clamp(native_clearcoatRoughness,0.0525,1.0);native_sheenRoughness=clamp(native_sheenRoughness,0.0001,1.0);
ROUGHNESS=clamp(max(roughnessFactor,0.0525)+geometryRoughness,0.0525,1.0);SPECULAR=0.5;CLEARCOAT=native_clearcoat;CLEARCOAT_ROUGHNESS=native_clearcoatRoughness;
float source_nv=clamp(dot(normalize(normal),normalize(VIEW)),0.0,1.0);vec2 source_fab=native_dfg(vec2(ROUGHNESS,source_nv));native_energy_comp=vec3(1.0)+native_specularColorBlended*(1.0/max(source_fab.x+source_fab.y,0.000001)-1.0);
native_coat_normal=normalize(vNormal);float source_cc_nv=clamp(dot(native_coat_normal,normalize(VIEW)),0.0,1.0);native_coat_attenuation=vec3(1.0)-native_clearcoat*native_schlick(vec3(0.04),1.0,source_cc_nv);
native_sss=0.0;native_thin=0.0;
native_gum_on=iwGumOn;native_gum_thin=iwGumThin;native_gum_trans=iwGumTrans;native_direct_ao=1.0;

vec3 source_world_normal=normalize((INV_VIEW_MATRIX*vec4(normal,0.0)).xyz);vec3 source_world_view=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);float hemi_mix=clamp(source_world_normal.y*0.5+0.5,0.0,1.0);vec3 source_hemi=mix(hemi_ground,hemi_sky,hemi_mix);
EMISSION*=native_coat_attenuation;
vec3 source_coat_world_normal=normalize((INV_VIEW_MATRIX*vec4(native_coat_normal,0.0)).xyz);
EMISSION+=native_source_indirect_coated(ALBEDO,METALLIC,native_specularColor,native_specularF90,ROUGHNESS,native_sheenColor,native_sheenRoughness,native_clearcoat,native_clearcoatRoughness,source_world_normal,source_world_view,source_hemi,AO,mix(0.4,1.0,AO),source_coat_world_normal);
EMISSION+=native_gum_on*native_gum_trans*(source_hemi+source_ibl_irradiance(source_world_normal)/PI)*(0.015+0.14*native_gum_thin*native_gum_thin)*AO*native_coat_attenuation;

vec3 rim_view=normalize(VIEW);
vec3 rim_direction=native_rim_world?normalize((VIEW_MATRIX*vec4(uIwRimL,0.0)).xyz):uIwRimL;
float rim_fresnel=pow(1.0-clamp(dot(normal,rim_view),0.0,1.0),uIwRim.w);
float rim_side=clamp(dot(normal,rim_direction)*0.5+0.5,0.0,1.0);
EMISSION+=uIwRim.rgb*(1.2*rim_fresnel*(0.3+0.7*rim_side*rim_side));
float rim_fill=clamp(dot(normal,normalize(vec3(0.25,0.45,1.0)))*0.6+0.4,0.0,1.0);
EMISSION+=uIwFill*diffuseColor.rgb*rim_fill*rim_fill;
}
