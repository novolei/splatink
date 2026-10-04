// Original INKWAVE sea equations, geometry and lookup fields.
shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled;
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

float amp=swellAmp(dd);vec2 g;float h=swell(wp.xz,uTime,g);VERTEX.y+=h*amp;wp.y+=h*amp;vWorld=wp;vSwellGrad=g*amp;vDeckD=dd;}
void fragment(){
  vec3 P = vWorld;
  vec3 toCam = source_camera - P;
  float dist = length(toCam);
  vec3 V = toCam / dist;
  vec2 p = P.xz;
  float detail = 1.0 - smoothstep(35.0, 380.0, dist);

  vec4 w1 = texture(uWaveTex, p * 0.041 + uTime * vec2(0.012, 0.007));
  vec4 w2 = texture(uWaveTex, p * 0.097 + vec2(0.37, 0.61) + uTime * vec2(-0.019, 0.013));
  vec4 w3 = texture(uWaveTex, p * 0.0083 + uTime * vec2(0.0034, -0.0022));
  float nearF = 1.0 - smoothstep(6.0, 40.0, dist);
  vec4 w4 = texture(uWaveTex, p * 0.29 + vec2(0.71, 0.13) + uTime * vec2(0.031, -0.026));
  vec2 g = (w3.xy - 0.5) * 0.9 + ((w1.xy - 0.5) * 0.85 + (w2.xy - 0.5) * 0.55) * mix(0.3, 1.0, detail) + (w4.xy - 0.5) * 0.45 * nearF;
  g = g * uWaveStrength * 0.42 + vSwellGrad;
  vec3 N = normalize(vec3(-g.x, 1.0, -g.y));
  float crest = (w1.z * 0.9 + w2.z * 0.5 + w3.z * 0.9) / 2.3;

  float dEdge = sdDeck(p);
  // the sea never shows through inside the arena footprint (e.g. dry-dock trenches below sea level)
  if (dEdge < -0.05) discard;
  vec2 fuv = (p - uFoamRect.xy) * uFoamRect.zw;
  float inField = step(0.0, fuv.x) * step(fuv.x, 1.0) * step(0.0, fuv.y) * step(fuv.y, 1.0);
  float dObj = mix(8.0, texture(uFoamTex, clamp(fuv, 0.0, 1.0)).r * 8.0, inField);

  // shadows: real shadow map (deck, walls, boats) + analytic deck-slab shadow as a fallback outside the shadow camera
  float sm = source_shadow(P);
  vec2 q = p + uSunDir.xz * ((-0.6 - P.y) / max(uSunDir.y, 0.06));
  float ash = smoothstep(-0.2, 0.45, sdDeck(q));
  float shadow = min(sm, ash);
  float under = smoothstep(0.3, -2.4, dEdge);

  // body colour: turquoise shallows near the pier, deep blue further out; crests catch light
  float shallow = smoothstep(8.0, 0.5, dEdge) * (0.7 + 0.6 * (w3.z - 0.5));
  vec3 body = mix(uSeaDeep, uSeaShallow, clamp(shallow, 0.0, 1.0) * 0.6);
  body += uSeaCrest * smoothstep(0.55, 0.95, crest) * (0.3 + 0.7 * shadow) * 0.4 * mix(0.25, 1.0, detail);
  float NdL = max(dot(N, uSunDir), 0.0);
  vec3 lit = body * (uSeaAmbient + uSunLight * (0.4 + 0.6 * NdL) * shadow * 0.55);

  // reflection of the sky
  vec3 R = reflect(-V, N);
  R.y = abs(R.y);
  vec3 refl = skyGradient(normalize(R + vec3(0.0, 0.015, 0.0)));
  float NdV = clamp(dot(N, V), 0.0, 1.0);
  float fres = 0.035 + 0.965 * pow(1.0 - NdV, 5.0);
  fres = min(fres * 1.1, 1.0);
  vec3 col = mix(lit, refl, fres * mix(1.0, 0.45, under));
  col *= mix(1.0, 0.2, under);

  // sun glint: broad sheen + tight sparkles from the fine normals
  float rs = clamp(dot(R, uSunDir), 0.0, 1.0);
  float spec = pow(rs, 1600.0) * 9.0 + pow(rs, 200.0) * 0.38 + pow(rs, 24.0) * 0.04;
  col += uSunLight * spec * uSunSpec * shadow * (1.0 - under);

  // foam: lapping band along the deck edge, rings around pilings / boats / buoys
  float fn = w2.z * 0.6 + w1.z * 0.4;
  float edgeF = smoothstep(0.75, 0.0, dEdge + (fn - 0.5) * 0.9) * smoothstep(-1.0, -0.2, dEdge);
  float lapPhase = fract(dEdge * 0.7 - uTime * 0.3);
  float lap = smoothstep(0.1, 0.0, abs(lapPhase - 0.5) - 0.4) * smoothstep(3.4, 0.5, dEdge) * step(0.0, dEdge);
  lap *= smoothstep(0.35, 0.7, fn + 0.15);
  float objF = smoothstep(0.55, 0.0, dObj + (fn - 0.5) * 0.45);
  objF += 0.45 * smoothstep(0.1, 0.0, abs(fract(dObj * 0.9 - uTime * 0.35) - 0.5) - 0.42) * smoothstep(2.2, 0.4, dObj) * smoothstep(0.35, 0.7, fn + 0.1);
  float foam = clamp(edgeF + lap * 0.5 + objF, 0.0, 1.0) * mix(1.0, 0.35, under);
  vec3 foamCol = uFoamColor * (uSeaAmbient * 1.3 + uSunLight * (0.35 + 0.65 * shadow) * 0.6);
  col = mix(col, foamCol, foam * detail);

  col = applyHaze(col, P);
  ALBEDO=max(col,vec3(0.0));
  }
