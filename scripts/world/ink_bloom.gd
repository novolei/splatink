class_name InkBloom
extends RefCounted
## Source HDR bloom, evaluated before grade/tone mapping entirely on the GPU.
var strength:=0.28
var radius:=0.45
var threshold:=2.4
var _rd:RenderingDevice
var _shader:RID
var _sampler:RID
var _pipelines:Dictionary={}
var _framebuffers:Dictionary={}
var _framebuffer_contexts:Dictionary={}
var _framebuffer_context:int=0
var _framebuffer_size:=Vector2i.ZERO

func initialize(device:RenderingDevice,sampler:RID)->void:
	_rd=device;_sampler=sampler
	var source:RDShaderFile=load("res://assets/shaders/source_bloom.glsl")
	_shader=_rd.shader_create_from_spirv(source.get_spirv())

func configure(theme:Dictionary)->void:
	var settings:Array=theme.get("grade",{}).get("bloom",[.28,.45,2.4])
	strength=float(settings[0]);radius=float(settings[1]);threshold=float(settings[2])

func render(buffers:RenderSceneBuffersRD,source:RID,output:RID,size:Vector2i,view:int)->void:
	_prepare_framebuffer_cache(size,buffers.get_instance_id(),buffers)
	var format:=_rd.texture_get_format(source).format
	var dimensions:=Vector2i(maxi(1,floori(size.x/2.0+.5)),maxi(1,floori(size.y/2.0+.5)))
	var bright:=_texture(buffers,format,"bright_%d"%view,dimensions)
	var horizontal:Array[RID]=[]
	var vertical:Array[RID]=[]
	for level in 5:
		horizontal.append(_texture(buffers,format,"horizontal_%d_%d"%[view,level],dimensions))
		vertical.append(_texture(buffers,format,"vertical_%d_%d"%[view,level],dimensions))
		dimensions=Vector2i(maxi(1,floori(dimensions.x/2.0+.5)),maxi(1,floori(dimensions.y/2.0+.5)))
	render_allocated(source,output,size,bright,horizontal,vertical)

## The production render path and GPU contract share the exact same passes.
## All supplied textures must use the source HDR format and source round(size/2).
func render_allocated(source:RID,output:RID,size:Vector2i,bright:RID,horizontal:Array[RID],vertical:Array[RID])->void:
	assert(horizontal.size()==5 and vertical.size()==5)
	_prepare_framebuffer_cache(size)
	var dimensions:=Vector2i(maxi(1,floori(size.x/2.0+.5)),maxi(1,floori(size.y/2.0+.5)))
	_draw(source,bright,dimensions,0,0,Vector2.ZERO,[])
	var input:RID=bright
	for level in 5:
		_draw(input,horizontal[level],dimensions,1,level,Vector2.RIGHT,[])
		_draw(horizontal[level],vertical[level],dimensions,1,level,Vector2.DOWN,[])
		input=vertical[level]
		dimensions=Vector2i(maxi(1,floori(dimensions.x/2.0+.5)),maxi(1,floori(dimensions.y/2.0+.5)))
	# Three writes the composite into the first HALF target before the final
	# full-size additive upsample. Preserve that quantization and filtering.
	dimensions=Vector2i(maxi(1,floori(size.x/2.0+.5)),maxi(1,floori(size.y/2.0+.5)))
	_draw(source,horizontal[0],dimensions,2,0,Vector2.ZERO,vertical)
	var composite:Array[RID]=[horizontal[0],horizontal[0],horizontal[0],horizontal[0],horizontal[0]]
	_draw(source,output,size,3,0,Vector2.ZERO,composite)

func _texture(buffers:RenderSceneBuffersRD,format:int,name:String,size:Vector2i)->RID:
	return buffers.create_texture("ink_bloom",name,format,RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT,RenderingDevice.TEXTURE_SAMPLES_1,size,1,1,false,false)

func _draw(source:RID,output:RID,size:Vector2i,mode:int,kernel:int,direction:Vector2,mips:Array[RID])->void:
	var framebuffer:=_framebuffer_for_output(output)
	var format:=_rd.framebuffer_get_format(framebuffer)
	if not _pipelines.has(format):
		var raster:=RDPipelineRasterizationState.new();raster.cull_mode=RenderingDevice.POLYGON_CULL_DISABLED
		var blend:=RDPipelineColorBlendState.new();blend.attachments=[RDPipelineColorBlendStateAttachment.new()]
		_pipelines[format]=_rd.render_pipeline_create(_shader,format,RenderingDevice.INVALID_ID,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend)
	var uniforms:Array[RDUniform]=[]
	for binding in 6:
		var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE;uniform.binding=binding;uniform.add_id(_sampler)
		uniform.add_id(source if binding==0 or mips.is_empty() else mips[binding-1]);uniforms.append(uniform)
	var set:=UniformSetCacheRD.get_cache(_shader,0,uniforms)
	var params:=PackedFloat32Array([size.x,size.y,mode,kernel,direction.x,direction.y,threshold,strength,radius,0,0,0,0,0,0,0])
	var draw:=_rd.draw_list_begin(framebuffer)
	_rd.draw_list_bind_render_pipeline(draw,_pipelines[format]);_rd.draw_list_bind_uniform_set(draw,set,0)
	_rd.draw_list_set_push_constant(draw,params.to_byte_array(),64);_rd.draw_list_draw(draw,false,1,3);_rd.draw_list_end()

## The full RID is the key; its immutable attachment format is also checked.
## RD automatically destroys a framebuffer when its attachment is destroyed.
func _framebuffer_for_output(output:RID)->RID:
	var texture_format:int=_rd.texture_get_format(output).format
	var cached:Dictionary=_framebuffers.get(output,{})
	var framebuffer:RID=cached.get("framebuffer",RID())
	var contexts:Dictionary=cached.get("contexts",{})
	contexts[_framebuffer_context]=true
	if not cached.is_empty() and int(cached.texture_format)==texture_format and framebuffer.is_valid() and _rd.framebuffer_is_valid(framebuffer):
		return framebuffer
	if framebuffer.is_valid() and _rd.framebuffer_is_valid(framebuffer):_rd.free_rid(framebuffer)
	framebuffer=_rd.framebuffer_create([output])
	_framebuffers[output]={"texture_format":texture_format,"framebuffer":framebuffer,"contexts":contexts}
	return framebuffer

func _prepare_framebuffer_cache(size:Vector2i,context:int=0,owner:Object=null)->void:
	if context!=0:_framebuffer_context=context
	if not _framebuffer_contexts.has(_framebuffer_context):
		_framebuffer_contexts[_framebuffer_context]={"size":size,"owner":weakref(owner) if owner else null}
	else:
		var state:Dictionary=_framebuffer_contexts[_framebuffer_context]
		if state.size!=size:
			_clear_framebuffer_cache(_framebuffer_context,false)
			state.size=size
		if owner and state.owner==null:state.owner=weakref(owner)
	_framebuffer_size=size
	# Main and reflection viewports may share this effect. Keep both contexts;
	# resizing or deleting one must not rebuild the other's framebuffers.
	for id in _framebuffer_contexts.keys():
		var reference:WeakRef=_framebuffer_contexts[id].owner
		if reference and reference.get_ref()==null:
			_clear_framebuffer_cache(int(id),false)
			_framebuffer_contexts.erase(id)
	for output in _framebuffers.keys():
		var framebuffer:RID=_framebuffers[output].framebuffer
		if not framebuffer.is_valid() or not _rd.framebuffer_is_valid(framebuffer):_framebuffers.erase(output)

## Full clear is explicit: RefCounted ObjectIDs can be negative.
func _clear_framebuffer_cache(context:int=0,all_contexts:bool=true)->void:
	for output in _framebuffers.keys():
		var cached:Dictionary=_framebuffers[output]
		var contexts:Dictionary=cached.contexts
		if not all_contexts:
			contexts.erase(context)
			if not contexts.is_empty():continue
		var framebuffer:RID=cached.framebuffer
		if _rd and framebuffer.is_valid() and _rd.framebuffer_is_valid(framebuffer):_rd.free_rid(framebuffer)
		_framebuffers.erase(output)

## Call on the render thread, as with initialize/render.
func release()->void:
	_clear_framebuffer_cache()
	if _rd and _shader.is_valid():_rd.free_rid(_shader)
	_shader=RID()
	_pipelines.clear()
	_framebuffer_contexts.clear()
	_framebuffer_context=0
	_framebuffer_size=Vector2i.ZERO
