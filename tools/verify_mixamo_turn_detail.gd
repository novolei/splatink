extends SceneTree
## Three-mode close view and original-time 60Hz pose sequence. Root runs the GPU.
## Example -- --detail-turn=left_turn_90 --detail-start-frame=20 --detail-end-frame=38
const Preview=preload("res://scenes/experiments/mixamo_turn_preview.tscn")
var failures:int=0

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():push_error("MIXAMO_DETAIL watchdog");quit(1))
	call_deferred("_run")

func _argument(key:String,fallback:String) -> String:
	for arg:String in OS.get_cmdline_args()+OS.get_cmdline_user_args():
		if arg.begins_with(key+"="):return arg.trim_prefix(key+"=")
	return fallback

func _run() -> void:
	var turn:String=_argument("--detail-turn","left_turn_90")
	if not turn in ["left_turn","right_turn","left_turn_90","right_turn_90"]:
		push_error("MIXAMO_DETAIL unknown source turn");quit(1);return
	var first:int=_argument("--detail-start-frame","20").to_int()
	var last:int=_argument("--detail-end-frame","38").to_int()
	root.size=Vector2i(1440,900)
	var preview:Node3D=Preview.instantiate() as Node3D
	root.add_child(preview)
	preview.set("playing",false)
	preview.set_physics_process(false)
	var kept:Array[Dictionary]=[]
	var all_entries:Array=preview.get("entries")
	for entry:Dictionary in all_entries:
		var anchor:Node3D=entry.anchor
		if String((entry.clip as Dictionary).id)!="mixamo_"+turn:
			anchor.visible=false
			continue
		anchor.position=Vector3((float(kept.size())-1.0)*2.05,0,0)
		for child:Node in anchor.get_children():
			if child is Label3D:
				var label:Label3D=child as Label3D
				label.position=Vector3(0,2.22,0)
				label.font_size=22
				label.pixel_size=.0045
				label.text=String(entry.mode)+"\n"+turn.replace("_"," ")+" / original %.3fs"%float((entry.clip as Dictionary).duration)
		kept.append(entry)
	if kept.size()!=3:push_error("MIXAMO_DETAIL missing modes");quit(1);return
	var camera:Camera3D=preview.get("camera")
	camera.look_at_from_position(Vector3(0,3.0,6.65),Vector3(0,1.08,0),Vector3.UP)
	camera.fov=42.0
	for i:int in 3:await process_frame
	var duration:float=float((kept[0].clip as Dictionary).duration)
	var directory:String="res://shots/mixamo-detail-"+turn
	DirAccess.make_dir_recursive_absolute(directory)
	var maximum:int=ceili(duration*60.0)
	first=clampi(first,0,maximum)
	last=clampi(last,first,maximum)
	var frames:Array[Dictionary]=[]
	# Source holds receive a continuous clock from original frame zero. Skipping
	# capture frames does not time-warp the authored lower animation or source hold.
	for frame:int in last+1:
		var time:float=minf(float(frame)/60.0,duration)
		for entry:Dictionary in kept:preview.call("_sample",entry,time)
		if frame<first:continue
		await process_frame
		await RenderingServer.frame_post_draw
		var image:Image=root.get_texture().get_image()
		var path:String=directory+"/frame-%04d.png"%frame
		if image==null or image.save_png(path)!=OK:
			failures+=1;push_error("MIXAMO_DETAIL write "+path)
		var modes:Array[Dictionary]=[]
		for entry:Dictionary in kept:modes.append((entry.prototype as MixamoTurnPrototype).last_report.duplicate(true))
		frames.append({"original_time_s":time,"frame60hz":frame,"image":path,"modes":modes})
	var report:Dictionary={"clip":turn,"original_duration_s":duration,"original_time_hz":60,"capture_range":[first,last],"fps_time_warp":false,"physics_controller_connected":false,"accepted_for_production":false,"frames":frames,"failures":failures}
	var file:=FileAccess.open(directory+"/sequence.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	preview.queue_free()
	await process_frame
	print("MIXAMO_DETAIL ",JSON.stringify({"clip":turn,"frames":last-first+1,"failures":failures,"original_duration":duration,"directory":directory}))
	quit(1 if failures else 0)
