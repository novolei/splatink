#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1)in;
layout(set=0,binding=0)uniform sampler2D input_color;
layout(set=0,binding=1)uniform sampler2D denoised;
layout(set=0,binding=4,rgba16f)uniform restrict writeonly image2D result_image;
layout(set=0,binding=5,std140)uniform SceneParams{
 mat4 projection;mat4 projection_inverse;mat4 world;
 vec4 size_radius_exponent;vec4 thickness_scale_falloff_blend;
 vec4 denoise_phi_radius;vec4 near_far_index;
}p;
#define cameraProjectionMatrix p.projection
#define cameraProjectionMatrixInverse p.projection_inverse
#define cameraWorldMatrix p.world
#define resolution p.size_radius_exponent.xy
#define cameraNear p.near_far_index.x
#define cameraFar p.near_far_index.y

void main(){ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(pixel,ivec2(resolution))))return;
 vec2 uv=(vec2(pixel)+.5)/resolution;vec4 original=textureLod(input_color,uv,0.0);vec4 ao=textureLod(denoised,uv,0.0);
 imageStore(result_image,pixel,original*vec4(mix(vec3(1.0),ao.rgb,p.thickness_scale_falloff_blend.w),ao.a));}
