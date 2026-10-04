extends Node3D
## Render the three spatial variants on the original body and clothing rigs.
var source:String="running"
var label:String="v3"
var camera:Camera3D
var entries:Array[Dictionary]=[]
var checks:int=0
var failures:Array[String]=[]

func _ready()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--loop-source="):source=arg.trim_prefix("--loop-source=")
		if arg.begins_with("--loop-visual-label="):label=arg.trim_prefix("--loop-visual-label=")
	get_tree().create_timer(45.0).timeout.connect(func():push_error("MIXAMO_LOOP_VISUAL watchdog");get_tree().quit(1))
	_run.call_deferred()

func _check(label:String,passed:bool)->bool:
	checks+=1
	if not passed:failures.append(label);push_error("MIXAMO_LOOP_VISUAL "+label)
	return passed

func _run()->void:
	if not _check("windowed GPU renderer",DisplayServer.get_name()!="headless"):_finish();return
	if not _check("known isolated source",source in ["running","left_strafe","right_strafe"]):_finish();return
	if not _check("capture label valid filename",label.is_valid_filename()):_finish();return
	get_viewport().size=Vector2i(1280,720)
	_room()
	var avatar_script:Script=load("res://scripts/characters/ink_avatar.gd") as Script
	var sampler_script:Script=load("res://scripts/animation/experiments/mixamo_loop_prototype.gd") as Script
	var modes:Array[String]=["source9_baseline","fixed8_uncorrected","fixed8_endpoint_reprojected"]
	for index:int in modes.size():
		var avatar:Node3D=avatar_script.new()
		avatar.position.x=(float(index)-1.0)*2.5
		avatar.rotation_degrees.y=-15.0
		avatar.set("force_lod",0)
		add_child(avatar)
		avatar.set("presentation_interpolation",false)
		avatar.set_process(false)
		avatar.call("configure",Color("ff8a14"),"shooter",{"hair":2,"outfit":4,"eyes":2,"skin":3,"hat":0,"brows":1})
		avatar.call("configure_lighting",{"hemiSky":"#bddcf4","hemiGround":"#f6d0a1","hemiIntensity":2.1,"hemiGroundK":.5})
		var prototype:RefCounted=sampler_script.new()
		if not _check("actual rig configured",bool(prototype.call("configure",avatar.get("_skeleton")))):_finish();return
		var id:String="mixamo_loop_"+source+"_"+modes[index]+"_leg_reference_retime6"
		if not _check("retimed variant exists",(prototype.get("clips") as Dictionary).has(id)):_finish();return
		var rig:Skeleton3D=avatar.get("_skeleton")
		# In this pose laboratory, disable body shadows for both render references.
		# Later hiding only Skin/Cloth/Eyes must change direct torso/foot pixels,
		# not merely a shadow. Weapons and hair remain in the reference image.
		for name:String in ["Skin","Cloth","Eyes"]:
			var body_model:MeshInstance3D=(avatar.get("_body") as Node).find_child(name,true,false) as MeshInstance3D
			if body_model!=null:body_model.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		avatar.call("animate",1.0/60.0,{"grounded":true,"form":"kid","speed":0.0,"velocity":Vector3.ZERO,"firing":true,"aim_pitch":.15,"is_local":true})
		entries.append({"avatar":avatar,"prototype":prototype,"id":id,"authority":_capture(rig),"mode":modes[index]})
	var folder:String="res://shots/mixamo-loop-"+source+"-gpu-"+label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var captures:Array=[]
	for phase:int in 4:
		var fraction:float=float(phase)/4.0
		for entry:Dictionary in entries:
			var avatar:Node3D=entry.avatar
			var rig:Skeleton3D=avatar.get("_skeleton")
			_restore(rig,entry.authority)
			var prototype:RefCounted=entry.prototype
			var clip:Dictionary=(prototype.get("clips") as Dictionary)[entry.id]
			var sample:Dictionary=prototype.call("apply",String(entry.id),float(clip.duration)*fraction,true)
			_check("actual resource pose sampled",not sample.is_empty())
			prototype.call("copy_modules",avatar,bool(clip.writes_hips))
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var picture:Image=get_viewport().get_texture().get_image()
		var hidden:Array[Dictionary]=[]
		for entry:Dictionary in entries:
			var body:Node=(entry.avatar as Node).get("_body")
			var meshes:Array=[]
			for name:String in ["Skin","Cloth","Eyes"]:
				var model:MeshInstance3D=body.find_child(name,true,false) as MeshInstance3D
				var valid:bool=model!=null and model.mesh!=null and model.mesh.get_surface_count()>0 and model.skin!=null and model.is_visible_in_tree()
				# Check the normal render BEFORE the reference changes visibility.
				_check("actual body mesh present and visible "+name,valid)
				meshes.append({"name":name,"visible_skinned_mesh":valid,"original_local_visible":model.visible if model!=null else false,"surfaces":model.mesh.get_surface_count() if valid else 0})
				if model!=null:
					hidden.append({"mesh":model,"visible":model.visible})
					model.hide()
			entry.normal_meshes=meshes
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var reference:Image=get_viewport().get_texture().get_image()
		for item:Dictionary in hidden:(item.mesh as MeshInstance3D).visible=bool(item.visible)
		var pixels:Array=[]
		for entry:Dictionary in entries:
			var avatar:Node3D=entry.avatar
			_check("kid actually visible",(avatar.get("_kid") as Node3D).is_visible_in_tree())
			var evidence:Dictionary=_pixels(avatar,picture,reference)
			evidence.body_meshes=entry.normal_meshes
			_check("original rig projected in viewport",bool(evidence.projected))
			_check("individual avatar colored pixels",int(evidence.colored_pixels)>=3)
			_check("direct torso body pixels",int(evidence.torso_changed_pixels)>=1)
			_check("direct left foot body pixels",int(evidence.foot_changed_pixels[0])>=1)
			_check("direct right foot body pixels",int(evidence.foot_changed_pixels[1])>=1)
			pixels.append(evidence)
		var path:String=folder+"/pose-%03d.png"%roundi(fraction*100.0)
		_check("image saved",picture.save_png(path)==OK)
		captures.append({"path":path,"phase":fraction,"avatars":pixels,"kind":"isolated sampled pose, no controller/MM loop selection"})
	var report:Dictionary={"checks":checks,"failures":failures,"captures":captures,"source":source,"resource_time_mode":"leg_reference_retime6","physics_movement_test":false,"motion_matching_new_library":false,"production_accepted":false}
	var file:FileAccess=FileAccess.open(folder+"/captures.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	else:_check("report saved",false)
	_finish()

func _room()->void:
	var environment:=WorldEnvironment.new()
	var settings:=Environment.new()
	settings.background_mode=Environment.BG_COLOR
	settings.background_color=Color("293440")
	settings.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color=Color("afbac4")
	settings.ambient_light_energy=.4
	environment.environment=settings
	add_child(environment)
	var light:=DirectionalLight3D.new()
	light.rotation_degrees=Vector3(-48,-35,0)
	light.light_energy=3.5/PI
	light.light_color=Color("ffe4c6")
	light.shadow_enabled=true
	add_child(light)
	var mesh:=MeshInstance3D.new()
	var plane:=PlaneMesh.new()
	plane.size=Vector2(100,100)
	mesh.mesh=plane
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("647581")
	material.roughness=.95
	mesh.material_override=material
	add_child(mesh)
	camera=Camera3D.new()
	camera.current=true
	camera.fov=43.0
	add_child(camera)
	camera.look_at_from_position(Vector3(0,2.8,9.5),Vector3(0,.75,0))
	var canvas:=CanvasLayer.new()
	add_child(canvas)
	var caption:=Label.new()
	caption.position=Vector2(20,14)
	caption.add_theme_font_size_override("font_size",20)
	caption.text="Mixamo loop candidate: "+source+" / retimed to leg-reference 6 m/s\nLEFT pelvis + legs / CENTER eight legs raw / RIGHT eight legs endpoint reprojection\nIsolated pose laboratory. Quality failures remain; no gameplay or MM-loop acceptance."
	canvas.add_child(caption)

func _pixels(avatar:Node3D,picture:Image,reference:Image)->Dictionary:
	var rig:Skeleton3D=avatar.get("_skeleton")
	var size:Vector2=get_viewport().get_visible_rect().size
	var low:Vector2=size
	var high:=Vector2.ZERO
	var projected:bool=true
	for name:String in ["head","hips","footL","footR"]:
		var point:Vector3=rig.global_transform*rig.get_bone_global_pose(rig.find_bone(name)).origin
		var screen:Vector2=camera.unproject_position(point)
		projected=projected and not camera.is_position_behind(point) and Rect2(Vector2.ZERO,size).has_point(screen)
		low=Vector2(minf(low.x,screen.x),minf(low.y,screen.y))
		high=Vector2(maxf(high.x,screen.x),maxf(high.y,screen.y))
	var count:int=0
	for row:int in 32:
		for column:int in 24:
			var screen:Vector2=Vector2(lerpf(low.x-26,high.x+26,(float(column)+.5)/24.0),lerpf(low.y-30,high.y+12,(float(row)+.5)/32.0))
			var color:Color=picture.get_pixel(clampi(roundi(screen.x*float(picture.get_width())/size.x),0,picture.get_width()-1),clampi(roundi(screen.y*float(picture.get_height())/size.y),0,picture.get_height()-1))
			if color.r>color.g*1.1 and color.r>color.b*1.2 and color.r-color.b>.08:count+=1
	var chest:Vector3=rig.global_transform*rig.get_bone_global_pose(rig.find_bone("chest")).origin
	var torso:Vector2=camera.unproject_position(chest)
	torso*=Vector2(float(picture.get_width())/size.x,float(picture.get_height())/size.y)
	var torso_pixels:int=_changed_region(picture,reference,torso,4)
	var shoes:Array[int]=[]
	for name:String in ["footL","footR"]:
		var foot:Transform3D=rig.global_transform*rig.get_bone_global_pose(rig.find_bone(name))
		var sole:Vector2=camera.unproject_position(foot*Vector3(0,-.04,.015))
		sole*=Vector2(float(picture.get_width())/size.x,float(picture.get_height())/size.y)
		shoes.append(_changed_region(picture,reference,sole,6))
	return {"projected":projected,"colored_pixels":count,"minimum":low,"maximum":high,"torso_changed_pixels":torso_pixels,"foot_changed_pixels":shoes,"body_reference_method":"hide only Skin/Cloth/Eyes, body shadow disabled in both images, weapons/hair retained","viewport_rect_size":size,"image_size":Vector2i(picture.get_width(),picture.get_height())}

func _changed_region(picture:Image,reference:Image,center:Vector2,radius:int)->int:
	var count:int=0
	for row:int in radius*2+1:
		for column:int in radius*2+1:
			var x:int=clampi(roundi(center.x)+column-radius,0,picture.get_width()-1)
			var y:int=clampi(roundi(center.y)+row-radius,0,picture.get_height()-1)
			var a:Color=picture.get_pixel(x,y)
			var b:Color=reference.get_pixel(x,y)
			if Vector3(a.r-b.r,a.g-b.g,a.b-b.b).length()>.03:count+=1
	return count

func _capture(skeleton:Skeleton3D)->Array[Dictionary]:
	var packets:Array[Dictionary]=[]
	for bone:int in skeleton.get_bone_count():packets.append({"position":skeleton.get_bone_pose_position(bone),"rotation":skeleton.get_bone_pose_rotation(bone),"scale":skeleton.get_bone_pose_scale(bone)})
	return packets

func _restore(skeleton:Skeleton3D,packets:Array)->void:
	for bone:int in skeleton.get_bone_count():
		skeleton.set_bone_pose_position(bone,packets[bone].position)
		skeleton.set_bone_pose_rotation(bone,packets[bone].rotation)
		skeleton.set_bone_pose_scale(bone,packets[bone].scale)

func _finish()->void:
	for entry:Dictionary in entries:(entry.prototype as RefCounted).call("dispose")
	print("MIXAMO_LOOP_VISUAL ",checks," checks; ",failures.size()," failures; ",source)
	get_tree().quit(0 if failures.is_empty() else 1)
