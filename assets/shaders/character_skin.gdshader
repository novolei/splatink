// Generated from source material skin; original authored color/detail equations.
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


        uniform vec4 uMouth = vec4(0.75,1.0,0.0,0.0); uniform vec4 uMouth2 = vec4(0.0,0.0,0.0,0.0); uniform vec3 uTeam = vec3(1.0,0.25415209,0.00699541); uniform float uFreckle = 0.0; uniform float uSkinLum = 0.76872708;
        uniform vec3 uSSSW = vec3(0.46,0.22,0.15); uniform vec3 uSSSTint = vec3(1.0,0.38,0.26); uniform vec3 uMouthC = vec3(0.0,1.14293646,0.16481623); uniform vec3 uMouthF = vec3(-0.02438727,-0.46543966,0.88474357);
        varying vec3 vHead; varying vec4 vFace; varying vec2 vIwUv;
         
float iwSmax(float a, float b, float k){ float h = clamp(0.5 + 0.5 * (a - b) / k, 0.0, 1.0); return mix(b, a, h) + k * h * (1.0 - h); }
float iwVisorSD(float az, float el){
  float ax = abs(az);
  float lobe = (1.0 - length(vec2((ax - 0.355) / 0.3, (el - 0.15) / 0.29))) * 0.26;
  float bridge = ax < 0.42 ? 0.1 + 0.1 * smoothstep(0.0, 0.36, ax) - abs(el - 0.17) : -1.0;
  float s = (ax - 0.42) / 0.9;
  float wc = 0.16 + 0.2 * pow(clamp(s, 0.0, 1.0), 1.35);
  float wh = 0.205 * pow(clamp(1.0 - s, 0.0, 1.0), 0.8);
  float wing = (s > -0.1 && s <= 1.0) ? wh - abs(el - wc) : -1.0;
  return iwSmax(iwSmax(lobe, bridge, 0.06), wing, 0.07);
}
float iwHairline(float az){ float a = abs(az) / 3.14159265; float h = mix(0.58, 0.3, smoothstep(0.1, 0.42, a)); return mix(h, -0.8, smoothstep(0.5, 0.96, a)); }
uniform vec2 native_eye_close=vec2(0.0); uniform vec4 uLid=vec4(0.0); uniform mat3 native_face_head=mat3(1.0);
// Explicit column arithmetic avoids legacy Adreno SPIR-V matrix-size assertions.
vec3 native_mul3(mat3 m,vec3 v){return m[0]*v.x+m[1]*v.y+m[2]*v.z;}
vec3 native_mul3t(mat3 m,vec3 v){return vec3(dot(m[0],v),dot(m[1],v),dot(m[2],v));}
mat3 native_matrix3(mat3 a,mat3 b){return mat3(native_mul3(a,b[0]),native_mul3(a,b[1]),native_mul3(a,b[2]));}
mat3 native_inverse3(mat3 m){vec3 a=cross(m[1],m[2]),b=cross(m[2],m[0]),c=cross(m[0],m[1]);float det=dot(m[0],a);return mat3(vec3(a.x,b.x,c.x),vec3(a.y,b.y,c.y),vec3(a.z,b.z,c.z))/det;}

const vec3 native_eye_c0=vec3(0.05486993,1.23827187,0.12844966); const mat3 native_eye_m0=mat3(vec3(0.05070886,0.00519134,-0.01027919),vec3(-0.00591953,0.06019775,0.00119995),vec3(0.00695343,0.0,0.03430233)); const mat3 native_eye_mi0=mat3(vec3(18.75327552,-1.6172462,5.67626659),vec3(1.9198734,16.44634984,0),vec3(-3.80147715,0.32783203,28.00190222));
const vec3 native_eye_c1=vec3(-0.05486993,1.23827187,0.12844966); const mat3 native_eye_m1=mat3(vec3(-0.05070886,0.00519134,-0.01027919),vec3(0.00591953,0.06019775,0.00119995),vec3(-0.00695343,0.0,0.03430233)); const mat3 native_eye_mi1=mat3(vec3(-18.75327552,1.6172462,-5.67626659),vec3(1.9198734,16.44634984,0),vec3(-3.80147715,0.32783203,28.00190222));
vec2 native_lid_close(int si){float close=si==0?native_eye_close.x:native_eye_close.y;return vec2(max(close,si==0?uLid.x:uLid.y),max(close,si==0?uLid.z:uLid.w));}
uniform mat3 native_face_jaw=mat3(1.0);uniform mat3 native_face_cheekL=mat3(1.0);uniform mat3 native_face_cheekR=mat3(1.0);uniform mat3 native_face_neck=mat3(1.0);uniform mat3 native_face_chest=mat3(1.0);
uniform vec3 uMouthU=vec3(-0.01282461,0.88507961,0.46526295);uniform float uMouthHW=0.01842529;

uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);
#define SOURCE_SKIN
#include "res://assets/shaders/character_lighting.gdshaderinc"
#include "res://assets/shaders/source_cube_uv.gdshaderinc"
#include "res://assets/shaders/character_indirect.gdshaderinc"

vec4 source_read(vec2 coord,float slot,vec4 lo,vec4 hi){vec4 a=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0)/24.0))*255.0+0.5);vec4 b=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0+1.0)/24.0))*255.0+0.5);return mix(lo,hi,(a*256.0+b)/65535.0);}
void vertex(){
vec4 d0=source_read(UV2,float(0),data_min_0,data_max_0);
vec4 d1=source_read(UV2,float(1),data_min_1,data_max_1);
vec4 d2=source_read(UV2,float(2),data_min_2,data_max_2);
vec4 d3=source_read(UV2,float(3),data_min_3,data_max_3);
vec4 d4=source_read(UV2,float(4),data_min_4,data_max_4);
vec4 d9=source_read(UV2,float(9),data_min_9,data_max_9);
vec4 d10=source_read(UV2,float(10),data_min_10,data_max_10);
vec4 d11=source_read(UV2,float(11),data_min_11,data_max_11);
vBindPos=d0.xyz; vEx=d0.w; vHead=d3.xyz; vFace=d4; vIwUv=d2.xy; COLOR=vec4(d1.rgb,1.0);


if(d4.x+d4.y>0.0001 || abs(d4.z)>0.0001){
  mat3 face_skin=native_face_head*d9.x+native_face_jaw*d9.y+native_face_cheekL*d9.z+native_face_cheekR*d9.w+native_face_neck*d11.x+native_face_chest*d11.y;
  vec3 iwPos=d0.xyz; vec3 iwNormal=d10.xyz;
  if(d4.x+d4.y>0.0001){
    int si=d0.x>=0.0?0:1;vec2 cl=native_lid_close(si);float angle=d4.x*cl.x-d4.y*cl.y;
    mat3 M=si==0?native_eye_m0:native_eye_m1;mat3 Mi=si==0?native_eye_mi0:native_eye_mi1;vec3 C=si==0?native_eye_c0:native_eye_c1;
    vec3 s=native_mul3(Mi,d0.xyz-C);float ca=cos(angle),sa=sin(angle);
    iwPos=C+native_mul3(M,vec3(s.x,ca*s.y-sa*s.z,sa*s.y+ca*s.z));
    vec3 nu=native_mul3t(M,iwNormal);iwNormal=normalize(native_mul3t(Mi,vec3(nu.x,ca*nu.y-sa*nu.z,sa*nu.y+ca*nu.z)));
  }
  if(abs(d4.z)>0.0001){
    float w=abs(d4.z),up=d4.z>0.0?1.0:0.0;vec3 d=iwPos-uMouthC;float mx=d.x,my=dot(d,uMouthU);
    float xn=clamp(mx/uMouthHW,-1.35,1.35),xw=min(xn*xn,1.3);float band=exp(-my*my/0.00016);
    float curve=clamp(uMouth.x,-1.3,1.3),width=clamp(uMouth.y,0.2,1.5),open=clamp(uMouth.z,0.0,1.0);
    float pucker=clamp(uMouth2.z,0.0,1.0)+clamp((0.8-width)*1.2,0.0,0.6)*step(curve,-0.6);
    vec3 dp=vec3(mx*((width-1.0)*0.75-0.3*pucker+0.2*open),0.0,0.0);
    dp+=uMouthU*(curve*0.0062*xw*mix(0.4,1.0,band)+uMouth.w*mx*0.45);
    dp-=uMouthF*max(curve,0.0)*0.0017*xw*band;
    dp+=uMouthU*up*open*0.0024*max(0.0,1.0-xw)*band;
    dp+=uMouthU*up*clamp(uMouth2.y,0.0,1.0)*0.003*smoothstep(0.1,0.8,xn)*band;
    dp+=uMouthF*pucker*0.005*max(0.0,1.0-xw)*band;iwPos+=dp*w;
  }
  // Godot executes custom vertex hooks after GPU skinning. Transform only the
  // authored rest-space deformation delta by the same six face-bone bases.
  VERTEX+=native_mul3(face_skin,iwPos-d0.xyz);NORMAL=normalize(native_mul3(face_skin,iwNormal));
}

}
void fragment(){
vec4 diffuseColor=vec4(skin_color*COLOR.rgb,1.0); vec3 normal=NORMAL; vec3 vNormal=NORMAL; vec3 vViewPosition=-VERTEX; float roughnessFactor=0.6; float metalnessFactor=0.0; vec3 totalEmissiveRadiance=vec3(0.0);
float iwSSS = 1.0;
float iwThin = 0.0;
float iwVisor = 0.0; float iwHairP = 0.0; float iwH = 0.0; float iwNail = 0.0; float iwWet = 0.0; float iwTooth = 0.0; float iwAO = vFace.w; float iwInner = 0.0;
        float iwSub = floor(vEx + 0.5);
        // subtle skin mottling (breaks the plastic look up close; invisible at range)
        {
          float mott = iwFbm(vBindPos * 60.0);
          diffuseColor.rgb *= 1.0 + (mott - 0.5) * 0.06 * iwLod(vBindPos.y * 60.0, 1.0);
        }
        if (iwSub > 0.5 && iwSub < 1.5) {                 // fingernail
          iwNail = 1.0; iwSSS = 0.3;
          diffuseColor.rgb = mix(diffuseColor.rgb, vec3(1.0, 0.86, 0.84), 0.45);
        } else if (iwSub > 1.5 && iwSub < 2.5) {          // (legacy) inner ear
          diffuseColor.rgb *= vec3(1.0, 0.8, 0.76); iwThin = 1.0;
        } else if (iwSub > 7.5 && iwSub < 8.5) {          // ear: thin → translucent against back light; the cup (uv.x) is flushed
          diffuseColor.rgb *= mix(vec3(1.0, 0.95, 0.93), vec3(1.0, 0.8, 0.76), vIwUv.x); iwThin = mix(0.75, 1.0, vIwUv.x);
        } else if (iwSub > 10.5 && iwSub < 11.5) {        // teeth: one smooth band, gaps drawn here
          float g = abs(fract(vIwUv.x * 3.3 + 0.5) - 0.5);
          float gap = (1.0 - smoothstep(0.015, 0.05, g)) * step(0.2, abs(vIwUv.x) * 3.3);
          diffuseColor.rgb = vec3(0.96, 0.95, 0.92) * (1.0 - 0.18 * gap) * mix(0.82, 1.0, smoothstep(1.0, 0.6, abs(vIwUv.x)));
          iwTooth = 1.0; iwSSS = 0.25;
        } else if (iwSub > 11.5 && iwSub < 12.5) {        // tongue
          float groove = exp(-pow(vIwUv.x / 0.12, 2.0));
          diffuseColor.rgb = vec3(0.96, 0.44, 0.42) * (1.0 - 0.2 * groove) * (0.94 + 0.12 * iwNoise(vBindPos * 900.0));
          iwWet = 0.7;
        }
        float hl = length(vHead);
        if (hl > 0.5 && iwSub < 0.5) {
          vec3 d = vHead / hl;
          float az = atan(d.x, d.z), el = asin(clamp(d.y, -1.0, 1.0));
          float fw = max(fwidth(el), 1e-4);
          // ---- painted hairline under the cap edge (hides the cap/skin seam), soft shadow just below it
          float hs = el - iwHairline(az) + 0.004;
          float hw = max(fwidth(hs), 1e-4);
          iwHairP = smoothstep(-hw, hw, hs);
          float capShadow = smoothstep(-0.09, 0.0, hs) * (1.0 - iwHairP);
          diffuseColor.rgb *= 1.0 - 0.22 * capShadow;
          diffuseColor.rgb = mix(diffuseColor.rgb, uTeam * 0.55, iwHairP);
          // ---- blush: soft warm gradient over the cheek apples (+ uMouth2.w flush), stronger on fair skin
          float bl = exp(-pow((abs(az) - 0.6) / 0.2, 2.0) - pow((el + 0.3) / 0.13, 2.0));
          float blushK = bl * mix(0.3, 0.12, smoothstep(0.35, 0.8, 1.0 - uSkinLum)) * (1.0 + 1.5 * clamp(uMouth2.w, 0.0, 1.0));
          diffuseColor.rgb *= mix(vec3(1.0), vec3(1.0, 0.72, 0.72), blushK);
          // ---- freckles across the nose bridge + cheeks
          if (uFreckle > 0.5) {
            vec2 fp = vec2(az, el + 0.12) * 42.0;
            vec2 cell = floor(fp); vec2 fr = fract(fp) - 0.5;
            float rnd = iwHash2(cell);
            vec2 off = vec2(iwHash2(cell + 3.1), iwHash2(cell + 7.7)) - 0.5;
            float region = exp(-pow((abs(az) - 0.3) / 0.28, 2.0) - pow((el + 0.14) / 0.1, 2.0));
            float fd = length(fr - off * 0.5) - 0.13 * rnd;
            float fk = iwFill(fd) * step(0.45, rnd) * region;
            diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(0.78, 0.6, 0.5), fk * 0.7);
          }
          // ---- nose tip + nostril rims: slightly warmer
          float nose = exp(-pow(az / 0.06, 2.0) - pow((el + 0.13) / 0.06, 2.0)) + 0.6 * exp(-pow((abs(az) - 0.045) / 0.03, 2.0) - pow((el + 0.165) / 0.025, 2.0));
          diffuseColor.rgb *= mix(vec3(1.0), vec3(1.0, 0.88, 0.86), nose * 0.5);
          // ---- lips: a faint rosy tint, darker at the line and in the corners
          float mEl = -0.4100, mAz = 0.1200;
          float lipX = 1.0 - smoothstep(mAz * 0.64, mAz * 1.14, abs(az));
          float lip = lipX * smoothstep(mEl - 0.06, mEl - 0.032, el) * (1.0 - smoothstep(mEl + 0.012, mEl + 0.032, el));
          diffuseColor.rgb *= mix(vec3(1.0), mix(vec3(0.95, 0.8, 0.8), vec3(0.98, 0.88, 0.85), smoothstep(0.35, 0.8, 1.0 - uSkinLum)), lip * 0.8);
          // lip line: a thin dark stroke on both lip edges (rest-space, so it rides the smile/frown and parts when open)
          float lx = abs(az) / mAz;
          float lineW = 0.0038 * mix(1.0, 0.5, smoothstep(0.6, 1.05, lx));
          float lineK = iwStroke(el - mEl + 0.002, lineW) * (1.0 - smoothstep(0.98, 1.12, lx)) * (1.0 - smoothstep(0.04, 0.2, uMouth.z)); // the opening takes over
          diffuseColor.rgb = mix(diffuseColor.rgb, diffuseColor.rgb * vec3(0.42, 0.26, 0.28), lineK * 0.85);
          // ---- mask: pigment in the skin (not a lacquered band): near-black with a faint cool tint, satin, a soft
          //      ~1.5 mm feathered edge (plus AA), a whisper of a recess in the geometry, and a little of the skin's scatter
          float sd = iwVisorSD(az, el);
          float w = max(fwidth(sd), 1e-4);
          iwVisor = smoothstep(-0.008 - w, 0.008 + w, sd);
          vec3 vc = mix(vec3(0.012, 0.0135, 0.02), vec3(0.018, 0.021, 0.032), smoothstep(-0.1, 0.5, el));
          diffuseColor.rgb = mix(diffuseColor.rgb, vc, iwVisor);
          iwSSS *= 1.0 - 0.88 * iwVisor;
          // ---- lid margin (uv.x: rolls under the eyeball): wet, a touch warmer than the lacquer
          diffuseColor.rgb = mix(diffuseColor.rgb, vec3(0.06, 0.035, 0.045), vIwUv.x);
          iwWet = max(iwWet, vIwUv.x);
          // ---- inner lip → mouth cavity (uv.y), darkening with depth behind the lips
          if (vIwUv.y > 0.001) {
            float dz = dot(uMouthC - vBindPos, uMouthF);
            vec3 c = mix(vec3(0.8, 0.36, 0.38), vec3(0.3, 0.04, 0.05), smoothstep(0.003, 0.011, dz));
            c *= mix(1.0, 0.45, smoothstep(0.011, 0.026, dz));
            diffuseColor.rgb = mix(diffuseColor.rgb, c, vIwUv.y);
            iwWet = max(iwWet, smoothstep(0.55, 1.0, vIwUv.y) * 0.7 * smoothstep(0.04, 0.25, uMouth.z)); // matte seam when closed
            iwSSS *= 1.0 - 0.4 * vIwUv.y; iwVisor *= 1.0 - vIwUv.y; iwInner = vIwUv.y;
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
roughnessFactor = mix(roughnessFactor, 0.16, iwHurtM); roughnessFactor = mix(roughnessFactor, 0.48, iwVisor); roughnessFactor = mix(roughnessFactor, 0.35, iwHairP); roughnessFactor = mix(roughnessFactor, 0.22, iwNail); roughnessFactor = mix(roughnessFactor, 0.14, iwWet); roughnessFactor = mix(roughnessFactor, 0.28, iwTooth);

normal = iwBumpN(normal, iwH, -vViewPosition);
totalEmissiveRadiance += uFlash;
ALBEDO=max(diffuseColor.rgb,vec3(0.0)); ROUGHNESS=clamp(roughnessFactor,0.04,1.0); METALLIC=clamp(metalnessFactor,0.0,1.0); NORMAL=normal; SPECULAR=0.32;


AO=clamp(iwAO,0.0,1.0);
EMISSION=totalEmissiveRadiance+vec3(hit_flash)+ALBEDO*rim_strength*pow(1.0-clamp(dot(normal,VIEW),0.0,1.0),3.2);
vec3 source_dxy=max(abs(dFdx(vNormal)),abs(dFdy(vNormal)));float geometryRoughness=max(source_dxy.x,max(source_dxy.y,source_dxy.z));
native_specularColor=vec3(0.0128);native_specularColorBlended=mix(native_specularColor,diffuseColor.rgb,metalnessFactor);native_specularF90=mix(0.32,1.0,metalnessFactor);
native_clearcoat=0.01;native_clearcoatRoughness=clamp(max(0.5,0.0525)+geometryRoughness,0.0525,1.0);
native_sheenColor=vec3(1.0,0.64447968,0.52711513);native_sheenRoughness=0.85;

          native_clearcoat = max(iwNail * 0.6, max(iwWet * 0.8, iwTooth * 0.5));  // wet line, nails, teeth only (mask is satin)
          native_clearcoat *= mix(1.0, iwAO * iwAO, max(iwInner, iwTooth));   // no sky mirrored inside the mouth
          native_clearcoatRoughness = mix(0.45, 0.06, iwWet);


          native_sheenColor *= (1.0 - 0.85 * iwVisor) * (1.0 - iwHairP) * (1.0 - iwWet) * (1.0 - iwTooth) * mix(0.4, 0.22, uSkinLum);

native_clearcoat=clamp(native_clearcoat,0.0,1.0);native_clearcoatRoughness=clamp(native_clearcoatRoughness,0.0525,1.0);native_sheenRoughness=clamp(native_sheenRoughness,0.0001,1.0);
ROUGHNESS=clamp(max(roughnessFactor,0.0525)+geometryRoughness,0.0525,1.0);SPECULAR=0.28284271;CLEARCOAT=native_clearcoat;CLEARCOAT_ROUGHNESS=native_clearcoatRoughness;
float source_nv=clamp(dot(normalize(normal),normalize(VIEW)),0.0,1.0);vec2 source_fab=native_dfg(vec2(ROUGHNESS,source_nv));native_energy_comp=vec3(1.0)+native_specularColorBlended*(1.0/max(source_fab.x+source_fab.y,0.000001)-1.0);
native_coat_normal=normalize(vNormal);float source_cc_nv=clamp(dot(native_coat_normal,normalize(VIEW)),0.0,1.0);native_coat_attenuation=vec3(1.0)-native_clearcoat*native_schlick(vec3(0.04),1.0,source_cc_nv);
native_sss=iwSSS;native_thin=iwThin;
native_gum_on=0.0;native_gum_thin=0.0;native_gum_trans=vec3(0.0);native_direct_ao=1.0;

vec3 source_world_normal=normalize((INV_VIEW_MATRIX*vec4(normal,0.0)).xyz);vec3 source_world_view=normalize((INV_VIEW_MATRIX*vec4(VIEW,0.0)).xyz);float hemi_mix=clamp(source_world_normal.y*0.5+0.5,0.0,1.0);vec3 source_hemi=mix(hemi_ground,hemi_sky,hemi_mix);
EMISSION*=native_coat_attenuation;
vec3 source_coat_world_normal=normalize((INV_VIEW_MATRIX*vec4(native_coat_normal,0.0)).xyz);
EMISSION+=native_source_indirect_coated(ALBEDO,METALLIC,native_specularColor,native_specularF90,ROUGHNESS,native_sheenColor,native_sheenRoughness,native_clearcoat,native_clearcoatRoughness,source_world_normal,source_world_view,source_hemi,AO,mix(1.0,AO,0.8),source_coat_world_normal);


vec3 rim_view=normalize(VIEW);
vec3 rim_direction=native_rim_world?normalize((VIEW_MATRIX*vec4(uIwRimL,0.0)).xyz):uIwRimL;
float rim_fresnel=pow(1.0-clamp(dot(normal,rim_view),0.0,1.0),uIwRim.w);
float rim_side=clamp(dot(normal,rim_direction)*0.5+0.5,0.0,1.0);
EMISSION+=uIwRim.rgb*(1.0*rim_fresnel*(0.3+0.7*rim_side*rim_side));
float rim_fill=clamp(dot(normal,normalize(vec3(0.25,0.45,1.0)))*0.6+0.4,0.0,1.0);
EMISSION+=uIwFill*diffuseColor.rgb*rim_fill*rim_fill;
}
