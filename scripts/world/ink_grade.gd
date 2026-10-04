class_name InkGrade
extends CompositorEffect
## Original HDR grade and neutral tone curve; HUD is drawn after this pass.
var hurt := 0.0
var flash := 0.0
var bloom_enabled:=true
var _bloom:InkBloom=preload("res://scripts/world/ink_bloom.gd").new()
var _params := PackedFloat32Array([0,0,0,0,1.08,.12,1.07,0,.975,.99,1.035,1,1.025,1,.972,.22])
var _rd: RenderingDevice
var _shader: RID
var _sampler: RID
var _screen_shader: RID
var _screen_buffer: RID
var _screen_fields: Array=[]
var _screen_values:=PackedFloat32Array()
var _screen_enabled:=false
var _lens_texture: RID
var _pipelines: Dictionary={}

func _init() -> void:
	effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color=true
	RenderingServer.call_on_render_thread(_initialize_compute)

func update_screen(screen: InkScreenFx) -> void:
	if not screen:return
	screen.use_compositor=true
	_screen_enabled=screen.enabled
	if not _screen_enabled:return
	var values:=PackedFloat32Array();values.resize(_screen_fields.size()*4)
	for i in _screen_fields.size():
		var field:Dictionary=_screen_fields[i]
		var value=screen.uniforms.get(field.name,0.0)
		match str(field.type):
			"float","int":values[i*4]=float(value)
			"vec2":
				if value is Vector2:values[i*4]=value.x;values[i*4+1]=value.y
			"vec3":
				if value is Vector3:values[i*4]=value.x;values[i*4+1]=value.y;values[i*4+2]=value.z
			"vec4":
				if value is Vector4:values[i*4]=value.x;values[i*4+1]=value.y;values[i*4+2]=value.z;values[i*4+3]=value.w
	_screen_values=values
	var lens:Texture2D=screen.uniforms.get("tLens")
	_lens_texture=lens.get_rid() if lens else RID()

func configure(theme: Dictionary) -> void:
	_bloom.configure(theme)
	var gr: Dictionary=theme.get("grade",{})
	var shadows: Array=gr.get("uShadowTint",[.975,.99,1.035])
	var highlights: Array=gr.get("uHighTint",[1.025,1,.972])
	_params=PackedFloat32Array([0,0,0,0,gr.get("uSat",1.08),gr.get("uVib",.12),gr.get("uContrast",1.07),gr.get("uLift",0),shadows[0],shadows[1],shadows[2],gr.get("uExposure",1),highlights[0],highlights[1],highlights[2],gr.get("uVignette",.22)])

func _initialize_compute() -> void:
	_rd=RenderingServer.get_rendering_device()
	if not _rd:return
	var file: RDShaderFile=load("res://assets/shaders/source_grade.glsl")
	_shader=_rd.shader_create_from_spirv(file.get_spirv())
	var state:=RDSamplerState.new();state.min_filter=RenderingDevice.SAMPLER_FILTER_LINEAR;state.mag_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	state.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE;state.repeat_v=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	_sampler=_rd.sampler_create(state)
	_bloom.initialize(_rd,_sampler)
	_screen_fields=JSON.parse_string(FileAccess.get_file_as_string("res://data/screen_uniforms.json"))
	_screen_values.resize(_screen_fields.size()*4)
	var screen_file:RDShaderFile=load("res://assets/shaders/source_screen_hdr.glsl")
	_screen_shader=_rd.shader_create_from_spirv(screen_file.get_spirv())
	_screen_buffer=_rd.uniform_buffer_create(_screen_values.size()*4,_screen_values.to_byte_array())

func _render_callback(callback: int,render_data: RenderData) -> void:
	if callback!=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT or not _rd or not _shader.is_valid():return
	var buffers:=render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if not buffers:return
	var dimensions:=buffers.get_internal_size()
	if dimensions.x<=0 or dimensions.y<=0:return
	var params:=_params.duplicate();params[0]=dimensions.x;params[1]=dimensions.y;params[2]=hurt;params[3]=flash
	for view in buffers.get_view_count():
		var color:RID=buffers.get_color_layer(view)
		var format:=_rd.texture_get_format(color)
		var copy:=buffers.create_texture("ink_grade","hdr_copy",format.format,RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT,RenderingDevice.TEXTURE_SAMPLES_1,dimensions,1,1,false,false)
		if bloom_enabled:_bloom.render(buffers,color,copy,dimensions,view)
		else:
			var copy_params:=params.duplicate();copy_params[0]=-dimensions.x
			_draw_pass(color,copy,copy_params)
		if _screen_enabled and _screen_shader.is_valid():
			var values:=_screen_values.duplicate()
			for i in _screen_fields.size():
				if _screen_fields[i].name=="uRes":values[i*4]=dimensions.x;values[i*4+1]=dimensions.y
			_rd.buffer_update(_screen_buffer,0,values.size()*4,values.to_byte_array())
			var grade_params:=params.duplicate();grade_params[1]=-dimensions.y
			_draw_pass(copy,color,grade_params)
			var plain_params:=params.duplicate();plain_params[0]=-dimensions.x
			_draw_pass(color,copy,plain_params)
			_draw_pass(copy,color,params,true)
		else:
			_draw_pass(copy,color,params)

func _draw_pass(input: RID,output: RID,params: PackedFloat32Array,screen_pass: bool=false) -> void:
	var shader:RID=_screen_shader if screen_pass else _shader
	var framebuffer:=_rd.framebuffer_create([output]);var framebuffer_format:=_rd.framebuffer_get_format(framebuffer)
	var key:=Vector2i(shader.get_id(),framebuffer_format)
	if not _pipelines.has(key):
		var raster:=RDPipelineRasterizationState.new();raster.cull_mode=RenderingDevice.POLYGON_CULL_DISABLED
		var blend:=RDPipelineColorBlendState.new();blend.attachments=[RDPipelineColorBlendStateAttachment.new()]
		_pipelines[key]=_rd.render_pipeline_create(shader,framebuffer_format,RenderingDevice.INVALID_ID,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend)
	var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE;uniform.binding=0;uniform.add_id(_sampler);uniform.add_id(input)
	var uniforms:Array[RDUniform]=[uniform]
	if screen_pass:
		var lens:RID=RenderingServer.texture_get_rd_texture(_lens_texture) if _lens_texture.is_valid() else RID()
		var image:=RDUniform.new();image.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE;image.binding=1;image.add_id(_sampler);image.add_id(lens if lens.is_valid() else input);uniforms.append(image)
		var buffer:=RDUniform.new();buffer.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER;buffer.binding=2;buffer.add_id(_screen_buffer);uniforms.append(buffer)
	var set:=UniformSetCacheRD.get_cache(shader,0,uniforms)
	var draw:=_rd.draw_list_begin(framebuffer);_rd.draw_list_bind_render_pipeline(draw,_pipelines[key]);_rd.draw_list_bind_uniform_set(draw,set,0)
	_rd.draw_list_set_push_constant(draw,params.to_byte_array(),64);_rd.draw_list_draw(draw,false,1,3);_rd.draw_list_end();_rd.free_rid(framebuffer)

func _notification(what: int) -> void:
	if what==NOTIFICATION_PREDELETE and _rd:
		_bloom.release()
		if _shader.is_valid():_rd.free_rid(_shader)
		if _sampler.is_valid():_rd.free_rid(_sampler)
		if _screen_shader.is_valid():_rd.free_rid(_screen_shader)
		if _screen_buffer.is_valid():_rd.free_rid(_screen_buffer)

func _release(shader: RID) -> void:
	if _rd and shader.is_valid():_rd.free_rid(shader)
