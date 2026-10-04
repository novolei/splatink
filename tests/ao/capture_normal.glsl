#[compute]
#version 450
layout(local_size_x=8,local_size_y=8,local_size_z=1)in;
layout(set=0,binding=0)uniform sampler2D geometry_color;
layout(set=0,binding=1)uniform sampler2D geometry_depth;
layout(set=0,binding=2,rgba16f)uniform restrict writeonly image2D normal_output;
layout(set=0,binding=3,rgba32f)uniform restrict writeonly image2D depth_output;
layout(push_constant,std430)uniform Params{ivec2 size;int flip_y;int reserved;}p;
void main(){
 ivec2 pixel=ivec2(gl_GlobalInvocationID.xy);if(any(greaterThanEqual(pixel,p.size)))return;
 ivec2 native_pixel=pixel;if(p.flip_y==1)native_pixel.y=p.size.y-1-pixel.y;
 float reversed_depth=texelFetch(geometry_depth,native_pixel,0).r;
 // Camera3D uses the same finite near/far perspective, reversed 0..1.
 // Retain raw float depth here; the original reference sampled D24_8.
 float source_depth=1.0-reversed_depth;
 vec3 normal_rgb=texelFetch(geometry_color,native_pixel,0).rgb;
 // The source normal RT clears with source Color(0x7777ff), in linear space.
 if(reversed_depth==0.0)normal_rgb=vec3(0.184474994500441,0.184474994500441,1.0);
 imageStore(normal_output,pixel,vec4(normal_rgb,1.0));
 imageStore(depth_output,pixel,vec4(source_depth,0.0,0.0,1.0));
}
