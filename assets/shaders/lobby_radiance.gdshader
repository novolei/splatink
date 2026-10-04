shader_type sky;
uniform samplerCube source_cube:filter_linear_mipmap;
uniform float intensity = 0.6;
void sky(){COLOR = textureLod(source_cube, EYEDIR, 0.0).rgb * intensity;}
