extends SceneTree
## Root executes serially on the actual Mobile/Vulkan RenderingDevice.
## Inputs and expected outputs come from original GTAOPass GPU targets.
var _fixture:Dictionary
var _resources:Array[RID]=[]
var _report:Dictionary={"checks":0,"failures":0,"max_absolute_error":0.0,"max_allowed_ratio":0.0,"stages":[],"background_error":0.0,"alpha_error":0.0}

func _initialize()->void:
	create_timer(30.0).timeout.connect(func():push_error("AO_GPU watchdog");quit(1))
	_run.call_deferred()

func _run()->void:
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/ao/source_reference.json"))
	if not parsed is Dictionary:
		push_error("AO_GPU missing original GPU fixture");quit(1);return
	_fixture=parsed
	RenderingServer.call_on_render_thread(_gpu_run)

func _gpu_run()->void:
	var rd:RenderingDevice=RenderingServer.get_rendering_device()
	if rd==null:
		_finish.call_deferred({"checks":0,"failures":1,"reason":"RenderingDevice requires Vulkan GPU"});return
	var shaders:Array[RID]=[]
	var pipelines:Array[RID]=[]
	for stage:String in ["gtao","pd","blend"]:
		var file:RDShaderFile=load("res://tests/ao/source_%s.glsl"%stage)
		if file==null:
			_finish.call_deferred({"checks":0,"failures":1,"reason":"Missing/import-failed native draft kernel "+stage});return
		var spirv:RDShaderSPIRV=file.get_spirv()
		var error:String=spirv.get_stage_compile_error(RenderingDevice.SHADER_STAGE_COMPUTE)
		if not error.is_empty():
			_finish.call_deferred({"checks":0,"failures":1,"reason":"Native draft compilation: "+error});return
		var shader:RID=rd.shader_create_from_spirv(spirv)
		if not shader.is_valid():
			_finish.call_deferred({"checks":0,"failures":1,"reason":"Native AO GPU shader creation failed: "+stage});return
		shaders.append(shader);pipelines.append(rd.compute_pipeline_create(shader))
	var nearest:=_sampler(rd,false,false)
	var linear:=_sampler(rd,true,false)
	var repeat_nearest:=_sampler(rd,false,true)
	for record:Dictionary in _fixture.cases:
		var dimensions:=Vector2i(record.size[0],record.size[1])
		var depth_bytes:PackedByteArray=FileAccess.get_file_as_bytes(record.stages.depth.path)
		var input_bytes:PackedByteArray=FileAccess.get_file_as_bytes(record.stages.input.path)
		var depth:RID=_texture(rd,record.stages.depth)
		var normal:RID=_texture(rd,record.stages.normal)
		var input:RID=_texture(rd,record.stages.input)
		var ao_noise:RID=_texture(rd,record.noises.ao)
		var pd_noise:RID=_texture(rd,record.noises.pd)
		var ao:RID=_texture(rd,{"size":record.size,"format":"rgba16f"},true)
		var pd:RID=_texture(rd,{"size":record.size,"format":"rgba16f"},true)
		var output:RID=_texture(rd,{"size":record.size,"format":"rgba16f"},true)
		var parameters:RID=rd.uniform_buffer_create(256,_parameters(record))
		_resources.append(parameters)
		_dispatch(rd,shaders[0],pipelines[0],dimensions,{0:[nearest,normal],1:[nearest,depth],2:[repeat_nearest,ao_noise]},ao,parameters)
		_dispatch(rd,shaders[1],pipelines[1],dimensions,{0:[nearest,normal],1:[nearest,depth],2:[repeat_nearest,pd_noise],3:[linear,ao]},pd,parameters)
		_dispatch(rd,shaders[2],pipelines[2],dimensions,{0:[linear,input],1:[linear,pd]},output,parameters)
		var ao_bytes:PackedByteArray=rd.texture_get_data(ao,0)
		var pd_bytes:PackedByteArray=rd.texture_get_data(pd,0)
		var output_bytes:PackedByteArray=rd.texture_get_data(output,0)
		_compare(record.name,"ao",ao_bytes,record.stages.ao)
		_compare(record.name,"pd",pd_bytes,record.stages.pd)
		_compare(record.name,"output",output_bytes,record.stages.output)
		# Independent invariants complement the per-pixel original GPU comparison.
		for pixel:int in dimensions.x*dimensions.y:
			if depth_bytes.decode_float(pixel*16)>=1.0:
				var error:float=maxf(absf(ao_bytes.decode_half(pixel*8)-1.0),absf(pd_bytes.decode_half(pixel*8)-1.0))
				_report.background_error=maxf(float(_report.background_error),error)
				_report.checks+=1
				if error>0.00001:_report.failures+=1
			var alpha_error:float=absf(output_bytes.decode_half(pixel*8+6)-input_bytes.decode_half(pixel*8+6))
			_report.alpha_error=maxf(float(_report.alpha_error),alpha_error)
			_report.checks+=1
			if alpha_error>0.00001:_report.failures+=1
		for resource:RID in _resources:rd.free_rid(resource)
		_resources.clear()
	for pipeline:RID in pipelines:rd.free_rid(pipeline)
	for shader:RID in shaders:rd.free_rid(shader)
	for sampler:RID in [nearest,linear,repeat_nearest]:rd.free_rid(sampler)
	_finish.call_deferred(_report)

func _sampler(rd:RenderingDevice,bilinear:bool,repeat_texture:bool)->RID:
	var state:=RDSamplerState.new()
	state.min_filter=RenderingDevice.SAMPLER_FILTER_LINEAR if bilinear else RenderingDevice.SAMPLER_FILTER_NEAREST
	state.mag_filter=state.min_filter
	state.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT if repeat_texture else RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	state.repeat_v=state.repeat_u
	return rd.sampler_create(state)

func _texture(rd:RenderingDevice,record:Dictionary,storage:bool=false)->RID:
	var format:=RDTextureFormat.new()
	format.width=int(record.size[0]);format.height=int(record.size[1])
	match str(record.format):
		"rgba8":format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
		"rgba32f":format.format=RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		_:format.format=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	if storage:format.usage_bits|=RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
	var arrays:Array[PackedByteArray]=[]
	if record.has("path"):arrays.append(FileAccess.get_file_as_bytes(record.path))
	var texture:RID=rd.texture_create(format,RDTextureView.new(),arrays)
	_resources.append(texture);return texture

func _parameters(record:Dictionary)->PackedByteArray:
	var values:=PackedFloat32Array()
	for field:String in ["projection","projection_inverse","world"]:
		for value:float in record[field]:values.append(value)
	var params:Dictionary=record.params
	values.append_array(PackedFloat32Array([record.size[0],record.size[1],params.radius,params.distanceExponent,params.thickness,params.scale,params.distanceFallOff,params.blendIntensity,params.lumaPhi,params.depthPhi,params.normalPhi,params.pdRadius,params.cameraNear,params.cameraFar,params.index,0.0]))
	assert(values.size()==64)
	return values.to_byte_array()

func _dispatch(rd:RenderingDevice,shader:RID,pipeline:RID,size:Vector2i,textures:Dictionary,output:RID,parameters:RID)->void:
	var uniforms:Array[RDUniform]=[]
	for binding:int in textures:
		var pair:Array=textures[binding]
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE;uniform.binding=binding
		uniform.add_id(pair[0]);uniform.add_id(pair[1]);uniforms.append(uniform)
	var image:=RDUniform.new();image.uniform_type=RenderingDevice.UNIFORM_TYPE_IMAGE;image.binding=4;image.add_id(output);uniforms.append(image)
	var buffer:=RDUniform.new();buffer.uniform_type=RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER;buffer.binding=5;buffer.add_id(parameters);uniforms.append(buffer)
	var set:RID=UniformSetCacheRD.get_cache(shader,0,uniforms)
	var list:int=rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(list,pipeline)
	rd.compute_list_bind_uniform_set(list,set,0)
	rd.compute_list_dispatch(list,ceili(size.x/8.0),ceili(size.y/8.0),1)
	rd.compute_list_end()

func _compare(case_name:String,stage_name:String,actual:PackedByteArray,stage:Dictionary)->void:
	var expected:PackedByteArray=FileAccess.get_file_as_bytes(stage.path)
	var maximum:=0.0
	var ratio_max:=0.0
	var failed:=0
	var worst_pixel:=0
	var worst_channel:=0
	if actual.size()!=expected.size() or actual.size()!=int(stage.size[0])*int(stage.size[1])*8:
		_report.failures+=1;_report.stages.append({"case":case_name,"stage":stage_name,"error":"GPU byte size mismatch"});return
	for pixel:int in actual.size()/8:
		for channel:int in 4:
			var offset:int=pixel*8+channel*2
			var reference:float=expected.decode_half(offset)
			var value:float=actual.decode_half(offset)
			var error:float=absf(value-reference)
			var allowed:float=float(_fixture.absolute_tolerance)+absf(reference)*float(_fixture.relative_tolerance)
			var ratio:float=error/allowed
			_report.checks+=1
			if not is_finite(value) or ratio>1.0:failed+=1
			if error>maximum:maximum=error;worst_pixel=pixel;worst_channel=channel
			ratio_max=maxf(ratio_max,ratio)
	_report.failures+=failed
	_report.max_absolute_error=maxf(float(_report.max_absolute_error),maximum)
	_report.max_allowed_ratio=maxf(float(_report.max_allowed_ratio),ratio_max)
	_report.stages.append({"case":case_name,"stage":stage_name,"max_error":maximum,"max_ratio":ratio_max,"failed_channels":failed,"worst_pixel":worst_pixel,"worst_channel":worst_channel})
	if failed>0:push_error("AO_GPU %s/%s: %d channels differ; max=%f ratio=%f pixel=%d channel=%d"%[case_name,stage_name,failed,maximum,ratio_max,worst_pixel,worst_channel])

func _finish(report:Dictionary)->void:
	print("AO_GPU_CONTRACT "+JSON.stringify(report))
	quit(0 if int(report.failures)==0 else 1)
