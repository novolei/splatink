// Generated from source material coil; original authored color/detail equations.
shader_type spatial;
render_mode diffuse_lambert,cull_back;
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
uniform float uCharge = 0.0;
uniform float uFull = 0.0;
uniform float uFlash = 0.0;
uniform float uTime = 0.0;
varying float vSeg;

uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);
uniform vec3 uTeam=vec3(1.0);


vec4 source_read(vec2 coord,float slot,vec4 lo,vec4 hi){vec4 a=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0)/24.0))*255.0+0.5);vec4 b=floor(texture(source_data,vec2(coord.x,(coord.y+slot*2.0+1.0)/24.0))*255.0+0.5);return mix(lo,hi,(a*256.0+b)/65535.0);}
void vertex(){
vec4 d3=source_read(UV2,float(3),data_min_3,data_max_3);
vSeg=d3.w;


}
void fragment(){
vec4 diffuseColor=vec4(vec3(0.01096009,0.01161225,0.01599629),1.0); vec3 normal=NORMAL; vec3 vNormal=NORMAL; vec3 vViewPosition=-VERTEX; float roughnessFactor=0.3; float metalnessFactor=0.25; vec3 totalEmissiveRadiance=vec3(0.0);





{
          float lit = smoothstep(vSeg - 0.1, vSeg + 0.01, uCharge);
          float edge = exp(-pow((uCharge - vSeg + 0.05) * 11.0, 2.0)) * (1.0 - uFull);
          float I = 0.05 + lit * (0.9 + 1.7 * uCharge) + edge * (1.3 + 0.9 * sin(uTime * 57.0))
                  + uFull * (1.1 + 1.0 * (0.5 + 0.5 * sin(uTime * 34.0 - vSeg * 14.0))) + uFlash * 6.0;
          totalEmissiveRadiance = uTeam * I + vec3(uFlash * 2.0);
        }
ALBEDO=max(diffuseColor.rgb,vec3(0.0)); ROUGHNESS=clamp(roughnessFactor,0.04,1.0); METALLIC=clamp(metalnessFactor,0.0,1.0); NORMAL=normal; SPECULAR=0.5;



EMISSION=totalEmissiveRadiance+vec3(hit_flash)+ALBEDO*rim_strength*pow(1.0-clamp(dot(normal,VIEW),0.0,1.0),3.2);

float hemi_mix=clamp((INV_VIEW_MATRIX[0].y*normal.x+INV_VIEW_MATRIX[1].y*normal.y+INV_VIEW_MATRIX[2].y*normal.z)*0.5+0.5,0.0,1.0);EMISSION+=ALBEDO*(1.0-METALLIC)*mix(hemi_ground,hemi_sky,hemi_mix)*AO;
}
