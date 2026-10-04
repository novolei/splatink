extends RefCounted
## QA-only camera layer transport. No production code references this prototype.
## Sharing the SkinReference retains the original GPU bone buffer; MeshInstance3D
## may still allocate a second deformation buffer, which the benchmark measures.
const NORMAL_SHADER=preload("res://tests/ao/geometry_normal.gdshader")
var pairs:Array[Dictionary]=[]
var material:ShaderMaterial
var setup_us:=0

func attach(scene:Node,normal_layer:int=1<<19)->void:
	var started:int=Time.get_ticks_usec()
	material=ShaderMaterial.new();material.shader=NORMAL_SHADER
	var originals:Array[Node]=scene.find_children("*","MeshInstance3D",true,false)
	if scene is MeshInstance3D:originals.push_front(scene)
	for node:Node in originals:
		var original:=node as MeshInstance3D
		if original.mesh==null or original.has_meta("ao_normal_child") or bool(original.get_meta("ao_override_excluded",false)):continue
		var child:=MeshInstance3D.new()
		child.name="SourceAONormal";child.set_meta("ao_normal_child",true)
		child.mesh=original.mesh;child.material_override=material;child.layers=normal_layer
		child.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		child.lod_bias=original.lod_bias;child.extra_cull_margin=original.extra_cull_margin
		child.visibility_range_begin=original.visibility_range_begin
		child.visibility_range_end=original.visibility_range_end
		child.visibility_range_begin_margin=original.visibility_range_begin_margin
		child.visibility_range_end_margin=original.visibility_range_end_margin
		child.visibility_range_fade_mode=original.visibility_range_fade_mode
		var skeleton:=original.get_node_or_null(original.skeleton) as Skeleton3D
		var original_ref:SkinReference=original.get_skin_reference()
		if skeleton!=null and original_ref!=null:
			child.skin=original_ref.get_skin()
		original.add_child(child)
		if skeleton!=null and original_ref!=null:child.skeleton=skeleton.get_path()
		for blend:int in original.get_blend_shape_count():child.set_blend_shape_value(blend,original.get_blend_shape_value(blend))
		pairs.append({"original":original,"child":child,"skeleton":skeleton})
	setup_us=Time.get_ticks_usec()-started

func shared_reference_count()->int:
	var count:=0
	for pair:Dictionary in pairs:
		var original:=pair.original as MeshInstance3D
		var child:=pair.child as MeshInstance3D
		if original.get_skin_reference()!=null and original.get_skin_reference()==child.get_skin_reference():count+=1
	return count

func detach()->void:
	for pair:Dictionary in pairs:
		var child:=pair.child as MeshInstance3D
		if is_instance_valid(child):child.get_parent().remove_child(child);child.queue_free()
	pairs.clear()
