shader_type spatial;
render_mode unshaded,cull_back,depth_draw_opaque,fog_disabled,shadows_disabled;
// Same smooth interpolated view normal as the original MeshNormalMaterial.
// No source PBR normal/bump/face vertex patches enter the override pass.
void fragment(){ALBEDO=normalize(NORMAL)*0.5+0.5;}
