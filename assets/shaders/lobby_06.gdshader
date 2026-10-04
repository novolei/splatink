// Original built-in material colour/normal/weathering hooks 6.
shader_type spatial;
render_mode cull_disabled,fog_disabled;
uniform vec3 base_color=vec3(1.0,1.0,1.0);uniform vec3 emission_color=vec3(0.0,0.0,0.0);uniform float emission_intensity=1.0;uniform sampler2D emissive_map:filter_linear_mipmap;uniform float has_emissive_map=0.0;varying vec3 source_camera;
#define LS_TEXLIB
varying vec3 vLsW;

uniform vec3 uHzA; uniform vec3 uHzB; uniform vec4 uHzK; uniform float uHzStart;
float lsHazeAmt(vec3 w) {
  float d = max(distance(w, source_camera) - uHzStart, 0.0);
  float h = exp(-max(w.y, 0.0) * uHzK.y);
  return 1.0 - exp(-d * uHzK.x * (0.3 + 0.7 * h));
}
vec3 lsHazeCol(vec3 w) { return mix(uHzA, uHzB, smoothstep(uHzK.z, uHzK.w, -w.z) * (0.55 + 0.45 * exp(-max(w.y, 0.0) * 0.08))); }

uniform sampler2D tMask:filter_linear_mipmap; uniform vec4 uMaskR; uniform vec3 uTeamA; uniform vec3 uTeamB; uniform float uTime;
uniform sampler2D tRefl:filter_linear_mipmap; uniform mat4 uReflMat; uniform float uReflOn; uniform vec2 uReflRes; uniform vec4 uRip[6];
#ifdef LS_TEXLIB

uniform sampler2DArray tAlbedo:source_color,filter_linear_mipmap_anisotropic,repeat_enable; uniform sampler2DArray tNormal:filter_linear_mipmap_anisotropic,repeat_enable; uniform sampler2DArray tOrm:filter_linear_mipmap_anisotropic,repeat_enable; uniform vec4 uAs;
#include "res://assets/shaders/source_texlib.gdshaderinc"
#endif

float lsH(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float lsN(vec2 p) { vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(lsH(i), lsH(i + vec2(1, 0)), u.x), mix(lsH(i + vec2(0, 1)), lsH(i + vec2(1, 1)), u.x), u.y); }
float lsF(vec2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 4; i++) { s += a * lsN(p); p = mat2(vec2(1.6,1.2),vec2(-1.2,1.6)) * p + 7.1; a *= 0.5; } return s / 0.9375; }

      
uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);

float saturate(float x){return clamp(x,0.0,1.0);}
void vertex(){source_camera=CAMERA_POSITION_WORLD;vLsW=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){vec4 diffuseColor=vec4(base_color*COLOR.rgb,1.0);vec3 normal=NORMAL;vec3 vViewPosition=-VERTEX;float roughnessFactor=1.0;float metalnessFactor=0.0;vec3 totalEmissiveRadiance=emission_color*emission_intensity*mix(vec3(1.0),texture(emissive_map,vec2(UV.x,1.0-UV.y)).rgb,has_emissive_map);vec3 nativeReflection=vec3(0.0);vec3 gN = vec3(0.0, 0.0, 1.0);
float gRough = 0.8;
float gWater = 0.0;
float gDamp = 0.0;
float gInk = 0.0;
vec2 gRipN = vec2(0.0);
vec2 gTilt = vec2(0.0);
{
  vec2 p = vLsW.xz;
  vec3 alb = vec3(0.075, 0.074, 0.078);
#ifdef LS_TEXLIB
  TexlibSample ts = texlibSample(tAlbedo, tNormal, tOrm, p * uAs.y, uAs.x, int(uAs.z), int(uAs.w));
  alb *= ts.albedo.rgb * 1.25 * texlibMacro(p);
  alb *= mix(1.0, ts.orm.r, 0.7);
  gRough = ts.orm.g; gN = ts.normal;
#else
  alb *= 0.8 + 0.4 * lsN(p * 9.0) * lsN(p * 2.3);
  gRough = 0.82;
#endif
  // patched repairs: darker, smoother rectangles of newer asphalt
  vec2 pc = floor(p / vec2(2.7, 3.9)); float patchSel = step(0.8, lsH(pc + 3.0));
  vec2 pf = fract(p / vec2(2.7, 3.9)); float inPatch = patchSel * step(0.12, pf.x) * step(pf.x, 0.88) * step(0.1, pf.y) * step(pf.y, 0.9);
  alb *= mix(1.0, 0.7, inPatch);
  // painted mask (stage area) + procedural puddles further out + the drain gutter down the lane
  vec2 muv = vec2((p.x - uMaskR.x) / (uMaskR.z - uMaskR.x), 1.0 - (p.y - uMaskR.y) / (uMaskR.w - uMaskR.y));
  float inside = step(0.0, muv.x) * step(muv.x, 1.0) * step(0.0, muv.y) * step(muv.y, 1.0);
  vec3 m = texture(tMask, clamp(muv, 0.0, 1.0)).rgb * inside;
  float pn = lsF(p * vec2(0.42, 0.3) + 5.0);
  float far = smoothstep(-12.0, -16.0, p.y);
  float gut = (1.0 - smoothstep(0.1, 0.32, abs(p.x + 2.35))) * smoothstep(8.0, 5.0, p.y);
  float water = clamp(m.b * 1.6 - 0.12, 0.0, 1.0);
  water = max(water, smoothstep(0.6, 0.7, pn) * far);
  water = max(water, gut * (0.55 + 0.45 * smoothstep(0.35, 0.6, lsN(p * vec2(3.0, 0.4)))));
  gWater = water;
  gDamp = clamp(0.55 + 0.6 * (lsF(p * 0.55 + 1.3) - 0.5) + m.b * 0.6 + gut * 0.5, 0.0, 1.0);
  alb *= mix(1.0, 0.55, gDamp);
  alb *= mix(1.0, 0.35, water);
  // tyre-polished centre track (a touch smoother / darker where vans drive)
  float track = (1.0 - smoothstep(0.3, 0.9, abs(abs(p.x + 1.9) - 0.85))) * 0.25;
  alb *= 1.0 - track * 0.3;
  // oil stains
  float oil = smoothstep(0.72, 0.8, lsF(p * 0.9 + 17.0)) * 0.6;
  alb *= 1.0 - oil * 0.55;
  // ink splats: glossy, slightly raised, team coloured (normal flattened)
  float ia = clamp(m.r * 1.2, 0.0, 1.0), ib = clamp(m.g * 1.2, 0.0, 1.0);
  alb = mix(alb, uTeamA * 0.4, ia); alb = mix(alb, uTeamB * 0.4, ib);
  float ink = max(ia, ib);
  gInk = ink;
  // ink is a liquid film with a rounded rim: slope from the mask gradient (world metres) tilts the normal at its edges
  {
    vec2 du = vec2(0.025 / (uMaskR.z - uMaskR.x), 0.0), dv = vec2(0.0, 0.025 / (uMaskR.w - uMaskR.y));
    float hx = dot(texture(tMask, muv + du).rg - texture(tMask, muv - du).rg, vec2(1.0));
    float hz = -dot(texture(tMask, muv + dv).rg - texture(tMask, muv - dv).rg, vec2(1.0));
    gTilt = vec2(hx, hz) * 0.35 * inside;
  }
  gRough = mix(gRough, gRough * 0.42, gDamp);
  gRough = mix(gRough, 0.07, max(ink, track * 0.4));
  gRough = mix(gRough, 0.025, water);
  // drip ripples in standing water
  for (int i = 0; i < 6; i++) {
    vec4 r = uRip[i]; float age = uTime - r.z;
    if (age < 0.0 || age > 2.2) continue;
    vec2 dv = p - r.xy; float d = length(dv) + 1e-4;
    float front = age * 0.32;
    float env = exp(-age * 1.8) * smoothstep(front + 0.05, front - 0.03, d) * smoothstep(0.0, 0.03, d) * r.w;
    gRipN += (dv / d) * cos((d - front) * 70.0) * env * 0.6;
  }
  gRipN *= water;
  gTilt += gRipN;
  diffuseColor.rgb = alb;
}
roughnessFactor = gRough;

{
#ifdef LS_TEXLIB
  mat3 tbn = texlibTangentFrame(-vViewPosition, normal, vLsW.xz * uAs.y);
  normal = texlibPerturbNormal(normalize(gN + vec3(gRipN, 0.0) * 0.0), tbn, 1.0 - gWater * 0.92);
#endif
  // ripples + ink rims tilt the surface (world xz slope → view normal)
  if (dot(gTilt, gTilt) > 1e-6) {
    vec3 rw = normalize(vec3(-gTilt.x, 1.0, -gTilt.y));
    normal = normalize(mix(normal, (VIEW_MATRIX * vec4(rw, 0.0)).xyz, clamp(max(gWater, gInk), 0.0, 1.0)));
  }
}

// planar reflection: sharp in standing water, streaked + blurred on the damp film. Replaces the env-map specular
  // where it applies (the env map can't place the neon / door / kids correctly on the floor).
  if (uReflOn > 0.5) {
    vec4 rp = uReflMat * vec4(vLsW, 1.0);
    vec3 nw = (vec4(normal, 0.0) * VIEW_MATRIX).xyz;          // view → world normal
    vec2 ruv = rp.xy / rp.w + nw.xz * vec2(0.05, 0.08) * (1.0 - gWater * 0.6);
    float lod = mix(3.2, 0.2, gWater);
    float sp = mix(0.018, 0.003, gWater);
    vec3 rc = textureLod(tRefl, ruv, lod).rgb * 0.36
            + (textureLod(tRefl, ruv + vec2(0.0, sp), lod).rgb + textureLod(tRefl, ruv - vec2(0.0, sp), lod).rgb) * 0.22
            + (textureLod(tRefl, ruv + vec2(0.0, sp * 2.6), lod + 0.6).rgb + textureLod(tRefl, ruv - vec2(0.0, sp * 2.6), lod + 0.6).rgb) * 0.1;
    float NdV = saturate(dot(normal, VIEW));
    float F = 0.02 + 0.98 * pow(1.0 - NdV, 5.0);
    float k = clamp(gWater + gDamp * 0.5 + gInk * 0.5, 0.0, 1.0);
    nativeReflection = mix(nativeReflection, rc * F * mix(0.8, 1.0, gWater), k);
  }
float haze=lsHazeAmt(vLsW);ALBEDO=diffuseColor.rgb*(1.0-haze);ROUGHNESS=roughnessFactor;METALLIC=metalnessFactor;NORMAL=normal;EMISSION=(totalEmissiveRadiance+nativeReflection)*(1.0-haze)+lsHazeCol(vLsW)*haze;float hemi_mix=clamp((INV_VIEW_MATRIX[0].y*normal.x+INV_VIEW_MATRIX[1].y*normal.y+INV_VIEW_MATRIX[2].y*normal.z)*0.5+0.5,0.0,1.0);EMISSION+=ALBEDO*(1.0-METALLIC)*mix(hemi_ground,hemi_sky,hemi_mix);}
