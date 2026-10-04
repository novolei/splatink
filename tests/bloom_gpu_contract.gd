extends SceneTree
## Root executes this serially with the Mobile/Vulkan GPU backend.
## Compare every pixel against actual Three HDR targets, including odd sizes.
const Bloom = preload("res://scripts/world/ink_bloom.gd")
var _fixture:Dictionary
var _resources:Array[RID]=[]
var _report:Dictionary={"checks":0,"failures":0,"max_absolute_error":0.0,"max_allowed_ratio":0.0,"stages":[],"alpha_max_error":0.0}

func _initialize()->void:
	create_timer(30.0).timeout.connect(func():push_error("BLOOM_GPU watchdog");quit(1))
	_run.call_deferred()

func _run()->void:
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://data/bloom_gpu_reference.json"))
	if not parsed is Dictionary:
		push_error("BLOOM_GPU missing source GPU fixture");quit(1);return
	_fixture=parsed
	RenderingServer.call_on_render_thread(_gpu_run)

func _gpu_run()->void:
	var rd:RenderingDevice=RenderingServer.get_rendering_device()
	if rd==null:
		_finish.call_deferred({"checks":0,"failures":1,"reason":"RenderingDevice requires Vulkan GPU"});return
	var sampler_state:=RDSamplerState.new()
	sampler_state.min_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter=RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v=RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	var sampler:RID=rd.sampler_create(sampler_state)
	var bloom:=Bloom.new();bloom.initialize(rd,sampler)
	if not bloom._shader.is_valid():
		rd.free_rid(sampler);_finish.call_deferred({"checks":0,"failures":1,"reason":"Bloom shader compilation failed"});return
	for record:Dictionary in _fixture.cases:
		var size:=Vector2i(record.size[0],record.size[1])
		var input_bytes:=FileAccess.get_file_as_bytes(record.stages.input.path)
		var source:RID=_texture(rd,size,input_bytes)
		var output:RID=_texture(rd,size)
		var dims:=_half_size(size)
		var bright:RID=_texture(rd,dims)
		var horizontal:Array[RID]=[]
		var vertical:Array[RID]=[]
		for level in 5:
			horizontal.append(_texture(rd,dims));vertical.append(_texture(rd,dims));dims=_half_size(dims)
		bloom.strength=float(record.strength);bloom.radius=float(record.radius);bloom.threshold=float(record.threshold)
		bloom.render_allocated(source,output,size,bright,horizontal,vertical)
		_compare(record.name,"bright",rd.texture_get_data(bright,0),record.stages.bright)
		for level in 5:_compare(record.name,"vertical%d"%level,rd.texture_get_data(vertical[level],0),record.stages["vertical%d"%level])
		_compare(record.name,"composite",rd.texture_get_data(horizontal[0],0),record.stages.composite)
		var output_bytes:PackedByteArray=rd.texture_get_data(output,0)
		_compare(record.name,"output",output_bytes,record.stages.output)
		# The alpha divergence is intentional: menus use transparent HDR worlds.
		# This independent contract prevents bloom from turning that layer opaque.
		if output_bytes.size()==input_bytes.size():
			for pixel in size.x*size.y:
				var delta:float=absf(output_bytes.decode_half(pixel*8+6)-input_bytes.decode_half(pixel*8+6))
				_report.alpha_max_error=maxf(float(_report.alpha_max_error),delta)
				_report.checks+=1
				if delta>.0001:_report.failures+=1
		else:_report.failures+=1
		for texture:RID in _resources:rd.free_rid(texture)
		_resources.clear()
	bloom.release();rd.free_rid(sampler)
	_finish.call_deferred(_report)

func _texture(rd:RenderingDevice,size:Vector2i,data:PackedByteArray=PackedByteArray())->RID:
	var format:=RDTextureFormat.new()
	format.width=size.x;format.height=size.y
	format.format=RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var arrays:Array[PackedByteArray]=[]
	if not data.is_empty():arrays.append(data)
	var result:RID=rd.texture_create(format,RDTextureView.new(),arrays)
	_resources.append(result);return result

func _half_size(size:Vector2i)->Vector2i:
	return Vector2i(maxi(1,floori(size.x/2.0+.5)),maxi(1,floori(size.y/2.0+.5)))

func _compare(case_name:String,stage_name:String,actual:PackedByteArray,stage:Dictionary)->void:
	var expected:PackedByteArray=FileAccess.get_file_as_bytes(stage.path)
	var maximum:=0.0
	var ratio_max:=0.0
	var failed:=0
	var worst_pixel:=0
	var worst_channel:=0
	if actual.size()!=expected.size() or actual.size()!=int(stage.size[0])*int(stage.size[1])*8:
		_report.failures+=1
		_report.stages.append({"case":case_name,"stage":stage_name,"error":"HDR byte size mismatch"});return
	for pixel in actual.size()/8:
		for channel in 3:
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
	if failed>0:push_error("BLOOM_GPU %s/%s: %d channels differ; max=%f ratio=%f pixel=%d channel=%d"%[case_name,stage_name,failed,maximum,ratio_max,worst_pixel,worst_channel])

func _finish(report:Dictionary)->void:
	print("BLOOM_GPU_CONTRACT "+JSON.stringify(report))
	quit(0 if int(report.failures)==0 else 1)
