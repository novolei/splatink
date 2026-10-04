extends SceneTree
## Serialized GPU QA only; prototype resources are excluded from release builds.
const Transport=preload("res://tests/ao/normal_transport.gd")
const Capture=preload("res://tests/ao/normal_capture.gd")
const NORMAL_SHADER=preload("res://tests/ao/geometry_normal.gdshader")
var _fixture:Dictionary
var _records:Dictionary={}
var _report:Dictionary={"checks":0,"failures":0,"cases":[],"source_normal_max_error":0.0,"source_depth_max_error":0.0,"coverage_mismatches":0,"transport_byte_mismatches":0}

func _initialize()->void:
	create_timer(30.0).timeout.connect(func():push_error("NORMAL_TRANSPORT watchdog");quit(1))
	_run.call_deferred()

func _run()->void:
	var parsed:Variant=JSON.parse_string(FileAccess.get_file_as_string("res://tests/ao/normal_transport_reference.json"))
	if not parsed is Dictionary:push_error("Missing original normal geometry fixture");quit(1);return
	_fixture=parsed;root.size=Vector2i(320,240)
	for record:Dictionary in _fixture.cases:
		await _run_case(record)
	print("NORMAL_TRANSPORT_CONTRACT "+JSON.stringify(_report))
	quit(0 if int(_report.failures)==0 else 1)

func _run_case(record:Dictionary)->void:
	var dimensions:=Vector2i(int(record.size[0]),int(record.size[1]))
	var regular:=_viewport(dimensions);regular.own_world_3d=true;root.add_child(regular)
	var auxiliary:=_viewport(dimensions);auxiliary.world_3d=regular.find_world_3d();root.add_child(auxiliary)
	var scene:=Node3D.new();scene.name="ActualSourceGeometry";regular.add_child(scene)
	var material:=ShaderMaterial.new();material.shader=NORMAL_SHADER
	var rigs:Array[Skeleton3D]=[]
	var skins:Array[Skin]=[]
	for rig_data:Dictionary in record.rigs:
		var rig:=Skeleton3D.new();rig.name="SourceRig%d"%rigs.size();rig.transform=_transform(rig_data.world);scene.add_child(rig)
		var skin:=Skin.new()
		for bone:int in rig_data.bone_names.size():
			rig.add_bone(str(rig_data.bone_names[bone]));rig.set_bone_rest(bone,Transform3D.IDENTITY)
			skin.add_bind(bone,Transform3D.IDENTITY)
			rig.set_bone_global_pose_override(bone,_transform(rig_data.deformation_matrices[bone]),1.0,true)
		rigs.append(rig);skins.append(skin)
	var originals:Array[MeshInstance3D]=[]
	for mesh_data:Dictionary in record.meshes:
		var mesh:=MeshInstance3D.new();mesh.name=str(mesh_data.name).replace(":","_")
		mesh.mesh=_mesh(mesh_data);mesh.material_override=material;mesh.layers=1
		mesh.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;mesh.extra_cull_margin=3.0
		var rig_index:int=int(mesh_data.rig)
		if rig_index>=0:
			var rig:Skeleton3D=rigs[rig_index];rig.add_child(mesh)
			mesh.transform=Transform3D.IDENTITY if mesh_data.world==record.rigs[rig_index].world else rig.global_transform.affine_inverse()*_transform(mesh_data.world)
			mesh.skin=skins[rig_index];mesh.skeleton=rig.get_path()
		else:scene.add_child(mesh);mesh.transform=_transform(mesh_data.world)
		originals.append(mesh)
	for rig:Skeleton3D in rigs:rig.force_update_all_bone_transforms()
	var transport:=Transport.new();transport.attach(scene)
	_check(transport.pairs.size()==originals.size(),"Each source mesh receives one normal child")
	var skinned_count:=0
	for pair:Dictionary in transport.pairs:
		var original:=pair.original as MeshInstance3D
		var child:=pair.child as MeshInstance3D
		_check(original.mesh==child.mesh,"Original Mesh resource shared")
		_check(original.global_transform==child.global_transform,"Identity normal child inherits source transform")
		if pair.skeleton!=null:
			skinned_count+=1
			_check(original.skin==child.skin,"Original Skin resource shared")
			_check(original.get_skin_reference()==child.get_skin_reference(),"Original SkinReference shared")
			_check(original.get_skin_reference().get_skeleton()==child.get_skin_reference().get_skeleton(),"One original GPU bone RID")
	_check(transport.shared_reference_count()==skinned_count,"All skinned normal children share existing registration")
	var main_capture:=Capture.new();var aux_capture:=Capture.new()
	main_capture.captured.connect(_on_captured.bind("regular"));aux_capture.captured.connect(_on_captured.bind("auxiliary"))
	_camera(regular,record,1,main_capture);_camera(auxiliary,record,1<<19,aux_capture)
	for frame:int in 4:await process_frame
	var case_report:Dictionary={"name":record.name,"size":record.size,"meshes":originals.size(),"shared_skin_references":skinned_count,"source_bones":rigs[0].get_bone_count() if not rigs.is_empty() else 0,"setup_us":transport.setup_us,"skipped_source_override_parts":record.skipped_override_parts}
	var initial:Dictionary=await _snapshot(main_capture,aux_capture)
	if initial.has("regular") and initial.has("auxiliary"):
		_compare_transport(initial.regular,initial.auxiliary)
		_compare_source(initial.auxiliary,record,case_report)
		var hidden:MeshInstance3D=originals[4]
		hidden.visible=false
		_check(not (transport.pairs[4].child as MeshInstance3D).is_visible_in_tree(),"Normal proxy inherits original hidden state")
		var visibility:Dictionary=await _snapshot(main_capture,aux_capture)
		if visibility.has("regular") and visibility.has("auxiliary"):
			_compare_transport(visibility.regular,visibility.auxiliary)
			_check(visibility.regular.normal!=initial.regular.normal,"Actual hidden geometry disappears from GPU normal pass")
		hidden.visible=true
		if not rigs.is_empty():
			var rig:Skeleton3D=rigs[0]
			var bone:int=rig.find_bone("head")
			var pose:Transform3D=rig.get_bone_global_pose(bone);pose.origin+=Vector3(.08,.015,0)
			rig.set_bone_global_pose_override(bone,pose,1.0,true);rig.force_update_all_bone_transforms()
			var dynamic:Dictionary=await _snapshot(main_capture,aux_capture)
			if dynamic.has("regular") and dynamic.has("auxiliary"):
				_compare_transport(dynamic.regular,dynamic.auxiliary)
				_check(dynamic.regular.normal!=initial.regular.normal,"Original live bone updates affect shared normal pass")
				_check(transport.shared_reference_count()==skinned_count,"Live bone update does not allocate another SkinReference")
		# Small fixture timings describe submission/readback transport only, not a
		# full eight-player frame budget. No readback occurs in these warm frames.
		var warm_start:int=Time.get_ticks_usec()
		for frame:int in 16:await process_frame
		case_report.warm_frame_mean_us=(Time.get_ticks_usec()-warm_start)/16.0
		case_report.main_draw_calls=regular.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		case_report.auxiliary_draw_calls=auxiliary.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_DRAW_CALLS_IN_FRAME)
		case_report.main_primitives=regular.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		case_report.auxiliary_primitives=auxiliary.get_render_info(Viewport.RENDER_INFO_TYPE_VISIBLE,Viewport.RENDER_INFO_PRIMITIVES_IN_FRAME)
		case_report.capture_submit_mean_us=_mean(aux_capture.dispatch_us)
	_report.cases.append(case_report)
	main_capture.release();aux_capture.release();transport.detach()
	regular.queue_free();auxiliary.queue_free();await process_frame

func _viewport(size:Vector2i)->SubViewport:
	var viewport:=SubViewport.new();viewport.size=size
	viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d=Viewport.MSAA_DISABLED;viewport.screen_space_aa=Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa=false;viewport.use_debanding=false;viewport.mesh_lod_threshold=0.0
	return viewport

func _camera(viewport:SubViewport,record:Dictionary,mask:int,capture:CompositorEffect)->Camera3D:
	var camera:=Camera3D.new();camera.fov=float(record.fov);camera.near=float(record.near);camera.far=float(record.far)
	camera.keep_aspect=Camera3D.KEEP_HEIGHT;camera.cull_mask=mask
	var environment:=Environment.new();environment.background_mode=Environment.BG_COLOR
	environment.background_color=Color.BLACK;environment.tonemap_mode=Environment.TONE_MAPPER_LINEAR;environment.tonemap_exposure=1.0
	environment.ambient_light_source=Environment.AMBIENT_SOURCE_DISABLED;environment.reflected_light_source=Environment.REFLECTION_SOURCE_DISABLED
	camera.environment=environment
	var compositor:=Compositor.new();compositor.compositor_effects=[capture];camera.compositor=compositor
	viewport.add_child(camera);camera.global_transform=_transform(record.camera_world);camera.current=true
	return camera

func _snapshot(main_capture:CompositorEffect,aux_capture:CompositorEffect)->Dictionary:
	_records.clear();main_capture.request_readback=true;aux_capture.request_readback=true
	for frame:int in 12:
		await process_frame;await RenderingServer.frame_post_draw
		if _records.size()>=2:break
	var valid:=true
	for name:String in ["regular","auxiliary"]:
		if not _records.has(name) or _records[name].has("error"):
			valid=false;_check(false,"GPU normal readback "+name+": "+str(_records.get(name,{})))
	return _records.duplicate() if valid else {}

func _on_captured(record:Dictionary,name:String)->void:_records[name]=record

func _mesh(record:Dictionary)->ArrayMesh:
	var arrays:Array=[];arrays.resize(Mesh.ARRAY_MAX)
	for field:String in ["position","normal"]:
		var data:PackedFloat32Array=FileAccess.get_file_as_bytes(record.attributes[field].path).to_float32_array()
		var vectors:=PackedVector3Array();vectors.resize(data.size()/3)
		for vertex:int in vectors.size():vectors[vertex]=Vector3(data[vertex*3],data[vertex*3+1],data[vertex*3+2])
		arrays[Mesh.ARRAY_VERTEX if field=="position" else Mesh.ARRAY_NORMAL]=vectors
	if int(record.rig)>=0:
		arrays[Mesh.ARRAY_BONES]=FileAccess.get_file_as_bytes(record.attributes.bones.path).to_int32_array()
		arrays[Mesh.ARRAY_WEIGHTS]=FileAccess.get_file_as_bytes(record.attributes.weights.path).to_float32_array()
	var indices:PackedInt32Array=FileAccess.get_file_as_bytes(record.index.path).to_int32_array()
	for index:int in range(0,indices.size()-2,3):
		var swap:int=indices[index+1];indices[index+1]=indices[index+2];indices[index+2]=swap
	arrays[Mesh.ARRAY_INDEX]=indices
	var mesh:=ArrayMesh.new();mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,arrays)
	return mesh

func _transform(values:Array)->Transform3D:
	return Transform3D(Basis(Vector3(values[0],values[1],values[2]),Vector3(values[4],values[5],values[6]),Vector3(values[8],values[9],values[10])),Vector3(values[12],values[13],values[14]))

func _compare_transport(regular:Dictionary,auxiliary:Dictionary)->void:
	for channel:String in ["normal","depth"]:
		var original:PackedByteArray=regular[channel];var proxy:PackedByteArray=auxiliary[channel]
		_check(original==proxy,"Normal child "+channel+" readback is bit exact to original mesh camera")
		if original!=proxy:_report.transport_byte_mismatches+=1

func _compare_source(actual:Dictionary,record:Dictionary,case_report:Dictionary)->void:
	var normal:PackedByteArray=actual.normal;var depth:PackedByteArray=actual.depth
	var expected_normal:PackedByteArray=FileAccess.get_file_as_bytes(record.normal.path)
	var expected_depth:PackedByteArray=FileAccess.get_file_as_bytes(record.depth.path)
	_check(normal.size()==expected_normal.size() and depth.size()==expected_depth.size(),"Source/native normal/depth dimensions match")
	if normal.size()!=expected_normal.size() or depth.size()!=expected_depth.size():return
	var normal_error:=0.0;var depth_error:=0.0;var coverage:=0;var normal_failures:=0;var depth_failures:=0
	var worst_normal_pixel:=0;var worst_depth_pixel:=0
	for pixel:int in normal.size()/8:
		var a_depth:float=depth.decode_float(pixel*16);var b_depth:float=expected_depth.decode_float(pixel*16)
		var depth_difference:float=absf(a_depth-b_depth)
		if depth_difference>depth_error:depth_error=depth_difference;worst_depth_pixel=pixel
		_report.checks+=1
		if not is_finite(a_depth) or depth_difference>float(_fixture.depth_absolute_tolerance):depth_failures+=1
		if (a_depth<1.0)!=(b_depth<1.0):coverage+=1
		for channel:int in 4:
			var difference:float=absf(normal.decode_half(pixel*8+channel*2)-expected_normal.decode_half(pixel*8+channel*2))
			if difference>normal_error:normal_error=difference;worst_normal_pixel=pixel
			_report.checks+=1
			if not is_finite(normal.decode_half(pixel*8+channel*2)) or difference>float(_fixture.normal_absolute_tolerance):normal_failures+=1
	_report.failures+=normal_failures+depth_failures+coverage
	_report.source_normal_max_error=maxf(float(_report.source_normal_max_error),normal_error)
	_report.source_depth_max_error=maxf(float(_report.source_depth_max_error),depth_error)
	_report.coverage_mismatches+=coverage
	case_report.merge({"normal_max_error":normal_error,"depth_max_error":depth_error,"normal_failed_channels":normal_failures,"depth_failed_pixels":depth_failures,"coverage_mismatches":coverage,"worst_normal_pixel":worst_normal_pixel,"worst_depth_pixel":worst_depth_pixel,"color_format":actual.color_format,"depth_format":actual.depth_format})
	if normal_failures+depth_failures+coverage>0:push_error("NORMAL_TRANSPORT source mismatch: "+JSON.stringify(case_report))

func _check(condition:bool,message:String)->void:
	_report.checks+=1
	if not condition:_report.failures+=1;push_error("NORMAL_TRANSPORT "+message)

func _mean(values:Array[int])->float:
	if values.is_empty():return 0.0
	var total:=0
	for value:int in values:total+=value
	return total/float(values.size())
