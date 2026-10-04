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

func initialize(device:RenderingDevice,sampler:RID)->void:
	_rd=device;_sampler=sampler
	var source:RDShaderFile=load("res://assets/shaders/source_bloom.glsl")
	_shader=_rd.shader_create_from_spirv(source.get_spirv())

func configure(theme:Dictionary)->void:
	var settings:Array=theme.get("grade",{}).get("bloom",[.28,.45,2.4])
	strength=float(settings[0]);radius=float(settings[1]);threshold=float(settings[2])

func render(buffers:RenderSceneBuffersRD,source:RID,output:RID,size:Vector2i,view:int)->void:
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
	var framebuffer:=_rd.framebuffer_create([output])
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
	_rd.draw_list_set_push_constant(draw,params.to_byte_array(),64);_rd.draw_list_draw(draw,false,1,3);_rd.draw_list_end();_rd.free_rid(framebuffer)

func release()->void:
	if _rd and _shader.is_valid():_rd.free_rid(_shader)
