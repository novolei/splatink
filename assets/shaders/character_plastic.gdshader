// Generated from source material plastic; original authored color/detail equations.
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
varying float vMat; varying vec3 vWPos;
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

uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);
#include "res://assets/shaders/character_lighting.gdshaderinc"
#include "res://assets/shaders/source_cube_uv.gdshaderinc"
#include "res://assets/shaders/character_indirect.gdshaderinc"

vec4 source_read(vec2 coord,float slot,vec4 lo,vec4 hi){vec4 a=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0)/24.0))*255.0+0.5);vec4 b=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0+1.0)/24.0))*255.0+0.5);return mix(lo,hi,(a*256.0+b)/65535.0);}
void vertex(){
vec4 d0=source_read(UV2,float(0),data_min_0,data_max_0);
vec4 d1=source_read(UV2,float(1),data_min_1,data_max_1);
vec4 d2=source_read(UV2,float(2),data_min_2,data_max_2);
vMat=d2.w; vWPos=d0.xyz;
COLOR=vec4(d1.rgb,1.0);

}
void fragment(){
vec4 diffuseColor=vec4(COLOR.rgb,1.0); vec3 normal=NORMAL; vec3 vNormal=NORMAL; vec3 vViewPosition=-VERTEX; float roughnessFactor=0.4; float metalnessFactor=0.0; vec3 totalEmissiveRadiance=vec3(0.0);

float iwM = floor(vMat + 0.5); float iwH = 0.0; vec3 iwLed = vec3(0.0);
          if (iwM == 2.0) {                   // rubber: diamond knurl
            vec3 q = vWPos * 520.0;
            float k = abs(fract((q.x + q.y + q.z) * 0.5) - 0.5) + abs(fract((q.y - q.z + q.x * 0.3) * 0.5) - 0.5);
            iwH += 0.0003 * smoothstep(0.25, 0.6, k) * iwLod(vWPos.y * 520.0, 2.0);
          } else if (iwM == 3.0) {            // brushed metal streaks along the weapon axis
            float br = iwNoise(vec3(vWPos.x * 1800.0, vWPos.y * 1800.0, vWPos.z * 40.0));
            diffuseColor.rgb *= 0.9 + 0.2 * br;
          } else if (iwM == 5.0) {
            iwLed = diffuseColor.rgb * 2.2;
          } else if (iwM == 0.0) {            // satin: faint moulding texture
            iwH += 0.00004 * (iwNoise(vWPos * 1400.0) - 0.5) * iwLod(vWPos.y * 1400.0, 1.0);
          }
roughnessFactor = iwM == 1.0 ? 0.2 : iwM == 2.0 ? 0.82 : iwM == 3.0 ? 0.3 : iwM == 4.0 ? 0.04 : iwM == 5.0 ? 0.25 : iwM == 6.0 ? 0.62 : 0.42;
metalnessFactor = iwM == 3.0 ? 1.0 : 0.0;
normal = iwBumpN(normal, iwH, -vViewPosition);
totalEmissiveRadiance += iwLed;
ALBEDO=max(diffuseColor.rgb,vec3(0.0)); ROUGHNESS=clamp(roughnessFactor,0.04,1.0); METALLIC=clamp(metalnessFactor,0.0,1.0); NORMAL=normal; SPECULAR=0.5;



EMISSION=totalEmissiveRadiance+vec3(hit_flash)+ALBEDO*rim_strength*pow(1.0-clamp(dot(normal,VIEW),0.0,1.0),3.2);
vec3 source_dxy=max(abs(dFdx(vNormal)),abs(dFdy(vNormal)));float geometryRoughness=max(source_dxy.x,max(source_dxy.y,source_dxy.z));
native_specularColor=vec3(0.04);native_specularColorBlended=mix(native_specularColor,diffuseColor.rgb,metalnessFactor);native_specularF90=mix(1.0,1.0,metalnessFactor);
native_clearcoat=1.0;native_clearcoatRoughness=clamp(max(0.1,0.0525)+geometryRoughness,0.0525,1.0);
native_sheenColor=vec3(0.0,0.0,0.0);native_sheenRoughness=1.0;

            native_clearcoat = iwM == 1.0 ? 1.0 : iwM == 4.0 ? 1.0 : iwM == 0.0 ? 0.25 : iwM == 3.0 ? 0.2 : 0.0;
            native_clearcoatRoughness = iwM == 4.0 ? 0.02 : 0.1;

native_clearcoat=clamp(native_clearcoat,0.0,1.0);native_clearcoatRoughness=clamp(native_clearcoatRoughness,0.0525,1.0);native_sheenRoughness=clamp(native_sheenRoughness,0.0001,1.0);
ROUGHNESS=clamp(max(roughnessFactor,0.0525)+geometryRoughness,0.0525,1.0);SPECULAR=0.5;CLEARCOAT=native_clearcoat;CLEARCOAT_ROUGHNESS=native_clearcoatRoughness;
float source_nv=clamp(dot(normalize(normal),normalize(VIEW)),0.0,1.0);vec2 source_fab=native_dfg(vec2(ROUGHNESS,source_nv));native_energy_comp=vec3(1.0)+native_specularColorBlended*(1.0/max(source_fab.x+source_fab.y,0.000001)-1.0);
native_coat_normal=normalize(vNormal);float source_cc_nv=clamp(dot(native_coat_normal,normalize(VIEW)),0.0,1.0);native_coat_attenuation=vec3(1.0)-native_clearcoat*native_schlick(vec3(0.04),1.0,source_cc_nv);
native_sss=0.0;native_thin=0.0;
native_gum_on=0.0;native_gum_thin=0.0;native_gum_trans=vec3(0.0);native_direct_ao=1.0;

vec3 source_world_normal=normalize((INV_VIEW_MATRIX*vec4(normal,0.0)).xyz);vec3 source_world_view=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);float hemi_mix=clamp(source_world_normal.y*0.5+0.5,0.0,1.0);vec3 source_hemi=mix(hemi_ground,hemi_sky,hemi_mix);
EMISSION*=native_coat_attenuation;
vec3 source_coat_world_normal=normalize((INV_VIEW_MATRIX*vec4(native_coat_normal,0.0)).xyz);
EMISSION+=native_source_indirect_coated(ALBEDO,METALLIC,native_specularColor,native_specularF90,ROUGHNESS,native_sheenColor,native_sheenRoughness,native_clearcoat,native_clearcoatRoughness,source_world_normal,source_world_view,source_hemi,AO,1.0,source_coat_world_normal);


}
