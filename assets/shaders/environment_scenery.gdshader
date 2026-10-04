// Source scenery material hooks; native Godot PBR supplies direct lighting.
shader_type spatial;
render_mode cull_disabled,fog_disabled;

uniform vec3 base_color=vec3(1.0);uniform float base_roughness=0.8;uniform float base_metallic=0.0;
varying vec3 source_camera;


uniform float uTime;
uniform vec3 uSunDir;
uniform vec3 uZenith;
uniform vec3 uSkyMid;
uniform vec3 uHorizon;
uniform vec3 uGround;
uniform vec3 uHorizonGlow;
uniform vec3 uGlowColor;
uniform vec4 uGlowParams;   // x tight power, y tight strength, z horizon band sharpness, w wide strength
uniform vec4 uHaze;         // x density (1/m), y max, z height falloff (m)
uniform float uNight;

vec3 skyGradient(vec3 d) {
  float h = d.y;
  float hp = max(h, 0.0);
  float t = sqrt(hp);
  vec3 c = mix(uHorizon, uSkyMid, smoothstep(0.0, 0.52, t));
  c = mix(c, uZenith, smoothstep(0.4, 1.0, t));
  vec2 sh = normalize(uSunDir.xz + vec2(1e-5));
  vec2 dh = normalize(d.xz + vec2(1e-5));
  float az = dot(sh, dh) * 0.5 + 0.5;
  float band = exp(-hp * uGlowParams.z);
  c += uHorizonGlow * band * (0.2 + 0.8 * az * az * az);
  float sd = max(dot(normalize(vec3(d.x, hp, d.z)), uSunDir), 0.0);
  c += uGlowColor * (pow(sd, uGlowParams.x) * uGlowParams.y + pow(sd, 6.0) * uGlowParams.w);
  // dusk: the horizon opposite the sun lies in the earth's shadow — cooler and dimmer than the sunward side, so the
  // far shore / skyline away from the sun hazes into lavender-blue instead of glowing salmon (sky, env map and haze)
  float anti = (1.0 - az) * (1.0 - az);
  c *= mix(vec3(1.0), vec3(0.7, 0.74, 0.95), uNight * anti * exp(-hp * 2.5));
  c = mix(c, uGround, smoothstep(0.0, -0.22, h));
  return c;
}
vec3 hazeColor(vec3 d) {
  vec3 h = skyGradient(normalize(vec3(d.x, clamp(d.y, 0.0, 1.0) * 0.3, d.z)));
  h = mix(h, uSkyMid * 1.08 + uHorizon * 0.12, 0.22);   // aerial perspective: distant land turns bluer
  // looking down through the haze you see scattered ambient, not the glowing horizon band
  return mix(h, uGround * 1.15 + uSkyMid * 0.25, smoothstep(-0.02, -0.45, d.y) * 0.75);
}
vec3 applyHaze(vec3 col, vec3 wp) {
  vec3 dv = wp - source_camera;
  float dist = length(dv);
  vec3 dir = dv / max(dist, 1e-3);
  float hf = exp(-max(wp.y, 0.0) / uHaze.z);
  float f = 1.0 - exp(-dist * uHaze.x * mix(0.45, 1.0, hf));
  return mix(col, hazeColor(dir), min(f, uHaze.y));
}


float hash12(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float hash13(vec3 p3){ p3 = fract(p3 * 0.1031); p3 += dot(p3, p3.zyx + 31.32); return fract((p3.x + p3.y) * p3.z); }
float vnoise2(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f*f*(3.0-2.0*f);
  return mix(mix(hash12(i), hash12(i+vec2(1.0,0.0)), u.x), mix(hash12(i+vec2(0.0,1.0)), hash12(i+vec2(1.0,1.0)), u.x), u.y); }
float vnoise3(vec3 p){ vec3 i = floor(p), f = fract(p); vec3 u = f*f*(3.0-2.0*f);
  float a = hash13(i), b = hash13(i+vec3(1.0,0.0,0.0)), c = hash13(i+vec3(0.0,1.0,0.0)), d = hash13(i+vec3(1.0,1.0,0.0));
  float e = hash13(i+vec3(0.0,0.0,1.0)), f1 = hash13(i+vec3(1.0,0.0,1.0)), g = hash13(i+vec3(0.0,1.0,1.0)), h = hash13(i+vec3(1.0,1.0,1.0));
  return mix(mix(mix(a,b,u.x), mix(c,d,u.x), u.y), mix(mix(e,f1,u.x), mix(g,h,u.x), u.y), u.z); }
float fbm2(vec2 p){ float s = 0.0, a = 0.5; mat2 m = mat2(vec2(1.6,1.2),vec2(-1.2,1.6));
  for (int i = 0; i < 5; i++){ s += a * vnoise2(p); p = m * p + 3.7; a *= 0.5; } return s / 0.96875; }
// Round cumulus lobes: nearest jittered feature point; x = 1 - (d/r)^2 (>0 inside a puff), yz = offset from its centre.
vec3 lobes(vec2 p, float period){
  vec2 i = floor(p), f = fract(p);
  // smooth (soft-min) blend of neighbouring lobes → no Voronoi seams; creases between puffs stay soft
  float acc = 0.0; vec2 ob = vec2(0.0);
  for (int y = -1; y <= 1; y++) for (int x = -1; x <= 1; x++) {
    vec2 g = vec2(float(x), float(y));
    vec2 c = i + g;
    if (period > 0.0) c.x = mod(c.x, period);
    vec2 h = vec2(hash12(c), hash12(c + 17.31));
    float rad = 0.6 + 0.35 * hash12(c + 5.13);
    vec2 o = (g + 0.2 + 0.6 * h - f) / rad;
    float w = exp(-5.0 * dot(o, o));
    acc += w; ob -= w * o;
  }
  acc = max(acc, 1e-6);
  return vec3(1.0 + log(acc) / 5.0, ob / acc);
}
float fbm3(vec3 p){ float s = 0.0, a = 0.5;
  for (int i = 0; i < 5; i++){ s += a * vnoise3(p); p = p * 2.02 + vec3(1.7, 9.2, 4.1); a *= 0.5; } return s / 0.96875; }

#ifdef HZ_CITY
varying vec3 vBld;
float aaBand(float x, float a, float b, float w) { return smoothstep(a - w, a + w, x) * smoothstep(b + w, b - w, x); }
float aaLine(float x, float hw, float w) { float d = min(x, 1.0 - x); return smoothstep(hw + w, hw - w, d); }

#endif
varying float vGlow;
varying vec3 vHzWorld;
varying vec3 vHzNormal;
varying float vHzSeed;


   // night lights: added after the haze so they punch through it (and bloom)

void vertex(){source_camera=CAMERA_POSITION_WORLD;
#ifdef HZ_GULL
{
  float side = abs(VERTEX.x);
  float glide = 0.35 + 0.65 * smoothstep(-0.3, 0.6, sin(uTime * 0.55 + INSTANCE_CUSTOM.x * 17.0));
  float flap = sin(uTime * 8.5 + INSTANCE_CUSTOM.x * 6.2831);
  VERTEX.y += flap * glide * side * 0.62 * smoothstep(0.08, 0.35, side);
  VERTEX.y -= 0.12 * side * side;
}
#endif
vHzWorld=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vHzNormal=normalize(mat3(MODEL_MATRIX)*NORMAL);vHzSeed=fract(sin(dot(MODEL_MATRIX[3].xz,vec2(12.9898,78.233)))*43758.5453);vGlow=CUSTOM0.x;
#ifdef HZ_CITY
vBld=CUSTOM1.xyz;
#endif
}
void fragment(){vec4 diffuseColor=vec4(base_color*COLOR.rgb,1.0);float roughnessFactor=base_roughness;vec3 totalEmissiveRadiance=vec3(0.0);float hzWin=0.0;float hzLit=0.0;vec3 hzEmit=vec3(0.0);
#ifdef HZ_CITY
vec3 hzLitCol=vec3(0.0);
#endif

#ifdef HZ_CITY
{
  // facade styles (vBld.x): 0 solid, 1 punched windows w/ mullion, 2 ribbon bands, 3 curtain wall, 4 vertical piers, 5 bands only (round towers)
  vec3 wn = normalize(vHzNormal);
  float style = floor(vBld.x + 0.5);
  float seed = vBld.y;
  float v = vHzWorld.y - vBld.z;
  if (style > 0.5 && abs(wn.y) < 0.5) {
    vec2 tdir = normalize(vec2(-wn.z, wn.x));
    float u = dot(vHzWorld.xz, tdir) + seed * 37.0;
    float bay = style < 1.5 ? 3.3 : style < 2.5 ? 1.7 : style < 3.5 ? 1.5 : style < 4.5 ? 2.8 : 2.0;
    float flH = style < 2.5 ? 3.5 : 3.9;
    vec2 cell = vec2(u / bay, v / flH);
    vec2 f = fract(cell), id = floor(cell);
    vec2 fw = fwidth(cell);
    float far = smoothstep(0.22, 0.75, max(fw.x, fw.y));
    float glass = 0.0, mull = 0.0, avg = 0.5;
    if (style < 1.5) {
      glass = aaBand(f.x, 0.2, 0.8, fw.x) * aaBand(f.y, 0.27, 0.86, fw.y);
      mull = aaBand(f.x, 0.485, 0.515, fw.x) * glass;
      avg = 0.6 * 0.59;
    } else if (style < 2.5) {
      glass = aaBand(f.y, 0.3, 0.9, fw.y);
      mull = aaLine(f.x, 0.04, fw.x) * glass;
      avg = 0.58;
    } else if (style < 3.5) {
      glass = 1.0;
      mull = max(aaLine(f.x, 0.035, fw.x), aaLine(f.y, 0.05, fw.y) * 0.8);
      avg = 0.86;
    } else if (style < 4.5) {
      glass = aaBand(f.x, 0.32, 0.92, fw.x) * aaBand(f.y, 0.06, 0.97, fw.y);
      mull = aaLine(f.y, 0.04, fw.y) * glass;
      avg = 0.52;
    } else {
      glass = aaBand(f.y, 0.36, 0.9, fw.y);
      avg = 0.54;
    }
    glass = mix(glass * (1.0 - mull), avg, far);
    // ground-floor storefront band, and no glass right at the roofline
    glass = mix(glass, 0.75 * smoothstep(0.5, 0.9, v), 1.0 - smoothstep(3.6, 4.2, v));
    float r = hash12(id + seed * 113.0);
    vec3 gcol = mix(vec3(0.11, 0.16, 0.23), vec3(0.2, 0.27, 0.33), r);                 // blinds / interiors vary per window
    if (style > 2.5 && style < 3.5) gcol = mix(vec3(0.24, 0.37, 0.47), vec3(0.34, 0.47, 0.55), r * 0.7) * mix(0.9, 1.08, fract(seed * 7.1));
    gcol = mix(gcol, vec3(0.22, 0.29, 0.36), far);
    diffuseColor.rgb = mix(diffuseColor.rgb, gcol, glass);
    diffuseColor.rgb *= 1.0 - mull * 0.3 * (1.0 - far);
    // floor-line grooves on the solid parts
    diffuseColor.rgb *= 1.0 - 0.07 * aaLine(f.y, 0.025, fw.y) * (1.0 - glass) * (1.0 - far);
    hzWin = glass;
    float lit = step(r, style > 2.5 && style < 3.5 ? 0.34 : 0.44);
    lit = mix(lit, 0.38, far);
    vec3 lc = mix(vec3(1.0, 0.72, 0.4), vec3(0.8, 0.88, 1.0), step(0.78, hash12(id * 1.7 + seed)));
    hzLitCol = lc * lit * glass;
  }
}
#endif
#ifdef HZ_TERRAIN
{
  // stylised hills: meadow grass on gentle slopes, clumpy woodland canopy, warm dry meadows on the tops, layered rock on
  // steep faces, a sand + wet-sand beach line at the shore; vGlow carries baked fold AO
  vec3 wn = normalize(vHzNormal);
  float hgt = vHzWorld.y - -1.600;
  vec2 tp = vHzWorld.xz;
  float n1 = fbm2(tp * 0.011);
  float n2 = vnoise2(tp * 0.05) * 0.6 + vnoise2(tp * 0.17) * 0.4;
  float nt = vnoise2(tp * 0.3) * 0.55 + vnoise2(tp * 0.83 + 7.0) * 0.45;
  vec3 tint = diffuseColor.rgb;
  float slope = 1.0 - wn.y;
  vec3 grass = tint * mix(0.9, 1.08, n1);
  float wood = smoothstep(0.47, 0.62, n1 + (n2 - 0.5) * 0.3) * smoothstep(0.62, 0.3, slope) * smoothstep(1.5, 5.0, hgt);
  vec3 canopy = tint * vec3(0.5, 0.66, 0.52) * mix(0.68, 1.14, smoothstep(0.3, 0.78, nt));
  grass = mix(grass, canopy, wood * 0.92);
  grass = mix(grass, tint * vec3(1.12, 1.06, 0.8), smoothstep(0.34, 0.12, n1) * (1.0 - wood) * 0.5);
  vec3 rock = vec3(0.56, 0.55, 0.51) * (0.82 + 0.3 * n2);
  rock *= 0.9 + 0.1 * sin(vHzWorld.y * 0.85 + n2 * 5.0);
  float rockM = smoothstep(0.34, 0.54, slope + (n2 - 0.5) * 0.2) * 0.88;
  vec3 sand = vec3(0.95, 0.88, 0.72) * (0.95 + 0.08 * n2);
  float sandM = smoothstep(1.6, 0.6, hgt + (n1 - 0.5) * 1.6);
  vec3 c = mix(grass, rock, rockM);
  c = mix(c, sand, sandM);
  c = mix(c, sand * vec3(0.72, 0.7, 0.66), smoothstep(0.45, 0.1, hgt) * sandM);
  diffuseColor.rgb = c * vGlow;
}
#endif
#ifdef HZ_WATERLINE
{
  float wl = vHzWorld.y - -1.600;
  diffuseColor.rgb *= mix(0.5, 1.0, smoothstep(0.0, 0.45, wl));
  diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.16, 0.27, 0.18), smoothstep(0.3, 0.0, wl) * 0.55);
}
#endif
#ifdef HZ_SHORE
{
  float wl = vHzWorld.y - -1.600;
  float wob = 0.12 * sin(uTime * 1.2 + vHzWorld.x * 0.21 + vHzWorld.z * 0.17);
  diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.95, 0.97, 0.98), smoothstep(0.45, 0.05, abs(wl - 0.12 - wob)) * 0.85);
}
#endif

#ifdef HZ_CITY
roughnessFactor = mix(roughnessFactor, 0.14, hzWin);
#endif

{
  float blink = step(0.55, fract(uTime * 0.7 + vHzWorld.x * 0.013 + vHzWorld.z * 0.007));
#ifndef HZ_TERRAIN
  float gAmt = vGlow > 1.5 ? blink * 1.5 : vGlow;
  hzEmit += COLOR.rgb * gAmt * (vGlow > 1.5 ? max(uNight, 0.35) : uNight) * 7.0;
#endif
#ifdef HZ_CITY
  hzEmit += uNight * hzLitCol * 1.5;   // warm lit windows, not white: 3.0 blew them out through the tone curve
#endif
#ifdef HZ_WATERLINE
  float wl2 = vHzWorld.y - -1.600;
  vec2 cq = vHzWorld.xz * 1.7 + vec2(vHzWorld.y * 2.3, 0.0);
  float cz = sin(cq.x + uTime * 1.3 + sin(cq.y * 1.3 + uTime * 0.9) * 1.6) * sin(cq.y * 1.1 - uTime * 1.1 + sin(cq.x * 0.9 - uTime * 0.7) * 1.4);
  float side = 1.0 - abs(normalize(vHzNormal).y);
  totalEmissiveRadiance += uGlowColor * 0.07 * side * smoothstep(0.45, 0.95, cz) * smoothstep(1.1, 0.15, wl2) * step(0.0, wl2);
#endif
}

vec3 dv=vHzWorld-source_camera;float dist=length(dv);vec3 dir=dv/max(dist,0.001);float hf=exp(-max(vHzWorld.y,0.0)/uHaze.z);float f=min(1.0-exp(-dist*uHaze.x*mix(0.45,1.0,hf)),uHaze.y);
#ifdef HZ_CITY
vec3 wn2=normalize(vHzNormal);vec3 refl=min(skyGradient(normalize(reflect(dir,wn2)+vec3(0.0,0.02,0.0))),vec3(1.1));float fres=0.05+0.95*pow(1.0-clamp(dot(-dir,wn2),0.0,1.0),5.0);totalEmissiveRadiance+=refl*mix(0.92,0.55,uNight)*hzWin*clamp(0.18+fres*0.75,0.0,0.85)*(1.0-uNight*0.75);diffuseColor.rgb*=1.0-0.38*uNight;
#endif
ALBEDO=max(diffuseColor.rgb,vec3(0.0))*(1.0-f);ROUGHNESS=roughnessFactor;METALLIC=base_metallic;EMISSION=hazeColor(dir)*f+(totalEmissiveRadiance+hzEmit*exp(-dist*uHaze.x*0.35))*(1.0-f);}
