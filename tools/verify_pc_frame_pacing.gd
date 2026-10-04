extends SceneTree
## Real eight-actor match, production bot commands and GPU rendering.
## Samples contain no screenshots, readbacks or injected animation poses.
var game:Node
var output:String="res://shots/pc-frame-pacing.json"
var duration:float=16.0
var quality:String="high"
var fps:int=144
var live:bool=false
var finishing:bool=false
var rows:Array[Dictionary]=[]
var last_wall:int=0
var last_tick:int=0
var start_clock:float=0.0
var warmed:bool=false
var checks:int=0
var failures:Array[String]=[]

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--pacing-output="):output=argument.trim_prefix("--pacing-output=")
		if argument.begins_with("--pacing-seconds="):duration=maxf(8.0,float(argument.trim_prefix("--pacing-seconds=")))
		if argument.begins_with("--pacing-quality="):quality=argument.trim_prefix("--pacing-quality=")
		if argument.begins_with("--pacing-fps="):fps=clampi(int(argument.trim_prefix("--pacing-fps=")),30,240)
	_run.call_deferred()

func _check(label:String,value:bool)->void:
	checks+=1
	if not value:failures.append(label);push_error("PC_FRAME_PACING "+label)

func _run()->void:
	_check("GPU renderer required",DisplayServer.get_name()!="headless")
	if not failures.is_empty():quit(1);return
	root.size=Vector2i(1280,720)
	seed(37)
	game=load("res://scenes/main.tscn").instantiate()
	game.set("_args",{"nonpersistent":true,"benchmark-background":true,"page":"online","autopilot":true,"profile-render":true,"benchmark-fps":str(fps)})
	root.add_child(game)
	current_scene=game
	game.call("apply_settings",{"quality":quality,"cameraShake":1.0,"aimAssist":0.0,"aimAssistMouse":false})
	game.call("start_match",{"map":"tidewater","mode":"turf","duration":180,"time_of_day":"day","weapon":"shooter","palette":0,"style":{"hair":2,"skin":3,"outfit":4,"eyes":2,"hat":0,"brows":1}})
	await create_timer(4.8).timeout
	_check("real playing state",game.get("state")=="playing")
	_check("eight production actors",(game.get("actors") as Array).size()==8)
	_check("autopilot uses production bot commands",bool(game.get("_autopilot")))
	_check("default presentation remains off",game.get("local_player").get("avatar").get("presentation_mode")=="off")
	if not failures.is_empty():quit(1);return
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps=fps
	start_clock=float(game.get("match_clock"))
	last_wall=Time.get_ticks_usec();last_tick=Engine.get_physics_frames()
	live=true
	RenderingServer.frame_post_draw.connect(_sample)

func _sample()->void:
	if not live or finishing:return
	var wall:int=Time.get_ticks_usec()
	var tick:int=Engine.get_physics_frames()
	var elapsed:float=float(game.get("match_clock"))-start_clock
	rows.append({"t":elapsed,"wall_interval_ms":float(wall-last_wall)/1000.0,"physics_ticks":tick-last_tick,"phase":"warm" if elapsed>=4.0 else "initial",
		"process_cpu_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_cpu_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,
		"main_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(root.get_viewport_rid()),
		"main_render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(root.get_viewport_rid()),
		"render_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})
	last_wall=wall;last_tick=tick
	if elapsed>=4.0 and not warmed:
		warmed=true
		(game.get("_render_samples") as Dictionary).clear()
		(game.get("_frame_samples") as Array).clear()
	if elapsed>=duration:
		finishing=true;live=false
		_finish.call_deferred()

func _stats(values:Array)->Dictionary:
	if values.is_empty():return {"count":0,"status":"uncovered"}
	var sorted:Array=values.duplicate();sorted.sort()
	return {"count":values.size(),"median":sorted[floori(sorted.size()*.5)],"p95":sorted[mini(sorted.size()-1,floori(sorted.size()*.95))],"p99":sorted[mini(sorted.size()-1,floori(sorted.size()*.99))],"max":sorted[-1]}

func _finish()->void:
	RenderingServer.frame_post_draw.disconnect(_sample)
	var warm_rows:Array=rows.filter(func(row):return row.phase=="warm")
	_check("warm moving match sampled",warm_rows.size()>0 and game.get("state")=="playing")
	_check("match continues during unattended sampling",game.get("_backgrounded")==false)
	var metrics:Dictionary={}
	for key:String in ["wall_interval_ms","physics_ticks","process_cpu_ms","physics_cpu_ms","main_gpu_ms","main_render_cpu_ms","render_setup_cpu_ms","draw_calls"]:
		metrics[key]=_stats(warm_rows.map(func(row):return row[key]))
	var game_profile:Dictionary={}
	for key:String in game.get("_render_samples"):
		game_profile[key]=_stats(game.get("_render_samples")[key])
	var report:Dictionary={"checks":checks,"failures":failures,"scene":game.scene_file_path,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),
		"quality":quality,"window":root.size,"render_scale":root.scaling_3d_scale,"fps_limit":fps,"vsync":"disabled for controlled comparison","physics_hz":Engine.physics_ticks_per_second,
		"matcher_script":game.get("local_player").get("avatar").get("_motion").get_script().resource_path,"user_args":OS.get_cmdline_user_args(),
		"seed":37,"actors":game.get("actors").size(),"bot_policy":"Eight production bot-command actors including local autopilot","samples":rows,"warm_metrics":metrics,"game_profile":game_profile,
		"playing_seconds":float(game.get("options").duration)-float(game.get("time_left")),"focus_paused":game.get("_backgrounded"),"accepted_for_production":false,
		"limitations":["CPU/GPU timer association is not an actual display presentation timestamp.","Auxiliary viewport GPU work may be excluded from main viewport timer.","No screenshots/readback occur during sampling; report serialization occurs after sampling.","Fixed quality/fps/vsync conditions do not reproduce every saved user setting or level."]}
	var file:=FileAccess.open(output,FileAccess.WRITE)
	_check("report writable",file!=null)
	report.checks=checks;report.failures=failures
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("PC_FRAME_PACING ",JSON.stringify({"checks":checks,"failures":failures,"warm":metrics,"output":output}))
	quit(0 if failures.is_empty() else 1)
