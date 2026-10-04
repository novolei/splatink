extends CompositorEffect
## Isolated pre-tonemap geometry-normal readback. GPU stalls only on QA requests.
signal captured(record:Dictionary)
var request_readback:=false
var frame_count:=0
var dispatch_us:Array[int]=[]
var rd:RenderingDevice
var normal_output:RID
var depth_output:RID
var _shader:RID
var _pipeline:RID
var _sampler:RID
var _size:=Vector2i.ZERO
var _fault_reported:=false

func _init()->void:
	effect_callback_type=EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color=true;access_resolved_depth=true
	RenderingServer.call_on_render_thread(_initialize)

func _initialize()->void:
	rd=RenderingServer.get_rendering_device()
	if rd==null:_fault("RenderingDevice unavailable");return
	var file:RDShaderFile=load("res://tests/ao/capture_normal.glsl")
	if file==null:_fault("Normal capture compute import failed");return
	var spirv:RDShaderSPIRV=file.get_spirv()
	var error:String=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
	if not error.is_empty():_fault(error);return
	_shader=rd.shader_create_from_spirv(spirv);_pipeline=rd.compute_pipeline_create(_shader)
	var sampler:=RDSamplerState.new()
	sampler.min_filter=RenderingDevice.SAMPLER_FILTER_NEAREST;sampler.mag_filter=RenderingDevice.SAMPLER_FILTER_NEAREST
	sampler.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE;sampler.repeat_v=sampler.repeat_u
	_sampler=rd.sampler_create(sampler)

func _render_callback(callback:int,data:RenderData)->void:
	if callback!=effect_callback_type or rd==null or not _pipeline.is_valid():return
	var started:int=Time.get_ticks_usec()
	var buffers:=data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers==null:return
	var size:Vector2i=buffers.get_internal_size()
	if size.x==0 or size.y==0:return
	if _size!=size:
		if normal_output.is_valid():rd.free_rid(normal_output);rd.free_rid(depth_output)
		normal_output=_texture(size,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
		depth_output=_texture(size,RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT);_size=size
	var uniforms:Array[RDUniform]=[]
	for binding:int in 2:
		var value:RID=buffers.get_color_layer(0) if binding==0 else buffers.get_depth_layer(0)
		var uniform:=RDUniform.new();uniform.binding=binding;uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform.add_id(_sampler);uniform.add_id(value);uniforms.append(uniform)
	for binding:int in [2,3]:
		var uniform:=RDUniform.new();uniform.binding=binding;uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.add_id(normal_output if binding==2 else depth_output);uniforms.append(uniform)
	var set:RID=UniformSetCacheRD.get_cache(_shader,0,uniforms)
	var list:int=rd.compute_list_begin();rd.compute_list_bind_compute_pipeline(list,_pipeline)
	rd.compute_list_bind_uniform_set(list,set,0)
	rd.compute_list_set_push_constant(list,PackedInt32Array([size.x,size.y,1,0]).to_byte_array(),16)
	rd.compute_list_dispatch(list,ceili(size.x/8.0),ceili(size.y/8.0),1);rd.compute_list_end()
	frame_count+=1;dispatch_us.append(Time.get_ticks_usec()-started)
	if request_readback:
		request_readback=false
		var result:Dictionary={"size":[size.x,size.y],"normal":rd.texture_get_data(normal_output,0),"depth":rd.texture_get_data(depth_output,0),"color_format":rd.texture_get_format(buffers.get_color_layer(0)).format,"depth_format":rd.texture_get_format(buffers.get_depth_layer(0)).format}
		_emit.call_deferred(result)

func _texture(size:Vector2i,data_format:int)->RID:
	var format:=RDTextureFormat.new();format.width=size.x;format.height=size.y;format.format=data_format
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT|RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	return rd.texture_create(format,RDTextureView.new())

func _fault(message:String)->void:
	if _fault_reported:return
	_fault_reported=true;_emit.call_deferred({"error":message})

func _emit(record:Dictionary)->void:captured.emit(record)

func release()->void:RenderingServer.call_on_render_thread(_release)

func _release()->void:
	if rd==null:return
	for resource:RID in [_pipeline,_shader,_sampler,normal_output,depth_output]:
		if resource.is_valid():rd.free_rid(resource)
