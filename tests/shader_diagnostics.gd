extends SceneTree
func _initialize() -> void:
	var shaders:Array[String]=["res://assets/shaders/source_grade.glsl","res://assets/shaders/source_screen_hdr.glsl"]
	for path in shaders:
		var source:RDShaderFile=load(path)
		for stage in [RenderingDevice.SHADER_STAGE_VERTEX,RenderingDevice.SHADER_STAGE_FRAGMENT]:
			var error:=source.get_spirv().get_stage_compile_error(stage)
			if not error.is_empty():print(path," STAGE ",stage," ",error)
	quit()
