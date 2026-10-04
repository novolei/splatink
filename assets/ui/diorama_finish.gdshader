shader_type canvas_item;
render_mode unshaded;
uniform sampler2D world_screen:hint_screen_texture,repeat_disable,filter_linear;
uniform float fade=1.0;
uniform bool blur_enabled=true;
void fragment(){
 vec2 uv=SCREEN_UV;vec3 original=texture(world_screen,uv).rgb;vec3 blurred=original;
 if(blur_enabled){vec2 px=SCREEN_PIXEL_SIZE*6.0;blurred=original*.25;
  blurred+=(texture(world_screen,uv+vec2(px.x,0)).rgb+texture(world_screen,uv-vec2(px.x,0)).rgb+texture(world_screen,uv+vec2(0,px.y)).rgb+texture(world_screen,uv-vec2(0,px.y)).rgb)*.125;
  blurred+=(texture(world_screen,uv+px).rgb+texture(world_screen,uv-px).rgb+texture(world_screen,uv+vec2(px.x,-px.y)).rgb+texture(world_screen,uv+vec2(-px.x,px.y)).rgb)*.0625;
  float luma=dot(blurred,vec3(.2126,.7152,.0722));blurred=mix(vec3(luma),blurred,1.12);
 }
 float top=uv.y<.1176?mix(1.0,.55,uv.y/.1176):mix(.55,0.0,clamp((uv.y-.1176)/.1624,0.0,1.0));
 float bot=uv.y>.912?mix(.5,1.0,(uv.y-.912)/.088):mix(0.0,.5,clamp((uv.y-.78)/.132,0.0,1.0));
 vec3 rgb=mix(original,blurred,max(top,bot)*fade);float vig=clamp((length((uv-vec2(.5,.54))/vec2(.7,.76))-.52)/.48,0.0,1.0)*.34*fade;
 rgb=mix(rgb,vec3(.0549,.0392,.1098),vig);COLOR=vec4(rgb,1.0);
}
