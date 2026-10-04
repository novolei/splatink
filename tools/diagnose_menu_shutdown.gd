extends SceneTree
## Isolated development reproduction for the Mac menu-return shutdown warning.
## No player data is loaded/saved. No ENet socket or external service is opened.
const Game=preload("res://scripts/ink_game.gd")
var game:InkGame
var output:String=""
var exit_delay:float=1.2
var drain_audio:bool=false
var release_game:bool=false

class QuietBots:
	extends InkBots
	func command_for(actor,_dt:float)->Dictionary:
		return {"move":Vector3.ZERO,"aim_dir":Vector3(sin(actor.aim_yaw),0,cos(actor.aim_yaw)),"fire":false,"sub":false,"swim":false,"jump":false,"special":false}

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
		if argument.begins_with("--exit-delay="):exit_delay=clampf(float(argument.trim_prefix("--exit-delay=")),0,5)
		if argument=="--drain-audio":drain_audio=true
		if argument=="--release-game":release_game=true
	_run.call_deferred()

func _run()->void:
	root.size=Vector2i(1280,720)
	seed(0x494e4b)
	game=Game.new()
	game._args={"nonpersistent":true,"benchmark-background":true,"page":"online"}
	root.add_child(game)
	game.apply_settings({"quality":"low"})
	_quiet()
	await create_timer(.8).timeout
	game.start_match({"map":"tidewater","mode":"turf","bots":true,"duration":90,"time_of_day":"day","weapon":"shooter","style":{"hair":2,"skin":3,"outfit":4,"eyes":2,"hat":0,"brows":1}})
	_quiet()
	await create_timer(8.0).timeout
	var playing:bool=game.state=="playing"
	game.quit_to_menu()
	_quiet()
	await create_timer(exit_delay).timeout
	var report:Dictionary={"diagnostic_only":true,"real_enet":false,"playing_seen":playing,"menu_state":game.state,"ui_page":game.ui.page,"exit_delay":exit_delay,"news_open":is_instance_valid(game.ui._news),"wipe_running":game.ui._wipe.running,"nodes":Performance.get_monitor(Performance.OBJECT_NODE_COUNT),"objects":Performance.get_monitor(Performance.OBJECT_COUNT),"resources":Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT),"orphan_nodes":Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT),"native_mm_requested":OS.get_cmdline_user_args().has("--native-locomotion-mm"),"native_extension_present":ClassDB.class_exists("MMAnimationLibrary")}
	var menu_seen:bool=game.state=="menu"
	report["audio_drain_requested"]=drain_audio
	report["game_release_requested"]=release_game
	report["headless_gpu_instance_present"]=game.stage!=null and game.stage._gpu!=null
	if drain_audio:
		var audio:InkAudio=game.audio
		audio.set_process(false)
		audio.clear_gameplay()
		if audio._music_tween!=null:audio._music_tween.kill()
		audio._music_tween=null
		for child:Node in audio.get_children():
			if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
				child.call("stop")
				child.set("stream",null)
		audio._streams.clear()
		audio=null
		await process_frame
		await process_frame
	if release_game:
		game.queue_free()
		game=null
		await process_frame
		await process_frame
	report["objects_after_isolation"]=Performance.get_monitor(Performance.OBJECT_COUNT)
	report["orphan_nodes_after_isolation"]=Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	if not output.is_empty():
		var path:String=ProjectSettings.globalize_path(output)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file:=FileAccess.open(path,FileAccess.WRITE)
		if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("MENU_SHUTDOWN_DIAGNOSTIC ",JSON.stringify(report))
	quit(0 if playing and menu_seen else 1)

func _quiet()->void:
	var quiet:=QuietBots.new()
	quiet.configure(game,"normal")
	game.bots=quiet
