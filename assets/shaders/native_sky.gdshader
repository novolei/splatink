shader_type sky;
uniform samplerCube source_sky : source_color,filter_linear_mipmap;
uniform samplerCube source_radiance : filter_linear_mipmap;
void sky(){
 if(AT_CUBEMAP_PASS){COLOR=texture(source_radiance,EYEDIR).rgb;}
 else{COLOR=texture(source_sky,EYEDIR).rgb;}
}
