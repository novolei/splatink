// Generated from source material eye; original authored color/detail equations.
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

        uniform vec2 uLook = vec2(0.0,0.0); uniform vec3 uIris = vec3(1.0,0.44520119,0.01161225); uniform vec3 uIris2 = vec3(1.0,0.14412847,0.0); uniform vec3 uFlash = vec3(0.0,0.0,0.0); uniform float uPupil = 0.5; uniform float uIrisR = 0.37;
        uniform vec4 uEyeAp = vec4(0.5,0.6,0.57,0.0); uniform vec4 uEyeLid = vec4(0.22,0.035,1.075,1.05);
        varying vec2 vEyeUv; varying float vSide;
        varying vec3 vEyeS; varying vec3 vEyeSock; varying vec3 vAi0; varying vec3 vAi1; varying vec3 vAi2; varying vec2 vLidC;
        float iwCircle(vec2 p, vec2 c, float r){ float d = length(p - c) - r; float w = max(fwidth(d), 1e-4); return 1.0 - smoothstep(-w, w, d); }
uniform vec2 native_eye_close=vec2(0.0); uniform vec4 uLid=vec4(0.0); uniform mat3 native_face_head=mat3(1.0);
// Explicit column arithmetic avoids legacy Adreno SPIR-V matrix-size assertions.
vec3 native_mul3(mat3 m,vec3 v){return m[0]*v.x+m[1]*v.y+m[2]*v.z;}
vec3 native_mul3t(mat3 m,vec3 v){return vec3(dot(m[0],v),dot(m[1],v),dot(m[2],v));}
mat3 native_matrix3(mat3 a,mat3 b){return mat3(native_mul3(a,b[0]),native_mul3(a,b[1]),native_mul3(a,b[2]));}
mat3 native_inverse3(mat3 m){vec3 a=cross(m[1],m[2]),b=cross(m[2],m[0]),c=cross(m[0],m[1]);float det=dot(m[0],a);return mat3(vec3(a.x,b.x,c.x),vec3(a.y,b.y,c.y),vec3(a.z,b.z,c.z))/det;}

const vec3 native_eye_c0=vec3(0.05486993,1.23827187,0.12844966); const mat3 native_eye_m0=mat3(vec3(0.05070886,0.00519134,-0.01027919),vec3(-0.00591953,0.06019775,0.00119995),vec3(0.00695343,0.0,0.03430233)); const mat3 native_eye_mi0=mat3(vec3(18.75327552,-1.6172462,5.67626659),vec3(1.9198734,16.44634984,0),vec3(-3.80147715,0.32783203,28.00190222));
const vec3 native_eye_c1=vec3(-0.05486993,1.23827187,0.12844966); const mat3 native_eye_m1=mat3(vec3(-0.05070886,0.00519134,-0.01027919),vec3(0.00591953,0.06019775,0.00119995),vec3(-0.00695343,0.0,0.03430233)); const mat3 native_eye_mi1=mat3(vec3(-18.75327552,1.6172462,-5.67626659),vec3(1.9198734,16.44634984,0),vec3(-3.80147715,0.32783203,28.00190222));
vec2 native_lid_close(int si){float close=si==0?native_eye_close.x:native_eye_close.y;return vec2(max(close,si==0?uLid.x:uLid.y),max(close,si==0?uLid.z:uLid.w));}
uniform vec4 uGaze=vec4(0.0);uniform float uEyeRest=-0.06;

uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);
#include "res://assets/shaders/character_lighting.gdshaderinc"
#include "res://assets/shaders/source_cube_uv.gdshaderinc"
#include "res://assets/shaders/character_indirect.gdshaderinc"

vec4 source_read(vec2 coord,float slot,vec4 lo,vec4 hi){vec4 a=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0)/24.0))*255.0+0.5);vec4 b=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0+1.0)/24.0))*255.0+0.5);return mix(lo,hi,(a*256.0+b)/65535.0);}
void vertex(){
vec4 d0=source_read(UV2,float(0),data_min_0,data_max_0);
vec4 d2=source_read(UV2,float(2),data_min_2,data_max_2);
vec4 d7=source_read(UV2,float(7),data_min_7,data_max_7);
vec4 d10=source_read(UV2,float(10),data_min_10,data_max_10);
vEyeUv=d2.xy; vSide=d0.w; vEyeS=d7.xyz; vEyeSock=d7.xyz; vLidC=vec2(0.0);


if(abs(d0.w)>1.5){
  int si=d0.w>0.0?0:1;float sd=d0.w>0.0?1.0:-1.0;
  mat3 M=si==0?native_eye_m0:native_eye_m1;mat3 Mi=si==0?native_eye_mi0:native_eye_mi1;vec3 C=si==0?native_eye_c0:native_eye_c1;
  float yaw=uEyeRest+sd*clamp(0.6*(uLook.x*1.25+(si==0?uGaze.x:uGaze.z)),-0.36,0.36);
  float pitch=clamp(0.6*(uLook.y*1.25+(si==0?uGaze.y:uGaze.w)),-0.3,0.3);
  float cy=cos(yaw),sy=sin(yaw),cp=cos(-pitch),sp=sin(-pitch);
  mat3 Ry=mat3(vec3(cy,0.0,-sy),vec3(0.0,1.0,0.0),vec3(sy,0.0,cy));
  mat3 Rx=mat3(vec3(1.0,0.0,0.0),vec3(0.0,cp,sp),vec3(0.0,-sp,cp));mat3 R=native_matrix3(Ry,Rx);
  vec3 s=native_mul3(R,d7.xyz);vec3 iwEP=C+native_mul3(M,s);VERTEX+=native_mul3(native_face_head,iwEP-d0.xyz);
  NORMAL=normalize(native_mul3(native_face_head,native_mul3t(Mi,native_mul3(R,native_mul3t(M,d10.xyz)))));
  vEyeS=d7.xyz;vEyeSock=s;vLidC=native_lid_close(si);
  mat3 view_basis=mat3(MODELVIEW_MATRIX[0].xyz,MODELVIEW_MATRIX[1].xyz,MODELVIEW_MATRIX[2].xyz);
  mat3 Ai=native_inverse3(native_matrix3(native_matrix3(native_matrix3(view_basis,native_face_head),M),R));vAi0=Ai[0];vAi1=Ai[1];vAi2=Ai[2];
}else{mat3 Ai=native_inverse3(mat3(MODELVIEW_MATRIX[0].xyz,MODELVIEW_MATRIX[1].xyz,MODELVIEW_MATRIX[2].xyz));vAi0=Ai[0];vAi1=Ai[1];vAi2=Ai[2];}

}
void fragment(){
vec4 diffuseColor=vec4(vec3(1.0),1.0); vec3 normal=NORMAL; vec3 vNormal=NORMAL; vec3 vViewPosition=-VERTEX; float roughnessFactor=0.14; float metalnessFactor=0.0; vec3 totalEmissiveRadiance=vec3(0.0);

vec3 iwEyeEmit = vec3(0.0); float iwEyeRim = 0.0; float iwCat = 0.0;
        if (abs(vSide) > 1.5) {
          // ---------------- socketed eyeball ----------------
          vec3 dS = normalize(vEyeS);
          vec3 V = normalize(native_mul3(mat3(vAi0, vAi1, vAi2),normalize(vViewPosition)));   // view dir in eye space
          // lid positions in the socket frame (same curves as the skin's lids) → contact shadow + corner shade
          vec3 sk = normalize(vEyeSock);
          float lam = atan(sk.y, sk.z), xu = sk.x / uEyeAp.x, q = sqrt(max(1.0 - xu * xu, 0.0));
          float lU0 = uEyeAp.w + uEyeAp.y * q, lL0 = uEyeAp.w - uEyeAp.z * q, lC = lL0 + uEyeLid.x * (lU0 - lL0);
          float lU = lU0 - vLidC.x * (lU0 - lC + uEyeLid.y), lL = lL0 + vLidC.y * (lC - lL0);
          float dU = lU - lam, dL = lam - lL;
          float shade = mix(0.3, 1.0, smoothstep(0.0, 0.2, dU)) * mix(0.55, 1.0, smoothstep(0.0, 0.12, dL));
          shade *= mix(0.7, 1.0, smoothstep(1.0, 0.72, abs(xu)));
          // soft contact shadow under the two lash tabs (they ride the upper lid)
          {
            float lnS = (lam - uEyeAp.w) / (lam >= uEyeAp.w ? uEyeAp.y : uEyeAp.z);
            for (int k = 0; k < 2; k++) {
              vec3 L = k == 0 ? vec3(0.7612, 0.4987, 0.155) : vec3(0.9033, 0.2211, 0.115);
              float tipA = k == 0 ? -1.2 : -0.7;
              float xl = L.x * uEyeAp.x, ql = sqrt(max(1.0 - L.x * L.x, 0.0));
              float lU0l = uEyeAp.w + uEyeAp.y * ql, lCl = uEyeAp.w - uEyeAp.z * ql + uEyeLid.x * (uEyeAp.y + uEyeAp.z) * ql;
              float yl = L.y - vLidC.x * (lU0l - lCl + uEyeLid.y) / uEyeAp.y;
              vec2 dv = vec2(xu - L.x, lnS - yl);
              float dl = length(dv) - L.z * (1.0 + 0.9 * pow(max(0.0, cos(atan(dv.y, dv.x) - tipA)), 5.0));
              shade *= mix(0.45, 1.0, smoothstep(-0.02, 0.07, dl));
            }
          }
          // sclera: warm white, cooler toward the rim, a hint of pink in the corners
          vec3 sclera = mix(vec3(0.95, 0.94, 0.92), vec3(0.8, 0.82, 0.88), smoothstep(0.35, 1.1, acos(clamp(dS.z, -1.0, 1.0))));
          sclera = mix(sclera, vec3(0.95, 0.8, 0.8), smoothstep(0.75, 1.05, abs(xu)) * 0.45);
          // iris seen through the cornea: refract the view ray onto a plane just under the limbus
          float zI = cos(uIrisR) - 0.03;
          vec3 rd = refract(-V, dS, 0.75);
          float tI = (vEyeS.z - zI) / max(-rd.z, 0.12);
          vec3 ip = vEyeS + rd * max(tI, 0.0);
          vec2 iq = ip.xy / sin(uIrisR);
          float r = length(iq), ang = atan(iq.y, iq.x);
          float iw = max(fwidth(r), 1e-3);
          float irisM = 1.0 - smoothstep(1.0 - iw, 1.0 + iw, r);
          vec3 ic = mix(uIris2, uIris, smoothstep(0.55, -0.8, iq.y));
          float fl = iwLod(r * 24.0, 1.0);
          vec2 idr = iq / max(r, 1e-4);                                   // seam-free angular coordinate
          float fib = iwNoise(vec3(idr * 11.0, r * 4.0 + vSide * 7.0)) * 0.6 + iwNoise(vec3(idr * 27.0, r * 1.5 + vSide)) * 0.4;
          ic *= mix(1.0, mix(0.76, 1.2, fib), smoothstep(0.3, 0.7, r) * fl);
          float coll = 1.0 - smoothstep(0.0, 0.07, abs(r - 0.47 - 0.035 * sin(ang * 9.0 + vSide)));
          ic = mix(ic, ic * 1.3 + 0.04, coll * 0.55 * fl);
          ic = mix(ic, ic * 1.45 + 0.07, smoothstep(0.3, 0.95, r) * smoothstep(0.15, -0.7, iq.y) * 0.85);  // lower glow
          ic *= mix(1.0, 0.22, smoothstep(0.78, 0.99, r));                                                  // limbal ring
          float pr = 0.34 * (0.8 + 0.45 * clamp(uPupil, 0.0, 1.0));
          float pd = length(iq * vec2(1.0, 0.86) - vec2(0.0, 0.03)) - pr;
          float pw = max(fwidth(pd), 1e-4);
          float pupil = (1.0 - smoothstep(-pw, pw, pd)) * irisM;
          ic = mix(ic, ic * 0.55, (1.0 - smoothstep(0.0, 0.08, pd)) * (1.0 - pupil));                        // pupil rim
          vec3 col = mix(sclera, ic, irisM);
          col = mix(col, vec3(0.01, 0.009, 0.022), pupil);
          col *= shade;
          iwEyeRim = 1.0 - shade;
          diffuseColor.rgb = col;
          iwEyeEmit = ic * irisM * (1.0 - pupil) * 0.07 * shade;
          // catch-light: a virtual key from the camera's upper left, on the cornea's true (bulged) normal
          vec3 nV = normalize(vNormal);
          float spread = clamp(length(fwidth(nV)) * 6.0, 0.0, 1.0);
          vec3 Vv = normalize(vViewPosition);
          float e1 = mix(1100.0, 90.0, spread), e2 = mix(1800.0, 160.0, spread);
          float c1 = pow(max(dot(nV, normalize(normalize(vec3(-0.42, 0.55, 0.72)) + Vv)), 0.0), e1);
          float c2 = pow(max(dot(nV, normalize(normalize(vec3(0.5, -0.35, 0.8)) + Vv)), 0.0), e2);
          iwCat = (c1 * 1.6 + c2 * 0.7) * mix(1.0, 0.35, spread) * smoothstep(0.02, 0.12, dU);
          iwEyeEmit += vec3(iwCat);
        } else {
          // ---------------- legacy painted eye patch (squid form) ----------------
          vec2 p = vEyeUv;
          float r = length(p);
          float outer = p.x * sign(vSide + 1e-3);
          vec2 q = p - uLook;
          vec3 sclera = mix(vec3(0.93, 0.94, 0.97), vec3(0.78, 0.8, 0.88), smoothstep(0.35, 1.0, r));
          sclera *= mix(0.72, 1.0, smoothstep(0.98, 0.3, p.y));
          vec2 iq = q * vec2(1.0, 0.94);
          float ir = length(iq) / 0.66;
          float iris = iwCircle(iq, vec2(0.0), 0.66);
          float ang = atan(iq.y, iq.x);
          vec3 ic = mix(uIris2, uIris, smoothstep(0.55, -0.75, q.y));
          float stri = 0.5 + 0.5 * sin(ang * 23.0 + 3.0 * sin(ang * 5.0));
          ic *= mix(0.86, 1.08, stri * smoothstep(0.25, 0.8, ir));
          ic = mix(ic, ic * 1.45 + 0.06, smoothstep(0.3, 0.95, ir) * smoothstep(0.15, -0.65, q.y));
          ic = mix(ic, ic * 1.25 + 0.04, (1.0 - smoothstep(0.34, 0.5, ir)) * 0.6);
          ic *= mix(1.0, 0.42, smoothstep(0.78, 1.0, ir));
          ic *= mix(0.7, 1.0, smoothstep(0.75, 0.1, q.y));
          vec2 pq = (q - vec2(0.0, 0.03)) * vec2(1.0, 0.8);
          float pd = length(vec2(pq.x, max(abs(pq.y) - 0.07, 0.0))) - 0.24;
          float pw = max(fwidth(pd), 1e-4);
          float pupil = 1.0 - smoothstep(-pw, pw, pd);
          vec3 col = mix(sclera, ic, iris);
          col = mix(col, vec3(0.012, 0.01, 0.028), pupil);
          float h1 = iwCircle(p * vec2(1.0, 0.9), uLook * 0.5 + vec2(-0.25, 0.3), 0.19);
          float h2 = iwCircle(p, uLook * 0.5 + vec2(0.24, -0.3), 0.075);
          float h3 = iwCircle(p * vec2(1.0, 1.6), uLook * 0.5 + vec2(0.08, 0.62), 0.07) * 0.6;
          col = mix(col, vec3(1.0), max(max(h1, h2 * 0.9), h3));
          float lidTop = smoothstep(0.7, 0.82, p.y + 0.12 * outer * outer) * smoothstep(0.35, 0.6, r);
          float lash1 = iwCircle(vec2(outer, p.y), vec2(0.86, 0.46), 0.1);
          float lash2 = iwCircle(vec2(outer, p.y), vec2(0.95, 0.24), 0.07);
          float rim = smoothstep(0.84, 0.97, r);
          float lids = max(max(lidTop, rim), max(lash1, lash2) * smoothstep(0.7, 0.9, r));
          col = mix(col, vec3(0.018, 0.018, 0.03), lids);
          iwEyeRim = lids;
          diffuseColor.rgb = col;
          iwEyeEmit = col * (0.07 * (1.0 - lids)) + vec3(1.0) * max(h1, h2) * 0.2 + ic * iris * (1.0 - pupil) * 0.06;
        }
roughnessFactor = mix(roughnessFactor, 0.35, iwEyeRim);


totalEmissiveRadiance += iwEyeEmit + uFlash * 0.5;
ALBEDO=max(diffuseColor.rgb,vec3(0.0)); ROUGHNESS=clamp(roughnessFactor,0.04,1.0); METALLIC=clamp(metalnessFactor,0.0,1.0); NORMAL=normal; SPECULAR=0.5;
CLEARCOAT=0.8; CLEARCOAT_ROUGHNESS=0.12;


EMISSION=totalEmissiveRadiance+vec3(hit_flash)+ALBEDO*rim_strength*pow(1.0-clamp(dot(normal,VIEW),0.0,1.0),3.2);
vec3 source_dxy=max(abs(dFdx(vNormal)),abs(dFdy(vNormal)));float geometryRoughness=max(source_dxy.x,max(source_dxy.y,source_dxy.z));
native_specularColor=vec3(0.02);native_specularColorBlended=mix(native_specularColor,diffuseColor.rgb,metalnessFactor);native_specularF90=mix(0.5,1.0,metalnessFactor);
native_clearcoat=1.0;native_clearcoatRoughness=clamp(max(0.03,0.0525)+geometryRoughness,0.0525,1.0);
native_sheenColor=vec3(0.0,0.0,0.0);native_sheenRoughness=1.0;

          native_clearcoat *= mix(1.0, 0.35, iwEyeRim);

native_clearcoat=clamp(native_clearcoat,0.0,1.0);native_clearcoatRoughness=clamp(native_clearcoatRoughness,0.0525,1.0);native_sheenRoughness=clamp(native_sheenRoughness,0.0001,1.0);
ROUGHNESS=clamp(max(roughnessFactor,0.0525)+geometryRoughness,0.0525,1.0);SPECULAR=0.35355339;CLEARCOAT=native_clearcoat;CLEARCOAT_ROUGHNESS=native_clearcoatRoughness;
float source_nv=clamp(dot(normalize(normal),normalize(VIEW)),0.0,1.0);vec2 source_fab=native_dfg(vec2(ROUGHNESS,source_nv));native_energy_comp=vec3(1.0)+native_specularColorBlended*(1.0/max(source_fab.x+source_fab.y,0.000001)-1.0);
native_coat_normal=normalize(vNormal);float source_cc_nv=clamp(dot(native_coat_normal,normalize(VIEW)),0.0,1.0);native_coat_attenuation=vec3(1.0)-native_clearcoat*native_schlick(vec3(0.04),1.0,source_cc_nv);
native_sss=0.0;native_thin=0.0;
native_gum_on=0.0;native_gum_thin=0.0;native_gum_trans=vec3(0.0);native_direct_ao=1.0;

vec3 source_world_normal=normalize((INV_VIEW_MATRIX*vec4(normal,0.0)).xyz);vec3 source_world_view=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);float hemi_mix=clamp(source_world_normal.y*0.5+0.5,0.0,1.0);vec3 source_hemi=mix(hemi_ground,hemi_sky,hemi_mix);
EMISSION*=native_coat_attenuation;
vec3 source_coat_world_normal=normalize((INV_VIEW_MATRIX*vec4(native_coat_normal,0.0)).xyz);
EMISSION+=native_source_indirect_coated(ALBEDO,METALLIC,native_specularColor,native_specularF90,ROUGHNESS,native_sheenColor,native_sheenRoughness,native_clearcoat,native_clearcoatRoughness,source_world_normal,source_world_view,source_hemi,AO,1.0,source_coat_world_normal);


}
