// Original INKWAVE sea equations, geometry and lookup fields.
shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled;
#define MARINA
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


uniform vec4 uRects[32];
uniform vec2 uRectAx[32];
uniform int uRectCount;
// axis-aligned rect given as (minX, minZ, maxX, maxZ) — the arena bounds
float sdRect(vec2 p, vec4 r) {
  vec2 c = (r.xy + r.zw) * 0.5; vec2 h = (r.zw - r.xy) * 0.5;
  vec2 q = abs(p - c) - h;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
// oriented rect: r = (centre, half extents), a = local x axis
float sdORect(vec2 p, vec4 r, vec2 a) {
  vec2 d = p - r.xy;
  vec2 q = abs(vec2(dot(d, a), dot(d, vec2(-a.y, a.x)))) - r.zw;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0);
}
float sdDeck(vec2 p) {
  float d = 1e5;
  for (int i = 0; i < 32; i++) { if (i >= uRectCount) break; d = min(d, sdORect(p, uRects[i], uRectAx[i])); }
  return d;
}
uniform vec4 uWet[12];
uniform vec2 uWetAx[12];
uniform int uWetCount;
uniform vec4 uArena;        // arena bounds (minX, minZ, maxX, maxZ): the harbour basin around it is sheltered
float basinK(vec2 p) { return smoothstep(60.0, 210.0, sdRect(p, uArena)); }   // 0 in the basin → 1 open sea
float sdWet(vec2 p) {
  float d = 1e5;
  for (int i = 0; i < 12; i++) { if (i >= uWetCount) break; d = min(d, sdORect(p, uWet[i], uWetAx[i])); }
  return d;
}

uniform sampler2D uWaveTex : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D uFoamTex : filter_linear, repeat_disable;
uniform vec4 uFoamRect;
uniform vec3 uSeaDeep;
uniform vec3 uSeaShallow;
uniform vec3 uSeaCrest;
uniform vec3 uFoamColor;
uniform vec3 uSunLight;
uniform vec3 uSeaAmbient;
uniform float uSunSpec;
uniform float uWaveStrength;
varying vec3 vWorld;
varying vec2 vSwellGrad;
varying float vDeckD;



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

uniform sampler2D uReflTex : filter_linear, repeat_disable;
uniform mat4 uReflMat;
uniform float uReflOn;
uniform samplerCube uFarCube : filter_linear_mipmap;   // far scenery (hills, city, port, bridge) baked from the arena centre, alpha = coverage
uniform float uFarOn;
uniform sampler2D uCloudTex : filter_linear, repeat_enable;
uniform vec4 uCloudParams;
uniform vec3 uChannelCol;
uniform vec3 uShadeCol;
uniform vec4 uMarinaK;     // x calm (wave-normal scale hugging faces), y face-ripple strength, z reflection distortion (m)
// distance (m) + outward unit gradient (world xz) to an oriented rect / the nearest rect of a set. The gradient is
// found in the rect's frame and rotated back (g.x·a + g.y·(−a.y, a.x)); exact for axis-aligned rects (a = (1, 0)).
vec3 sdORectG(vec2 p, vec4 r, vec2 a) {
  vec2 b = vec2(-a.y, a.x);
  vec2 d = p - r.xy;
  vec2 l = vec2(dot(d, a), dot(d, b));
  vec2 s = vec2(l.x < 0.0 ? -1.0 : 1.0, l.y < 0.0 ? -1.0 : 1.0);
  vec2 q = abs(l) - r.zw;
  vec3 o;
  if (max(q.x, q.y) > 0.0) { vec2 m = max(q, 0.0); float len = max(length(m), 1e-4); o = vec3(len, s * m / len); }
  else o = q.x > q.y ? vec3(q.x, s.x, 0.0) : vec3(q.y, 0.0, s.y);
  return vec3(o.x, o.y * a + o.z * b);
}
vec3 sdDeckG(vec2 p) {
  vec3 b = vec3(1e5, 0.0, 1.0);
  for (int i = 0; i < 32; i++) { if (i >= uRectCount) break; vec3 r = sdORectG(p, uRects[i], uRectAx[i]); if (r.x < b.x) b = r; }
  return b;
}
vec3 sdWetG(vec2 p) {
  vec3 b = vec3(1e5, 0.0, 1.0);
  for (int i = 0; i < 12; i++) { if (i >= uWetCount) break; vec3 r = sdORectG(p, uWet[i], uWetAx[i]); if (r.x < b.x) b = r; }
  return b;
}
vec3 skyRefl(vec3 R) {
  vec3 c = skyGradient(normalize(R + vec3(0.0, 0.015, 0.0)));
  float u = atan(R.z, R.x) / 6.28318531 + 0.5 + uTime * 0.00035 * uCloudParams.z;
  float v = pow(clamp(R.y, 0.0, 1.0), 1.0 / 1.6);
  vec4 cl = textureLod(uCloudTex, vec2(u, v), 0.0) * smoothstep(-0.002, 0.012, R.y);
  return c * (1.0 - cl.a) + cl.rgb;
}


// long gentle swell; returns height (unit amplitude) and writes gradient
float swell(vec2 p, float t, out vec2 g) {
  float h = 0.0; g = vec2(0.0);
  vec2 k; float ph;
  k = vec2(0.110, 0.047); ph = dot(p, k) + t * 0.95;        h += 0.45 * sin(ph); g += 0.45 * k * cos(ph);
  k = vec2(-0.052, 0.097); ph = dot(p, k) + t * 1.13 + 1.7; h += 0.35 * sin(ph); g += 0.35 * k * cos(ph);
  k = vec2(0.173, -0.141); ph = dot(p, k) + t * 1.61 + 4.1; h += 0.20 * sin(ph); g += 0.20 * k * cos(ph);
  return h;
}
float swellAmp(float dDeck) { return mix(0.035, 0.16, smoothstep(3.0, 70.0, dDeck)); }

float source_shadow(vec3 P){vec2 p=P.xz+uSunDir.xz*((-0.6-P.y)/max(uSunDir.y,0.06));return smoothstep(-0.2,0.45,sdDeck(p));}
void vertex(){source_camera=CAMERA_POSITION_WORLD;vec3 wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;float dd=sdDeck(wp.xz);
dd=min(dd,sdWet(wp.xz));
float amp=swellAmp(dd);amp*=mix(0.45,1.0,basinK(wp.xz));vec2 g;float h=swell(wp.xz,uTime,g);VERTEX.y+=h*amp;wp.y+=h*amp;vWorld=wp;vSwellGrad=g*amp;vDeckD=dd;}
void fragment(){
  vec3 P = vWorld;
  vec3 toCam = source_camera - P;
  float dist = length(toCam);
  vec3 V = toCam / dist;
  vec2 p = P.xz;
  float detail = 1.0 - smoothstep(35.0, 380.0, dist);

  // the per-rect work only matters near the stage: past 24 m from the arena every face is out of reach
  float dA = sdRect(p, uArena);
  vec3 gw = vec3(dA, 0.0, 1.0), gd = gw;
  if (dA < 24.0) {
    gw = sdWetG(p);
    if (gw.x < -0.03) discard;                     // inside a hull / over a sunken floor: no sea
    gd = sdDeckG(p);
  }
  vec3 gs = gd.x < gw.x ? gd : gw;                 // nearest face: distance + outward normal
  float dS = gs.x;
  float shelter = smoothstep(0.3, 9.0, max(dS, 0.0));

  vec4 w1 = texture(uWaveTex, p * 0.041 + uTime * vec2(0.012, 0.007));
  vec4 w2 = texture(uWaveTex, p * 0.097 + vec2(0.37, 0.61) + uTime * vec2(-0.019, 0.013));
  vec4 w3 = texture(uWaveTex, p * 0.0083 + uTime * vec2(0.0034, -0.0022));
  float nearF = 1.0 - smoothstep(6.0, 40.0, dist);
  vec4 w4 = texture(uWaveTex, p * 0.29 + vec2(0.71, 0.13) + uTime * vec2(0.031, -0.026));
  vec2 g = (w3.xy - 0.5) * 0.9 + ((w1.xy - 0.5) * 0.85 + (w2.xy - 0.5) * 0.55) * mix(0.3, 1.0, detail);
  float basin = smoothstep(60.0, 210.0, dA);   // = basinK(p)
  g *= uWaveStrength * 0.42 * mix(uMarinaK.x, 1.0, shelter) * mix(0.62, 1.0, basin);
  // fine cat's-paw ripples close to the camera are not damped: glassy, never dead flat
  g += (w4.xy - 0.5) * 0.45 * nearF * uWaveStrength * 0.42 * 0.85;
  // ripples bounced off the faces: crests parallel to the nearest face, running outward, gone within ~3 m
  float along = dot(p, vec2(-gs.z, gs.y));
  float ph1 = dS * 4.4 - uTime * 1.8 + sin(along * 0.62 + uTime * 0.55) * 0.9 + w2.z * 3.0;
  float ph2 = dS * 7.1 - uTime * 2.6 + sin(along * 1.25 - uTime * 0.45) * 0.8 + w1.z * 2.2;
  float lapA = uMarinaK.y * exp(-max(dS, 0.0) * 0.85) * smoothstep(-0.25, 0.1, dS) * (0.4 + 0.9 * w3.z);
  g += gs.yz * lapA * (0.055 * sin(ph1) + 0.03 * sin(ph2)) * detail;
  vec2 gRip = g;
  g += vSwellGrad;
  vec3 N = normalize(vec3(-g.x, 1.0, -g.y));
  float crest = (w1.z * 0.9 + w2.z * 0.5 + w3.z * 0.9) / 2.3;

  vec2 fuv = (p - uFoamRect.xy) * uFoamRect.zw;
  float inField = step(0.0, fuv.x) * step(fuv.x, 1.0) * step(0.0, fuv.y) * step(fuv.y, 1.0);
  float dObj = mix(uMarinaK.w, texture(uFoamTex, clamp(fuv, 0.0, 1.0)).r * uMarinaK.w, inField);

  // light: the shadow map (it covers every slab and hull here); no sky / sun under the floating slabs
  float shadow = source_shadow(P);
  float under = smoothstep(0.0, -0.8, gd.x);
  float skyVis = mix(0.55, 1.0, smoothstep(-0.2, 3.0, dS)) * (1.0 - 0.9 * under);

  vec3 body = mix(uSeaDeep, uSeaShallow, clamp(0.4 + 0.5 * (w3.z - 0.5), 0.0, 1.0));
  body = mix(uChannelCol, body, 0.3 + 0.7 * shelter);
  body += uSeaCrest * smoothstep(0.55, 0.95, crest) * (0.3 + 0.7 * shadow) * 0.3 * mix(0.25, 1.0, detail) * shelter;
  float NdL = max(dot(N, uSunDir), 0.0);
  vec3 lit = body * (uSeaAmbient * skyVis + uSunLight * (0.35 + 0.65 * NdL) * shadow * 0.5);

  // reflection: sky + clouds, then the planar reflection of everything standing above the water
  vec3 R = reflect(-V, N);
  R.y = abs(R.y);
  vec3 refl = skyRefl(R);
  float occl = 0.0;
  if (uFarOn > 0.5) {
    vec4 fc = textureLod(uFarCube, R, clamp(log2(1.0 + dist * 0.008) + length(gRip) * 4.0, 0.0, 5.0));
    float fa = clamp(fc.a, 0.0, 1.0);
    refl = refl * (1.0 - fa) + fc.rgb;
    occl = fa;
  }
  refl *= skyVis;
  if (uReflOn > 0.5) {
    vec2 off = (N.xz - vSwellGrad * 0.5) * uMarinaK.z;
    vec4 rp = uReflMat * vec4(P.x + off.x, -1.600, P.z + off.y, 1.0);
    vec2 ruv = rp.xy / max(rp.w, 1e-4);
    float lod = clamp(log2(1.0 + dist * 0.035) + length(gRip) * 5.0, 0.0, 4.5);
    vec4 rc = textureLod(uReflTex, clamp(ruv, 0.001, 0.999), lod);
    float ra = clamp(rc.a, 0.0, 1.0);   // coverage: anything additive in the mirror must never push it past 1
    refl = refl * (1.0 - ra) + rc.rgb;
    occl = max(occl, ra);
  }
  float NdV = clamp(dot(N, V), 0.0, 1.0);
  float fres = min((0.025 + 0.975 * pow(1.0 - NdV, 5.0)) * 1.1, 1.0);
  vec3 col = mix(lit, refl, fres);
  col = mix(col, uShadeCol * (uSeaAmbient + 0.02), under * 0.85);

  // sun glints (blocked by shadows and by anything reflected in front of the sky)
  float rs = clamp(dot(R, uSunDir), 0.0, 1.0);
  float spec = pow(rs, 1600.0) * 9.0 + pow(rs, 200.0) * 0.38 + pow(rs, 24.0) * 0.04;
  col += uSunLight * spec * uSunSpec * shadow * (1.0 - under) * (1.0 - occl);

  // foam — calm harbour water: a thin, broken froth line where the water laps a hull or anything standing in it (the
  // contour field: piles, fenders, moored boats), a few drifting clumps, faint rings pushed off by the lapping
  float dC = min(gw.x, dObj);                       // nearest thing standing in the water
  if (dC < 1.2) {
    float fn = w2.z * 0.6 + w1.z * 0.4;
    // non-repeating value noise (the wave texture tiles every ~1 m at froth scale)
    float nA = vnoise2(p * 3.3 + uTime * vec2(0.13, -0.09));
    float nB = vnoise2(p * 0.8 + vec2(17.0, 3.0) - uTime * vec2(0.05, 0.03));
    float froth = nA * 0.55 + nB * 0.45;
    float contact = smoothstep(0.03 + 0.07 * nA, 0.0, dC) * (0.35 + 0.65 * smoothstep(0.3, 0.7, nB)) * smoothstep(-0.04, 0.0, gw.x);
    float clump = smoothstep(0.66, 0.86, froth) * smoothstep(0.7, 0.05, dC) * smoothstep(0.35, 0.8, nB);
    float lapF = smoothstep(0.05, 0.0, abs(fract(dC * 1.5 - uTime * 0.2 + fn * 0.4) - 0.5) - 0.46)
      * smoothstep(1.1, 0.1, dC) * smoothstep(0.4, 0.75, nB);
    float foam = clamp(contact * 0.7 + clump * 0.35 + lapF * 0.15, 0.0, 1.0) * (1.0 - 0.8 * under);
    vec3 foamCol = uFoamColor * (uSeaAmbient * 1.2 * skyVis + uSunLight * (0.3 + 0.7 * shadow) * 0.55);
    col = mix(col, foamCol, foam * detail);
  }

  col = applyHaze(col, P);
  ALBEDO=max(col,vec3(0.0));
  }
