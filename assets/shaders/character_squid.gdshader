// Generated from source material squid; original authored color/detail equations.
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
uniform vec3 uTeam = vec3(1.0,0.25415209,0.00699541); uniform vec3 uFlash = vec3(0.0,0.0,0.0); uniform vec3 uGlow = vec3(0.0,0.0,0.0); uniform float uOpacity = 1.0; varying float vTint; varying vec2 vSqUv; varying float vSqPart; varying vec3 vSqP; varying vec3 vSq;
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

  
vec3 iwSat(vec3 c, float k){ float l = dot(c, vec3(0.2126, 0.7152, 0.0722)); return max(mix(vec3(l), c, k), 0.0); }

uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);
#include "res://assets/shaders/character_lighting.gdshaderinc"
#include "res://assets/shaders/source_cube_uv.gdshaderinc"
#include "res://assets/shaders/character_indirect.gdshaderinc"
varying vec2 vSqWig; uniform float uTime=0.0; uniform vec3 uWig=vec3(0.012,9.0,0.0);
vec4 source_read(vec2 coord,float slot,vec4 lo,vec4 hi){vec4 a=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0)/24.0))*255.0+0.5);vec4 b=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0+1.0)/24.0))*255.0+0.5);return mix(lo,hi,(a*256.0+b)/65535.0);}
void vertex(){
vec4 d0=source_read(UV2,float(0),data_min_0,data_max_0);
vec4 d1=source_read(UV2,float(1),data_min_1,data_max_1);
vec4 d2=source_read(UV2,float(2),data_min_2,data_max_2);
vec4 d8=source_read(UV2,float(8),data_min_8,data_max_8);
vTint=d1.r; vSqUv=d2.xy; vSqPart=d0.w; vSqP=d0.xyz; vSq=d8.xyz; vSqWig=d1.gb;

float wig=d1.g; float ph=d1.b*6.2831; float wave=sin(uTime*uWig.y+ph-wig*4.2); float co=cos(uTime*uWig.y*0.8+ph*1.3-wig*3.1); float k=wig*wig*uWig.x*2.0; vec2 rad=normalize(VERTEX.xz+vec2(0.00001)); VERTEX.xz+=rad*(wave*k*1.1)+vec2(-rad.y,rad.x)*(co*k*0.9); VERTEX.y+=(wave*0.5+0.5)*wig*uWig.x*0.8+wave*k*0.35;
}
void fragment(){
vec4 diffuseColor=vec4(vec3(1.0),1.0); vec3 normal=NORMAL; vec3 vNormal=NORMAL; vec3 vViewPosition=-VERTEX; float roughnessFactor=0.3; float metalnessFactor=0.0; vec3 totalEmissiveRadiance=vec3(0.0);
vec3 iwGumTrans = vec3(0.0);
float iwGumThin = 0.0;
float iwGumOn = 0.0;
float iwH = 0.0; float iwSuck = 0.0; float iwAO = 1.0; float iwCup = 0.0; float iwTipK = 0.0;
        {
          vec3 tc = uTeam;
          float lum = dot(tc, vec3(0.299, 0.587, 0.114));
          vec3 light = mix(tc, vec3(1.0), 0.6);
          vec3 dark = tc * mix(1.0, 0.5, clamp(lum * 1.4, 0.0, 1.0));
          vec3 core = pow(max(tc, vec3(1e-4)), vec3(1.45)) * mix(0.82, 0.92, clamp(lum * 1.2, 0.0, 1.0));
          vec3 base = vTint >= 0.0 ? mix(tc, light, clamp(vTint, 0.0, 1.0)) : mix(tc, dark, clamp(-vTint, 0.0, 1.0));
          float nv = clamp(dot(normalize(vNormal), normalize(vViewPosition)), 0.0, 1.0);
          float thick = vSq.x;
          float deep = smoothstep(0.003, 0.03, thick * (0.25 + 0.75 * nv));
          diffuseColor.rgb = mix(base, mix(base, core, 0.7), deep);
          iwAO = vSq.z;
          iwGumOn = 1.0;
          iwGumThin = 1.0 - smoothstep(0.0015, 0.016, thick);
          iwGumTrans = iwSat(tc, 1.4);
          iwH += 0.00008 * (iwNoise(vSqP * vec3(60.0)) - 0.5);
          if (vSqPart > 0.5 && vSqPart < 3.5 && vSqPart != 2.0) {
            // arm
            float t = vSqUv.x, cs = vSqUv.y;
            iwTipK = smoothstep(0.55, 1.0, t);
            diffuseColor.rgb *= mix(0.86, 1.04, t);
            diffuseColor.rgb = mix(diffuseColor.rgb, mix(base, light, 0.22), 0.25 * smoothstep(-0.3, -0.85, cs));  // paler sucker side
            if (vSqPart < 1.5 && cs < -0.2 && t > 0.2 && t < 0.95) {
              // printed suckers (tiers without modelled ones)
              float fa = fract(t * 14.0) - 0.5;
              float d = length(vec2(fa * 1.0, (cs + 0.78) * 2.2));
              float size = mix(0.3, 0.2, t);
              float w = max(fwidth(d), 1e-3);
              iwSuck = 1.0 - smoothstep(size - w, size + w, d);
              diffuseColor.rgb = mix(diffuseColor.rgb, light, iwSuck * 0.75);
              iwH += 0.0006 * smoothstep(size * 0.4, size * 0.85, d) * iwSuck - 0.0004 * (1.0 - smoothstep(0.0, size * 0.5, d)) * iwSuck;
            }
          } else if (vSqPart > 1.5 && vSqPart < 2.5) {
            // modelled sucker: ring 0 = dish centre, 1 = rim top, → 1.4 = foot
            float ring = vSq.y - 1.0; iwCup = 1.0;
            vec3 rimC = mix(tc, vec3(1.0), 0.42);
            vec3 dish = mix(core * 0.38, core * 0.8, smoothstep(0.15, 0.6, ring));
            float cupLod = 1.0 - smoothstep(0.3, 0.7, fwidth(ring));
            vec3 cupC = ring < 1.0 ? mix(dish, rimC, smoothstep(0.55, 0.9, ring)) : mix(rimC, diffuseColor.rgb, smoothstep(1.02, 1.3, ring));
            diffuseColor.rgb = mix(mix(diffuseColor.rgb, rimC, 0.35), cupC, cupLod);
            iwAO *= mix(1.0, ring < 1.0 ? mix(0.6, 1.0, smoothstep(0.1, 0.8, ring)) : mix(1.0, 0.55, smoothstep(1.12, 1.4, ring)), cupLod);
            iwGumThin = ring < 1.0 ? 0.35 + 0.5 * smoothstep(0.4, 1.0, ring) : 0.6;
          }
          diffuseColor.rgb *= mix(0.7, 1.0, iwAO);
          iwGumTrans = mix(iwGumTrans, mix(iwGumTrans, vec3(1.0), 0.15), iwTipK);
          diffuseColor.a *= uOpacity;
        }
roughnessFactor = mix(roughnessFactor, 0.4, iwCup);

normal = iwBumpN(normal, iwH, -vViewPosition);
totalEmissiveRadiance += uFlash + uGlow * 0.5 * (0.7 + 0.6 * iwGumThin);
ALBEDO=max(diffuseColor.rgb,vec3(0.0)); ROUGHNESS=clamp(roughnessFactor,0.04,1.0); METALLIC=clamp(metalnessFactor,0.0,1.0); NORMAL=normal; SPECULAR=0.5;
CLEARCOAT=0.8; CLEARCOAT_ROUGHNESS=0.12;

AO=clamp(iwAO,0.0,1.0);
EMISSION=totalEmissiveRadiance+vec3(hit_flash)+ALBEDO*rim_strength*pow(1.0-clamp(dot(normal,VIEW),0.0,1.0),3.2);
vec3 source_dxy=max(abs(dFdx(vNormal)),abs(dFdy(vNormal)));float geometryRoughness=max(source_dxy.x,max(source_dxy.y,source_dxy.z));
native_specularColor=vec3(0.04);native_specularColorBlended=mix(native_specularColor,diffuseColor.rgb,metalnessFactor);native_specularF90=mix(1.0,1.0,metalnessFactor);
native_clearcoat=1.0;native_clearcoatRoughness=clamp(max(0.05,0.0525)+geometryRoughness,0.0525,1.0);
native_sheenColor=vec3(1.0,1.0,1.0);native_sheenRoughness=0.4;

          native_clearcoat = mix(0.35, 1.0, iwAO); native_clearcoatRoughness = min((iwCup > 0.5 ? 0.09 : 0.06) + geometryRoughness, 1.0);

        if (iwGumOn > 0.5) { vec3 iwST = mix(vec3(1.0), iwGumTrans / max(max(iwGumTrans.r, max(iwGumTrans.g, iwGumTrans.b)), 1e-3), 0.6); native_specularColor *= iwST; native_specularColorBlended *= iwST; }

          native_sheenColor = mix(vec3(0.08), mix(uTeam, vec3(1.0), 0.6) * 0.2, iwTipK) * iwAO;

native_clearcoat=clamp(native_clearcoat,0.0,1.0);native_clearcoatRoughness=clamp(native_clearcoatRoughness,0.0525,1.0);native_sheenRoughness=clamp(native_sheenRoughness,0.0001,1.0);
ROUGHNESS=clamp(max(roughnessFactor,0.0525)+geometryRoughness,0.0525,1.0);SPECULAR=0.5;CLEARCOAT=native_clearcoat;CLEARCOAT_ROUGHNESS=native_clearcoatRoughness;
float source_nv=clamp(dot(normalize(normal),normalize(VIEW)),0.0,1.0);vec2 source_fab=native_dfg(vec2(ROUGHNESS,source_nv));native_energy_comp=vec3(1.0)+native_specularColorBlended*(1.0/max(source_fab.x+source_fab.y,0.000001)-1.0);
native_coat_normal=normalize(vNormal);float source_cc_nv=clamp(dot(native_coat_normal,normalize(VIEW)),0.0,1.0);native_coat_attenuation=vec3(1.0)-native_clearcoat*native_schlick(vec3(0.04),1.0,source_cc_nv);
native_sss=0.0;native_thin=0.0;
native_gum_on=iwGumOn;native_gum_thin=iwGumThin;native_gum_trans=iwGumTrans;native_direct_ao=1.0;

vec3 source_world_normal=normalize((INV_VIEW_MATRIX*vec4(normal,0.0)).xyz);vec3 source_world_view=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);float hemi_mix=clamp(source_world_normal.y*0.5+0.5,0.0,1.0);vec3 source_hemi=mix(hemi_ground,hemi_sky,hemi_mix);
EMISSION*=native_coat_attenuation;
vec3 source_coat_world_normal=normalize((INV_VIEW_MATRIX*vec4(native_coat_normal,0.0)).xyz);
EMISSION+=native_source_indirect_coated(ALBEDO,METALLIC,native_specularColor,native_specularF90,ROUGHNESS,native_sheenColor,native_sheenRoughness,native_clearcoat,native_clearcoatRoughness,source_world_normal,source_world_view,source_hemi,AO,mix(0.45,1.0,AO),source_coat_world_normal);
EMISSION+=native_gum_on*native_gum_trans*(source_hemi+source_ibl_irradiance(source_world_normal)/PI)*(0.015+0.14*native_gum_thin*native_gum_thin)*AO*native_coat_attenuation;

}
