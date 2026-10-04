// Original built-in material colour/normal/weathering hooks 2.
shader_type spatial;
render_mode cull_disabled,fog_disabled;
uniform vec3 base_color=vec3(1.0,1.0,1.0);uniform vec3 emission_color=vec3(0.0,0.0,0.0);uniform float emission_intensity=1.0;uniform sampler2D emissive_map:filter_linear_mipmap;uniform float has_emissive_map=0.0;varying vec3 source_camera;
#define LS_TEXLIB
varying vec3 vLsW;

varying vec2 vUvM; varying vec4 vSurf; varying vec3 vDec; varying vec3 vWN;

uniform vec3 uHzA; uniform vec3 uHzB; uniform vec4 uHzK; uniform float uHzStart;
float lsHazeAmt(vec3 w) {
  float d = max(distance(w, source_camera) - uHzStart, 0.0);
  float h = exp(-max(w.y, 0.0) * uHzK.y);
  return 1.0 - exp(-d * uHzK.x * (0.3 + 0.7 * h));
}
vec3 lsHazeCol(vec3 w) { return mix(uHzA, uHzB, smoothstep(uHzK.z, uHzK.w, -w.z) * (0.55 + 0.45 * exp(-max(w.y, 0.0) * 0.08))); }

   
uniform sampler2D tDecal:filter_linear_mipmap; uniform vec3 uTeamA; uniform vec3 uTeamB; uniform float uTime;
#ifdef LS_TEXLIB

uniform sampler2DArray tAlbedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable; uniform sampler2DArray tNormal:filter_linear_mipmap_anisotropic,repeat_enable; uniform sampler2DArray tOrm:filter_linear_mipmap_anisotropic,repeat_enable;
uniform vec4 uTL[12]; uniform vec4 uTLt[12];
#include "res://assets/shaders/source_texlib.gdshaderinc"
#endif

float lsH(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float lsN(vec2 p) { vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(lsH(i), lsH(i + vec2(1, 0)), u.x), mix(lsH(i + vec2(0, 1)), lsH(i + vec2(1, 1)), u.x), u.y); }
float lsF(vec2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 4; i++) { s += a * lsN(p); p = mat2(vec2(1.6,1.2),vec2(-1.2,1.6)) * p + 7.1; a *= 0.5; } return s / 0.9375; }

   
uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);

float saturate(float x){return clamp(x,0.0,1.0);}
void vertex(){source_camera=CAMERA_POSITION_WORLD;vLsW=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vSurf=CUSTOM0;vDec=CUSTOM1.xyz;vUvM=vec2(UV.x,1.0-UV.y);vWN=normalize(mat3(MODEL_MATRIX)*NORMAL);}
void fragment(){vec4 diffuseColor=vec4(base_color*COLOR.rgb,1.0);vec3 normal=NORMAL;vec3 vViewPosition=-VERTEX;float roughnessFactor=1.0;float metalnessFactor=0.0;vec3 totalEmissiveRadiance=emission_color*emission_intensity*mix(vec3(1.0),texture(emissive_map,vec2(UV.x,1.0-UV.y)).rgb,has_emissive_map);vec3 nativeReflection=vec3(0.0);vec3 gN = vec3(0.0, 0.0, 1.0);
float gNS = 0.0;
float gRough = 0.7;
float gMetal = 0.0;
{
  int slot = int(vSurf.x + 0.5);
  vec3 tint = diffuseColor.rgb, base = tint;
  vec3 wp = vLsW; vec3 wn = normalize(vWN);
  float vert = 1.0 - abs(wn.y);
  gRough = 0.7 * vSurf.z; gMetal = vSurf.w;
#ifdef LS_TEXLIB
  vec4 tl = uTL[slot]; vec4 tt = uTLt[slot];
  TexlibSample ts = texlibSample(tAlbedo, tNormal, tOrm, vUvM * tl.y, tl.x, int(tl.z), int(tl.w));
  if (tt.x > -0.5) {
    base = tt.x > 1.5 ? ts.albedo.rgb + tint * ts.albedo.a * 1.25 : (tt.x > 0.5 ? tint * ts.albedo.rgb * 1.25 : ts.albedo.rgb);
    base *= mix(1.0, ts.orm.r, 0.8);
    gRough = clamp(ts.orm.g * vSurf.z, 0.03, 1.0);
    gN = ts.normal; gNS = tt.y;
    if (slot == 9 && ts.albedo.a < 0.5) discard;   // grate openings
  }
#else
  if (slot == 1) {   // procedural brick fallback: 0.23 x 0.075 m running bond
    vec2 b = vUvM / vec2(0.23, 0.075); b.x += 0.5 * floor(b.y);
    vec2 f = fract(b); float m = step(0.06, f.x) * step(0.1, f.y);
    base = tint * mix(0.55, 0.9 + 0.2 * lsH(floor(b)), m);
  } else base = tint * (0.9 + 0.2 * lsN(vUvM * 3.0));
#endif
  // weathering, all world-space (walls never repeat their dirt): blotchy grime, damp streaks running down from
  // ledges, a dark wet splash band at the foot of every wall, contact darkening where walls meet the ground
  float gr = vSurf.y;
  if (gr > 0.0) {
    float hc = dot(wp.xz, vec2(-wn.z, wn.x));
    float blot = lsF(vec2(hc, wp.y) * 0.45 + wp.xz * 0.05);
    float st = lsF(vec2(hc * 2.6, wp.y * 0.16 + 3.0 * lsN(vec2(hc * 0.4, 1.7))));
    float streak = smoothstep(0.5, 0.82, st) * vert;
    float band = (1.0 - smoothstep(0.04, 0.3 + 0.35 * lsN(vec2(hc * 1.7, 2.0)), wp.y)) * vert;
    float grime = gr * (0.6 * smoothstep(0.3, 0.8, blot) + 0.55 * streak);
    base *= 1.0 - 0.5 * grime;
    base *= mix(1.0, 0.5, band * min(gr * 1.5, 1.0));
    base *= mix(0.55, 1.0, smoothstep(0.0, 0.8, wp.y) * vert + (1.0 - vert));
    gRough = mix(gRough, gRough * 0.4, clamp(streak * 0.7 + band, 0.0, 1.0) * min(gr * 1.5, 1.0));
    // tops of things are rain-wet
    gRough *= mix(1.0, 0.55, smoothstep(0.6, 0.95, wn.y) * gr);
  }
  // decals (channel encoded): teamA*R + teamB*G + white*B over black; mode 1/2 = paint on this surface,
  // 3/4 = decal-only quad (discards outside the paint), even modes swap the team channels
  if (vDec.z > 0.5) {
    vec4 d = texture(tDecal, vDec.xy);
    if (mod(vDec.z + 0.5, 2.0) < 1.0) d.rg = d.gr;
    float wear = smoothstep(0.45, 0.85, lsF(vUvM * 2.3 + 11.0)) * 0.75 + smoothstep(0.5, 0.9, lsN(vUvM * 14.0)) * 0.25;
    float cov = d.a * (1.0 - wear * 0.8);
    if (vDec.z > 2.5 && cov < 0.08) discard;
    vec3 paint = uTeamA * d.r * 0.85 + uTeamB * d.g * 0.85 + vec3(0.72) * d.b;
    base = mix(base, paint * mix(1.0, 0.8, gr), cov);
    gRough = mix(gRough, 0.5, cov * 0.7);
    gNS *= 1.0 - 0.5 * cov;
  }
  diffuseColor.rgb = base;
}
roughnessFactor = gRough;
metalnessFactor = gMetal;
#ifdef LS_TEXLIB
  { int slot = int(vSurf.x + 0.5); mat3 tbn = texlibTangentFrame(-vViewPosition, normal, vUvM * uTL[slot].y);
    if (gNS > 0.0) normal = texlibPerturbNormal(gN, tbn, gNS); }
#endif


float haze=lsHazeAmt(vLsW);ALBEDO=diffuseColor.rgb*(1.0-haze);ROUGHNESS=roughnessFactor;METALLIC=metalnessFactor;NORMAL=normal;EMISSION=(totalEmissiveRadiance+nativeReflection)*(1.0-haze)+lsHazeCol(vLsW)*haze;float hemi_mix=clamp((INV_VIEW_MATRIX[0].y*normal.x+INV_VIEW_MATRIX[1].y*normal.y+INV_VIEW_MATRIX[2].y*normal.z)*0.5+0.5,0.0,1.0);EMISSION+=ALBEDO*(1.0-METALLIC)*mix(hemi_ground,hemi_sky,hemi_mix);}
