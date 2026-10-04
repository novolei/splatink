class_name InkPaintGPU
extends RefCounted
## Original source brush SDF, RGB over-compositing and MAX coverage on the GPU.
## Scoring and ink queries never read the GPU back. All RD work stays on the render thread.
const MAX_BRUSHES := 6000
var texture := Texture2DRD.new()
var size := 2048
var ready := false
var _queue := PackedFloat32Array()
var _dry_acc := 0.0
var _rd: RenderingDevice
var _image: RID
var _framebuffer: RID
var _shader: RID
var _buffer: RID
var _uniform: RID
var _pipeline: RID
var _dry_pipeline: RID
var _mip_shader: RID
var _mip_pipeline: RID
var _mip_sampler: RID
var _mip_views: Array[RID]=[]
var _mip_frames: Array[RID]=[]
var _mip_sets: Array[RID]=[]
var _released := false

func initialize(atlas_size: int) -> void:
	size=atlas_size
	RenderingServer.call_on_render_thread(_initialize_rd)

func _initialize_rd() -> void:
	_rd=RenderingServer.get_rendering_device()
	if _rd==null:return
	var format:=RDTextureFormat.new();format.width=size;format.height=size;format.format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	format.mipmaps=floori(log(float(size))/log(2.0))+1
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT|RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT|RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	var blank:=PackedByteArray();var byte_count:=0
	for level in format.mipmaps:var dim:=maxi(1,size>>level);byte_count+=dim*dim*4
	blank.resize(byte_count)
	_image=_rd.texture_create(format,RDTextureView.new(),[blank])
	for level in format.mipmaps:
		var view:=_rd.texture_create_shared_from_slice(RDTextureView.new(),_image,0,level,1);_mip_views.append(view);_mip_frames.append(_rd.framebuffer_create([view]))
	_framebuffer=_mip_frames[0]
	var shader_file:RDShaderFile=load("res://assets/shaders/source_paint.glsl")
	_shader=_rd.shader_create_from_spirv(shader_file.get_spirv())
	_buffer=_rd.storage_buffer_create(MAX_BRUSHES*80)
	var uniform:=RDUniform.new();uniform.uniform_type=RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER;uniform.binding=0;uniform.add_id(_buffer)
	_uniform=_rd.uniform_set_create([uniform],_shader,0)
	_pipeline=_make_pipeline(false);_dry_pipeline=_make_pipeline(true)
	var mip_file: RDShaderFile=load("res://assets/shaders/paint_downsample.glsl");_mip_shader=_rd.shader_create_from_spirv(mip_file.get_spirv())
	_mip_sampler=_rd.sampler_create(RDSamplerState.new())
	var raster:=RDPipelineRasterizationState.new();raster.cull_mode=RenderingDevice.POLYGON_CULL_DISABLED
	var blend:=RDPipelineColorBlendState.new();blend.attachments=[RDPipelineColorBlendStateAttachment.new()]
	_mip_pipeline=_rd.render_pipeline_create(_mip_shader,_rd.framebuffer_get_format(_framebuffer),RenderingDevice.INVALID_ID,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend)
	for level in range(1,format.mipmaps):
		var input:=RDUniform.new();input.uniform_type=RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE;input.binding=0;input.add_id(_mip_sampler);input.add_id(_mip_views[level-1]);_mip_sets.append(_rd.uniform_set_create([input],_mip_shader,0))
	texture.texture_rd_rid=_image
	ready=_pipeline.is_valid() and _dry_pipeline.is_valid()

func _make_pipeline(drying: bool) -> RID:
	var blend:=RDPipelineColorBlendState.new();var attachment:=RDPipelineColorBlendStateAttachment.new();attachment.enable_blend=true
	attachment.src_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE if drying else RenderingDevice.BLEND_FACTOR_SRC_ALPHA
	attachment.dst_color_blend_factor=RenderingDevice.BLEND_FACTOR_ONE if drying else RenderingDevice.BLEND_FACTOR_ONE_MINUS_SRC_ALPHA
	attachment.color_blend_op=RenderingDevice.BLEND_OP_REVERSE_SUBTRACT if drying else RenderingDevice.BLEND_OP_ADD
	attachment.src_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ZERO if drying else RenderingDevice.BLEND_FACTOR_ONE
	attachment.dst_alpha_blend_factor=RenderingDevice.BLEND_FACTOR_ONE
	attachment.alpha_blend_op=RenderingDevice.BLEND_OP_ADD if drying else RenderingDevice.BLEND_OP_MAXIMUM
	blend.attachments=[attachment]
	var raster:=RDPipelineRasterizationState.new();raster.cull_mode=RenderingDevice.POLYGON_CULL_DISABLED
	return _rd.render_pipeline_create(_shader,_rd.framebuffer_get_format(_framebuffer),RenderingDevice.INVALID_ID,RenderingDevice.RENDER_PRIMITIVE_TRIANGLES,raster,RDPipelineMultisampleState.new(),RDPipelineDepthStencilState.new(),blend)

func stamp(face: Dictionary,s: Dictionary,tn: float,drip: float,drip_only: bool) -> void:
	if _queue.size()/20>=MAX_BRUSHES:return
	var kind:int=["shot","line","blast","bomb","trail","drop","roll","speck"].find(s.kind)
	if kind<0:kind=4
	var reaches:Array=[2.45,2.1,2.7,2.75,2.3,1.9,1.25,1.35]
	var r:float=s.radius;var reach:float=r*(reaches[kind]+1.4*s.smear)
	var u0:float=s.u-reach;var u1:float=s.u+reach;var v0:float=s.v-maxf(reach,r*3.9 if s.drip_dur>0 else 0);var v1:float=s.v+reach
	if drip_only:u0=s.u-r*.95;u1=s.u+r*.95;v0=s.v-r*3.9;v1=s.v-r*.3
	var a:Dictionary=face.atlas;var margin:float=(a.pad-.5)/a.ppm
	u0=maxf(-margin,u0);u1=minf(face.su+margin,u1);v0=maxf(-margin,v0);v1=minf(face.sv+margin,v1)
	if u1<=u0 or v1<=v0:return
	_queue.append_array(PackedFloat32Array([a.x+a.pad+u0*a.ppm,a.y+a.pad+v0*a.ppm,a.x+a.pad+u1*a.ppm,a.y+a.pad+v1*a.ppm,a.x+a.pad+s.u*a.ppm,a.y+a.pad+s.v*a.ppm,a.ppm,s.get("dn",0),s.get("R",r),s.team,s.seed,(1 if face.wall else 0)+kind*2,s.direction.x,s.direction.y,s.smear,0,tn,drip,1 if drip_only else 0,0]))

func flush(dt: float) -> void:
	_dry_acc+=dt
	var steps:=floori(_dry_acc*40)
	var dry:=0.0
	if steps>=2:steps=mini(steps,12);_dry_acc-=float(steps)/40;dry=float(steps)/255
	if not ready or (_queue.is_empty() and dry==0):return
	var pending:=_queue.to_byte_array();_queue.clear()
	RenderingServer.call_on_render_thread(_draw.bind(pending,dry))

func _draw(data: PackedByteArray,dry: float) -> void:
	if _released or not ready:return
	if not data.is_empty():_rd.buffer_update(_buffer,0,data.size(),data)
	var draw:=_rd.draw_list_begin(_framebuffer)
	_rd.draw_list_bind_uniform_set(draw,_uniform,0)
	if dry>0:
		_rd.draw_list_bind_render_pipeline(draw,_dry_pipeline)
		var constants:=PackedFloat32Array([-1,dry,size,0]).to_byte_array();_rd.draw_list_set_push_constant(draw,constants,16);_rd.draw_list_draw(draw,false,1,6)
	if not data.is_empty():
		_rd.draw_list_bind_render_pipeline(draw,_pipeline)
		var constants:=PackedFloat32Array([data.size()/80,0,size,0]).to_byte_array();_rd.draw_list_set_push_constant(draw,constants,16);_rd.draw_list_draw(draw,false,1,data.size()/80*6)
	_rd.draw_list_end()
	for level in range(1,_mip_frames.size()):
		var mip_draw:=_rd.draw_list_begin(_mip_frames[level]);_rd.draw_list_bind_render_pipeline(mip_draw,_mip_pipeline);_rd.draw_list_bind_uniform_set(mip_draw,_mip_sets[level-1],0)
		var dim:=float(maxi(1,size>>level));var constants:=PackedFloat32Array([dim,dim,0,0]).to_byte_array();_rd.draw_list_set_push_constant(mip_draw,constants,16);_rd.draw_list_draw(mip_draw,false,1,3);_rd.draw_list_end()

func release() -> void:
	ready=false;texture.texture_rd_rid=RID()
	RenderingServer.call_on_render_thread(_release_rd)
func _release_rd() -> void:
	_released=true
	if not _rd:return
	for rid in _mip_sets+_mip_frames+_mip_views+[_pipeline,_dry_pipeline,_uniform,_buffer,_shader,_mip_pipeline,_mip_shader,_mip_sampler,_image]:
		if rid.is_valid():_rd.free_rid(rid)
