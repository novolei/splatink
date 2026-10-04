shader_type spatial;
render_mode cull_disabled, diffuse_lambert, specular_schlick_ggx, ambient_light_disabled;
uniform sampler2DArray t_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray t_normal : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2DArray t_orm : filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D paint_atlas : filter_linear_mipmap_anisotropic, repeat_disable;
uniform sampler2D ao_atlas : filter_linear_mipmap, repeat_disable;
uniform sampler2D mural_atlas : source_color, filter_linear_mipmap, repeat_enable;
uniform vec4 slots[64];
uniform vec4 tints[64];
uniform vec4 stairs[64];
uniform vec4 mural_rect[12];
uniform vec4 mural_place[12];
uniform vec2 mural_fx[12];
uniform vec3 team_a : source_color = vec3(1.0,0.247,0.62);
uniform vec3 team_b : source_color = vec3(0.094,0.83,0.549);
uniform bool has_ao = true;
uniform bool grate = false;
uniform float clock = 0.0;
uniform float atlas_size=2048.0;
uniform float paint_ppm=18.0;
uniform float gel_layer=13.0;
uniform vec3 sun_direction=vec3(-.57,.63,-.52);
uniform vec3 hemi_sky=vec3(0.0);
uniform vec3 hemi_ground=vec3(0.0);
uniform vec4 ripple_params[24];
uniform vec4 wake_points[48];
uniform vec4 wake_bounds[4];
uniform float texel = 0.00048828125;
uniform vec4 ripples[24];
uniform vec4 swimmers[4];
uniform vec4 swimmer_dirs[4];
varying vec3 world_pos;
varying vec3 world_normal;
varying vec4 face_data;
varying vec4 aux;
varying vec3 face_tangent;
varying vec3 face_flags;
#define USE_TEXLIB
float h21(vec2 p){p=fract(p*vec2(123.34,456.21));p+=dot(p,p+45.32);return fract(p.x*p.y);}
float vnoise(vec2 p){vec2 i=floor(p),f=fract(p),u=f*f*(3.0-2.0*f);return mix(mix(h21(i),h21(i+vec2(1.0,0.0)),u.x),mix(h21(i+vec2(0.0,1.0)),h21(i+vec2(1.0,1.0)),u.x),u.y);}
float fbm(vec2 p){float a=.5,s=0.0;for(int i=0;i<4;i++){s+=a*vnoise(p);p=p*2.03+17.1;a*=.5;}return s;}
float gridLine(float x,float period,float width){float fx=abs(fract(x/period+.5)-.5)*period;float w=fwidth(x)*.75;return 1.0-smoothstep(width-w,width+w,fx);}
vec2 fsz0(vec4 fd){return fd.zw;}
#include "res://assets/shaders/source_texlib.gdshaderinc"
void vertex(){
 world_pos=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
 world_normal=normalize(mat3(MODEL_MATRIX)*NORMAL);
 face_data=CUSTOM0;aux=CUSTOM1;face_tangent=CUSTOM2.xyz;face_flags=CUSTOM3.xyz;
}
#include "res://assets/shaders/source_ink_pars.gdshaderinc"
#include "res://assets/shaders/source_surface_lighting.gdshaderinc"
void fragment(){
 #include "res://assets/shaders/source_surface_fragment.gdshaderinc"
 #include "res://assets/shaders/source_ink_color.gdshaderinc"
 #include "res://assets/shaders/source_ink_normal.gdshaderinc"
 float ao=has_ao&&aux.x>=0.0?texture(ao_atlas,vec2(aux.x,1.0-aux.y)).r:1.0;
 ALBEDO=base;ROUGHNESS=mix(rough,mix(.26,.14,gFresh),gInk);METALLIC=gTexORM.b*(1.0-gInk);
 AO=1.0;AO_LIGHT_AFFECT=0.0;SPECULAR=mix(.5,.27386128,gInk);
 #include "res://assets/shaders/source_surface_physical.gdshaderinc"
}
