// Original built-in material colour/normal/weathering hooks 5.
shader_type spatial;
render_mode cull_disabled,fog_disabled,unshaded;
uniform vec3 base_color=vec3(1.0,1.0,1.0);uniform vec3 emission_color=vec3(0.0,0.0,0.0);uniform float emission_intensity=0.0;uniform sampler2D emissive_map:filter_linear_mipmap;uniform float has_emissive_map=0.0;varying vec3 source_camera;
varying vec3 vLsW;

uniform vec3 uHzA; uniform vec3 uHzB; uniform vec4 uHzK; uniform float uHzStart;
float lsHazeAmt(vec3 w) {
  float d = max(distance(w, source_camera) - uHzStart, 0.0);
  float h = exp(-max(w.y, 0.0) * uHzK.y);
  return 1.0 - exp(-d * uHzK.x * (0.3 + 0.7 * h));
}
vec3 lsHazeCol(vec3 w) { return mix(uHzA, uHzB, smoothstep(uHzK.z, uHzK.w, -w.z) * (0.55 + 0.45 * exp(-max(w.y, 0.0) * 0.08))); }
uniform vec3 hemi_sky=vec3(0.0);uniform vec3 hemi_ground=vec3(0.0);

float saturate(float x){return clamp(x,0.0,1.0);}
void vertex(){source_camera=CAMERA_POSITION_WORLD;vLsW=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;}
void fragment(){vec4 diffuseColor=vec4(base_color*COLOR.rgb,1.0);vec3 normal=NORMAL;vec3 vViewPosition=-VERTEX;float roughnessFactor=0.8;float metalnessFactor=0.0;vec3 totalEmissiveRadiance=emission_color*emission_intensity*mix(vec3(1.0),texture(emissive_map,vec2(UV.x,1.0-UV.y)).rgb,has_emissive_map);vec3 nativeReflection=vec3(0.0);






float haze=lsHazeAmt(vLsW);ALBEDO=diffuseColor.rgb*(1.0-haze);ROUGHNESS=roughnessFactor;METALLIC=metalnessFactor;NORMAL=normal;EMISSION=(totalEmissiveRadiance+nativeReflection)*(1.0-haze)+lsHazeCol(vLsW)*haze;}
