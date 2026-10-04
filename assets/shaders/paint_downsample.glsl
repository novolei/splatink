// Box-filtered mip chain for the persistent source paint atlas.
#[vertex]
#version 450
void main(){vec2 p=vec2(gl_VertexIndex==1?2.0:0.0,gl_VertexIndex==2?2.0:0.0);gl_Position=vec4(p*2.0-1.0,0.0,1.0);}
#[fragment]
#version 450
layout(set=0,binding=0)uniform sampler2D source_level;
layout(push_constant,std430)uniform Params{vec4 dimensions;}p;
layout(location=0)out vec4 out_color;
void main(){vec2 uv=gl_FragCoord.xy/p.dimensions.xy;vec2 d=.25/p.dimensions.xy;out_color=(texture(source_level,uv+vec2(-d.x,-d.y))+texture(source_level,uv+vec2(d.x,-d.y))+texture(source_level,uv+vec2(-d.x,d.y))+texture(source_level,uv+vec2(d.x,d.y)))*.25;}
