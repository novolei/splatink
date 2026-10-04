class_name SplatReticleShadow
extends Control
## Reusable 384px mask + separable Gaussian surfaces. No readback or viewport allocation per frame.
## Each CSS drop-shadow blurs the alpha of the previous composite, including its shadows.
const DIM:int=384
const FILTER:Shader=preload("res://assets/ui/hud_reticle_shadow.gdshader")
const RESOLVE:Shader=preload("res://assets/ui/hud_reticle_resolve.gdshader")
class Mask:
	extends Control
	var host:Control
	var method:StringName=&"paint_mask"
	var manager:Control
	func _draw()->void:
		var started:int=Time.get_ticks_usec() if manager.get("_measure") else 0
		host.call(method,self)
		if started:manager.set("_mask_draw_usec",Time.get_ticks_usec()-started)
var host:Control
var mask:Mask
var surfaces:Array[SubViewport]=[]
var filters:Array[ShaderMaterial]=[]
var output:ColorRect
var _kernels:Dictionary={}
var _filter_key:String=""
var _visible:bool=false
var _stack:Array=[]
var _layers:int=0
var _measure:bool=false
var _last_requested_frame:int=-99
var _render_batches:int=0
var _cache_hits:int=0
var _mask_redraw_calls:int=0
var _gpu_last_ms:float=0
var _cpu_last_ms:float=0
var _process_usec:int=0
var _mask_draw_usec:int=0

func configure(reticle:Control,mask_method:StringName=&"paint_mask",layers:int=3)->void:
	host=reticle;mouse_filter=Control.MOUSE_FILTER_IGNORE;size=Vector2(DIM,DIM)
	_measure=reticle.get("_profile_enabled")==true and DisplayServer.get_name()!="headless"
	var viewport:SubViewport=_surface()
	mask=Mask.new();mask.host=host;mask.method=mask_method;mask.manager=self;mask.size=size;mask.mouse_filter=Control.MOUSE_FILTER_IGNORE;viewport.add_child(mask)
	var previous:Texture2D=viewport.get_texture()
	for index:int in clampi(layers,1,3):
		var horizontal:SubViewport=_surface();var horizontal_material:ShaderMaterial=_pass(horizontal,previous,previous,false)
		horizontal_material.set_shader_parameter("texel_axis",Vector2(1.0/DIM,0))
		var vertical:SubViewport=_surface();var vertical_material:ShaderMaterial=_pass(vertical,horizontal.get_texture(),previous,true)
		vertical_material.set_shader_parameter("texel_axis",Vector2(0,1.0/DIM));previous=vertical.get_texture()
	output=ColorRect.new();output.size=size;output.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var resolve:ShaderMaterial=ShaderMaterial.new();resolve.shader=RESOLVE;output.material=resolve;add_child(output)
	var initial:Array=[{"sigma":1.0,"color":Color(0,0,0,.95)}]
	if layers>1:initial.append({"sigma":2.0,"color":Color(0,0,0,.45),"offset":Vector2(0,1)})
	set_stack(initial)
	visibility_changed.connect(_visibility)
	_visibility()

func _surface()->SubViewport:
	var viewport:SubViewport=SubViewport.new();viewport.name="ShadowSurface%d"%surfaces.size();viewport.size=Vector2i(DIM,DIM);viewport.disable_3d=true;viewport.transparent_bg=true;viewport.world_2d=World2D.new();viewport.gui_disable_input=true;viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	add_child(viewport);surfaces.append(viewport)
	if _measure:RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(),true)
	return viewport

func _pass(viewport:SubViewport,input:Texture2D,original:Texture2D,composite:bool)->ShaderMaterial:
	var material:ShaderMaterial=ShaderMaterial.new();material.shader=FILTER;material.set_shader_parameter("input_tex",input);material.set_shader_parameter("original_tex",original);material.set_shader_parameter("composite",composite)
	var quad:ColorRect=ColorRect.new();quad.size=Vector2(DIM,DIM);quad.material=material;quad.mouse_filter=Control.MOUSE_FILTER_IGNORE;viewport.add_child(quad);filters.append(material);return material

func set_stack(stack:Array)->void:
	if stack==_stack:_cache_hits+=1;return
	_stack=stack;_layers=stack.size();_filter_key=str(stack)
	for index:int in stack.size():
		var record:Dictionary=stack[index];var sigma:float=clampf(float(record.sigma),.15,6.0)
		var kernel:Dictionary=_kernel(sigma)
		for axis:int in 2:
			var material:ShaderMaterial=filters[index*2+axis];material.set_shader_parameter("weights",kernel.weights);material.set_shader_parameter("radius",kernel.radius);material.set_shader_parameter("shadow_color",record.color);material.set_shader_parameter("offset_px",record.get("offset",Vector2.ZERO) if axis==1 else Vector2.ZERO)
	(output.material as ShaderMaterial).set_shader_parameter("source_tex",surfaces[stack.size()*2].get_texture())
	_request_render()

func redraw_mask()->void:
	_mask_redraw_calls+=1
	mask.queue_redraw()
	_request_render()

func _visibility()->void:
	_visible=is_visible_in_tree()
	if _visible:_request_render()
	else:
		for viewport:SubViewport in surfaces:viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED

func _request_render()->void:
	if not _visible:return
	var frame:int=Engine.get_process_frames()
	if _last_requested_frame!=frame:_render_batches+=1;_last_requested_frame=frame
	for index:int in surfaces.size():surfaces[index].render_target_update_mode=SubViewport.UPDATE_ONCE if index<=_layers*2 else SubViewport.UPDATE_DISABLED

func _process(_dt:float)->void:
	if not _measure or not _visible:return
	var started:int=Time.get_ticks_usec()
	_gpu_last_ms=0;_cpu_last_ms=0
	for index:int in _layers*2+1:
		var rid:RID=surfaces[index].get_viewport_rid()
		_gpu_last_ms+=RenderingServer.viewport_get_measured_render_time_gpu(rid)
		_cpu_last_ms+=RenderingServer.viewport_get_measured_render_time_cpu(rid)
	_process_usec=Time.get_ticks_usec()-started

func profile_metrics()->Dictionary:
	var recent:bool=_visible and Engine.get_process_frames()-_last_requested_frame<=1
	return {"gpu_last_ms":_gpu_last_ms,"cpu_last_ms":_cpu_last_ms,"process_cpu_ms":_process_usec/1000.0 if _measure and _visible else 0.0,"mask_draw_cpu_ms":_mask_draw_usec/1000.0 if recent else 0.0,"gpu_recent_ms":_gpu_last_ms if recent else 0.0,"cpu_recent_ms":_cpu_last_ms if recent else 0.0,"surface_count":surfaces.size(),"requested_surface_count":_layers*2+1 if recent else 0,"render_batches":_render_batches,"cache_hits":_cache_hits,"request_frame":_last_requested_frame,"timers_enabled":_measure}

func _kernel(sigma:float)->Dictionary:
	var value:float=snappedf(sigma,.025)
	if _kernels.has(value):return _kernels[value]
	var radius:int=mini(18,ceili(value*3));var weights:PackedFloat32Array=PackedFloat32Array();weights.resize(37);var sum:float=0
	for offset:int in range(-radius,radius+1):
		var weight:float=exp(-float(offset*offset)/(2*value*value));weights[offset+18]=weight;sum+=weight
	for index:int in weights.size():weights[index]/=sum
	var result:Dictionary={"weights":weights,"radius":radius};_kernels[value]=result;return result

func debug_state()->Dictionary:
	return {"surface_count":surfaces.size(),"size":DIM,"readbacks":0,"filter_key":_filter_key,"kernel_cache":_kernels.size(),"render_batches":_render_batches,"cache_hits":_cache_hits,"request_frame":_last_requested_frame,"mask_redraw_calls":_mask_redraw_calls}
