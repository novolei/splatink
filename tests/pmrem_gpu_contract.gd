extends SceneTree
## Compare the actual native GPU sampler with actual source Three CubeUV output.
var checks:int=0
var failures:int=0
var worst_error:float=0.0
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/source_radiance.json"))
	var viewport:=SubViewport.new()
	viewport.size=Vector2i(80,1);viewport.use_hdr_2d=true
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var shader:=Shader.new()
	shader.code='shader_type canvas_item;\n#include "res://assets/shaders/source_cube_uv.gdshaderinc"\nuniform vec4 sample_specs[80];\nvoid fragment(){int i=clamp(int(UV.x*80.0),0,79);COLOR=vec4(source_cube_uv(sample_specs[i].xyz,sample_specs[i].w),1.0);}'
	var material:=ShaderMaterial.new();material.shader=shader
	var surface:=ColorRect.new();surface.size=Vector2(80,1);surface.material=material;viewport.add_child(surface)
	for theme:Dictionary in data.stats:
		var specs:=PackedVector4Array()
		for sample:Array in theme.sample_specs:specs.append(Vector4(sample[0],sample[1],sample[2],sample[3]))
		var image:=Image.create_from_data(768,1024,false,Image.FORMAT_RGBAH,FileAccess.get_file_as_bytes(theme.pmrem.path))
		material.set_shader_parameter("source_pmrem",ImageTexture.create_from_image(image))
		material.set_shader_parameter("sample_specs",specs)
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var rendered:Image=viewport.get_texture().get_image()
		for index:int in specs.size():
			var expected:Array=theme.sample_rgb[index]
			var pixel:Color=rendered.get_pixel(index,0)
			var error:float=maxf(absf(pixel.r-expected[0]),maxf(absf(pixel.g-expected[1]),absf(pixel.b-expected[2])))
			worst_error=maxf(worst_error,error);checks+=1
			if error>.002:
				failures+=1;push_error("PMREM "+str(theme.theme)+" sample "+str(index)+" error "+str(error)+" native "+str(pixel)+" source "+str(expected))
	print("PMREM_GPU_CONTRACT "+JSON.stringify({"checks":checks,"failures":failures,"max_linear_error":worst_error}))
	quit(0 if failures==0 else 1)
