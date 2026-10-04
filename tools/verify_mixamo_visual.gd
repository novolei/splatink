extends SceneTree
const Preview = preload("res://scenes/experiments/mixamo_turn_preview.tscn")
var failures:int=0
func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():push_error("MIXAMO_VISUAL watchdog");quit(1))
	call_deferred("_run")
func _run() -> void:
	root.size=Vector2i(1600,1000)
	var preview:Node3D=Preview.instantiate() as Node3D
	root.add_child(preview)
	preview.set("playing",false)
	for frame:int in 5:await process_frame
	for fraction:float in [0.0,.25,.5,.75,1.0]:
		preview.call("seek_fraction",fraction)
		await process_frame
		await RenderingServer.frame_post_draw
		var image:Image=root.get_texture().get_image()
		var path:String="res://shots/mixamo-turn-%03d.png"%roundi(fraction*100.0)
		if image==null or image.save_png(path)!=OK:
			failures+=1
			push_error("MIXAMO_VISUAL write "+path)
	preview.queue_free()
	await process_frame
	print("MIXAMO_VISUAL 5 captures; failures=",failures)
	quit(1 if failures else 0)
