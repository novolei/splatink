extends SceneTree
## Root alone runs GPU captures. A sampled-pose preview, not an input recording.
const Preview=preload("res://scenes/experiments/motorica_locomotion_preview.tscn")
var failures:int=0
var checks:int=0
var capture_label:String="corrected"
func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():push_error("MOTORICA_VISUAL watchdog");quit(1))
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--motorica-capture-label="):capture_label=arg.trim_prefix("--motorica-capture-label=")
	call_deferred("_run")

func _check(label:String,passed:bool,detail:Variant=null) -> bool:
	checks+=1
	if not passed:
		failures+=1
		push_error("MOTORICA_VISUAL "+label+" "+str(detail))
	return passed

func _run() -> void:
	if not _check("capture label is a filename",not capture_label.is_empty() and capture_label.is_valid_filename()):quit(1);return
	var scene:Node3D=Preview.instantiate()
	root.add_child(scene)
	await process_frame
	scene.playing=false
	if not _check("both variants configured",scene.entries.size()==2):quit(1);return
	var folder:String="res://shots/motorica-"+String(scene.clip_id).trim_prefix("motorica_")+"-"+(String(scene.window_id) if not String(scene.window_id).is_empty() else "full")+"-"+capture_label
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(folder))
	var captures:Array=[]
	for index:int in 5:
		var fraction:float=float(index)/4.0
		scene.seek_fraction(fraction)
		if not _check("author metadata and both poses sampled",bool(scene.last_sample_valid)):quit(1);return
		await process_frame
		await RenderingServer.frame_post_draw
		var image:Image=root.get_texture().get_image()
		if not _check("real rendered image",image!=null and image.get_width()>16 and image.get_height()>16):quit(1);return
		var contrast:float=_image_contrast(image)
		_check("frame is not pure background",contrast>.06,contrast)
		var visual_evidence:Array=[]
		for entry:Dictionary in scene.entries:
			var avatar:InkAvatar=entry.avatar
			var prototype:MotoricaLocomotionPrototype=entry.prototype
			_check("actual avatar kid visible",avatar._kid.is_visible_in_tree())
			_check("real lower pose present",not prototype.last_report.is_empty() and is_equal_approx(float(prototype.last_report.time),float(scene.phase)))
			var pixels:Dictionary=_avatar_pixels(avatar,scene.camera,image,String(entry.mode)=="source_path_pelvis9")
			_check("avatar feet/head in front and inside viewport",bool(pixels.projected),pixels)
			_check("avatar team-colored pixels rendered",int(pixels.ink_pixels)>=3,pixels)
			visual_evidence.append(pixels)
		if failures>0:quit(1);return
		var file:String=folder+"/pose-%03d.png"%roundi(fraction*100.0)
		var code:Error=image.save_png(file)
		if code!=OK:push_error("Motorica capture failed: "+file);quit(1);return
		captures.append({"file":file,"source_time":scene.phase,"fraction":fraction,"visual_evidence":visual_evidence,"frame_contrast":contrast,"kind":"independent sampled authored pose; no input/controller integration"})
	var evidence:=FileAccess.open(folder+"/captures.json",FileAccess.WRITE)
	if evidence!=null:evidence.store_string(JSON.stringify({"captures":captures,"start_time":scene.start_time,"end_time":scene.end_time,"checks":checks,"failures":failures,"accepted_for_production":false},"\t"));evidence.close()
	scene.queue_free()
	await process_frame
	print("MOTORICA_VISUAL ",captures.size()," captures; ",checks," checks; ",failures," failures")
	quit(0)

func _image_contrast(image:Image) -> float:
	var low:=Vector3(1,1,1)
	var high:=Vector3.ZERO
	for row:int in 16:
		for column:int in 24:
			var pixel:Color=image.get_pixel(clampi(roundi((float(column)+.5)*float(image.get_width())/24.0),0,image.get_width()-1),clampi(roundi((float(row)+.5)*float(image.get_height())/16.0),0,image.get_height()-1))
			low=Vector3(minf(low.x,pixel.r),minf(low.y,pixel.g),minf(low.z,pixel.b))
			high=Vector3(maxf(high.x,pixel.r),maxf(high.y,pixel.g),maxf(high.z,pixel.b))
	return (high-low).length()

func _avatar_pixels(avatar:InkAvatar,camera:Camera3D,image:Image,orange:bool) -> Dictionary:
	var viewport:Vector2=camera.get_viewport().get_visible_rect().size
	var minimum:Vector2=viewport
	var maximum:=Vector2.ZERO
	var projected:bool=true
	for name:String in ["head","hips","footL","footR"]:
		var index:int=avatar._skeleton.find_bone(name)
		var point:Vector3=avatar._skeleton.global_transform*avatar._skeleton.get_bone_global_pose(index).origin
		var screen:Vector2=camera.unproject_position(point)
		projected=projected and not camera.is_position_behind(point) and Rect2(Vector2.ZERO,viewport).has_point(screen)
		minimum=Vector2(minf(minimum.x,screen.x),minf(minimum.y,screen.y))
		maximum=Vector2(maxf(maximum.x,screen.x),maxf(maximum.y,screen.y))
	minimum-=Vector2(26,30)
	maximum+=Vector2(26,12)
	var ink_pixels:int=0
	for row:int in 32:
		for column:int in 24:
			var screen:Vector2=Vector2(lerpf(minimum.x,maximum.x,(float(column)+.5)/24.0),lerpf(minimum.y,maximum.y,(float(row)+.5)/32.0))
			var x:int=clampi(roundi(screen.x*float(image.get_width())/viewport.x),0,image.get_width()-1)
			var y:int=clampi(roundi(screen.y*float(image.get_height())/viewport.y),0,image.get_height()-1)
			var color:Color=image.get_pixel(x,y)
			var matched:bool=color.r>color.g*1.1 and color.r>color.b*1.2 and color.r-color.b>.08 if orange else color.g>color.r*1.4 and color.g>color.b*1.025 and color.g-color.r>.08
			if matched:ink_pixels+=1
	return {"projected":projected,"ink_pixels":ink_pixels,"roi_min":minimum,"roi_max":maximum,"palette":"orange" if orange else "teal"}
