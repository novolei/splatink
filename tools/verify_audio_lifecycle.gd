extends SceneTree
## Real Game reproduction. Default exit relies only on InkAudio._exit_tree().
## No save data, ENet socket, private-field drain, or global quit hook is used.
const Game = preload("res://scripts/ink_game.gd")
var game: InkGame
var exit_mode: String = "normal"
var exit_delay: float = 1.2
var cycles: int = 3
var output: String = ""
var checks: int = 0
var failures: Array[String] = []
var snapshots: Array[Dictionary] = []
var watched: Array[Dictionary] = []

class QuietBots:
	extends InkBots
	func command_for(actor, _dt: float) -> Dictionary:
		return {"move":Vector3.ZERO,"aim_dir":Vector3(sin(actor.aim_yaw),0,cos(actor.aim_yaw)),"fire":false,"sub":false,"swim":false,"jump":false,"special":false}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--exit-mode="):exit_mode = argument.trim_prefix("--exit-mode=")
		if argument.begins_with("--exit-delay="):exit_delay = clampf(float(argument.trim_prefix("--exit-delay=")),0,5)
		if argument.begins_with("--cycles="):cycles = clampi(int(argument.trim_prefix("--cycles=")),1,12)
		if argument.begins_with("--output="):output = argument.trim_prefix("--output=")
	_run.call_deferred()

func _check(condition: bool, message: String) -> void:
	checks += 1
	if not condition:
		failures.append(message)
		push_error(message)

func _quiet() -> void:
	var quiet := QuietBots.new()
	quiet.configure(game,"normal")
	game.bots = quiet

func _snapshot(audio: InkAudio, label: String) -> Dictionary:
	var state: Dictionary = audio.debug_lifecycle_state()
	state["label"] = label
	state["objects"] = Performance.get_monitor(Performance.OBJECT_COUNT)
	state["resources"] = Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)
	state["orphan_nodes"] = Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)
	snapshots.append(state)
	return state

func _watch(resource: RefCounted, label: String, must_release: bool = false) -> void:
	if resource == null:return
	watched.append({"label":label,"id":resource.get_instance_id(),"class":resource.get_class(),"references_before":resource.get_reference_count(),"ref":weakref(resource),"must_release":must_release})

func _music_player(audio: InkAudio) -> AudioStreamPlayer:
	for child: Node in audio.get_children():
		if child is AudioStreamPlayer and child.bus == "Music":return child
	return null

func _watch_music(audio: InkAudio, label: String, must_release: bool = false) -> void:
	var player: AudioStreamPlayer = _music_player(audio)
	if player != null:_watch(player.stream,label,must_release)

func _watch_loop(audio: InkAudio, key: String, label: String) -> void:
	var loops: Dictionary = audio.get("_loops")
	var player: AudioStreamPlayer3D = loops.get(key) as AudioStreamPlayer3D
	_check(player != null,"Fixture loop starts from the existing pool")
	if player != null:_watch(player.stream,label,true)

func _loop_playback_started(audio: InkAudio, key: String) -> bool:
	var loops: Dictionary = audio.get("_loops")
	var player: AudioStreamPlayer3D = loops.get(key) as AudioStreamPlayer3D
	if player == null or not player.has_stream_playback():return false
	return player.get_stream_playback().is_playing()

func _watch_owned(audio: InkAudio) -> void:
	for child: Node in audio.get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			_watch(child.get("stream") as AudioStream,"exit stream")
	var streams: Dictionary = audio.get("_streams")
	for key: String in streams:_watch(streams[key] as AudioStream,"cache "+key)
	_watch(audio.get("_music_tween") as Tween,"exit tween")
	_watch(audio.boss_audio,"exit boss director")

func _resource_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for entry: Dictionary in watched:
		var resource: RefCounted = entry.ref.get_ref() as RefCounted
		rows.append({"label":entry.label,"id":entry.id,"class":entry.get("class"),"references_before":entry.references_before,"alive":resource!=null,"references_now":resource.get_reference_count() if resource!=null else 0,"must_release":entry.must_release})
	return rows

func _check_transient_release() -> void:
	for entry: Dictionary in watched:
		if bool(entry.must_release):_check(entry.ref.get_ref()==null,"Transient stream released: "+str(entry.label))

func _audio_exited(audio_ref: WeakRef) -> void:
	var audio: InkAudio = audio_ref.get_ref() as InkAudio
	if audio == null:
		push_error("Audio exit observer ran after its node was freed")
		return
	var state: Dictionary = audio.debug_lifecycle_state()
	print("AUDIO_LIFECYCLE_EXIT ",JSON.stringify(state))

func _exercise_audio() -> void:
	var audio: InkAudio = game.audio
	audio.set_volumes({"master":.8,"music":.61,"sfx":.73})
	for cycle: int in cycles:
		for track: String in ["title","battle","menu"]:
			_watch_music(audio,"replaced music %d %s"%[cycle,track],true)
			audio.play_music(track,.05)
			await create_timer(.08).timeout
			audio.play("ready")
			audio.play("jump",{"pos":Vector3.ZERO})
			audio.play("jump",{"pos":Vector3.ZERO,"delay":.5})
			var key: String = "lifecycle_%d_%s"%[cycle,track]
			audio.loop(key,"swim",{"pos":Vector3.ZERO})
			_watch_loop(audio,key,"paused loop "+key)
			# physics_frame is emitted before node processing; two signals let the
			# 3D player submit its queued playback before the pause cancels it.
			await physics_frame
			await physics_frame
			_check(_loop_playback_started(audio,key),"Paused loop reaches actual playback before stopping")
			audio.set_paused(true)
			var paused: Dictionary = audio.debug_lifecycle_state()
			_check(int(paused.active_loops)==0 and int(paused.pending)==0,"Pause clears loops and delayed sounds")
			audio.set_paused(false)
			audio.loop(key,"swim",{"pos":Vector3.ZERO})
			_watch_loop(audio,key,"background loop "+key)
			await physics_frame
			await physics_frame
			_check(_loop_playback_started(audio,key),"Background loop reaches actual playback before stopping")
			audio.set_backgrounded(true)
			_check(bool(audio.debug_lifecycle_state().music_paused),"Background suspends music")
			audio.set_backgrounded(false)
			_check(not bool(audio.debug_lifecycle_state().music_paused),"Foreground resumes music")
			var state: Dictionary = _snapshot(audio,"cycle %d %s"%[cycle,track])
			_check(int(state.players)==81 and int(state.pooled_handles)==81,"Playback changes reuse all 81 pooled players")
		audio.stop_music(.05)
		await create_timer(.08).timeout
	_check(is_equal_approx(audio.music,.61) and is_equal_approx(audio.sfx,.73),"Lifecycle exercise preserves configured volumes")
	var music_bus: int = AudioServer.get_bus_index("Music")
	_check(music_bus>=0 and absf(AudioServer.get_bus_volume_db(music_bus)-linear_to_db(pow(.61,1.5)))<.01,"Menu Music bus retains its configured gain")

func _exercise_same_frame_cancel() -> void:
	var audio: InkAudio = game.audio
	var key: String = "lifecycle_same_frame_cancel"
	audio.loop(key,"swim",{"pos":Vector3.ZERO})
	var loops: Dictionary = audio.get("_loops")
	var player: AudioStreamPlayer3D = loops.get(key) as AudioStreamPlayer3D
	_check(player != null,"Same-frame cancellation starts from the existing pool")
	if player == null:return
	_watch(player.stream,"same-frame cancelled stream",true)
	_watch(player.get_stream_playback(),"same-frame cancelled playback",true)
	audio.stop_loop(key)
	_check(player.stream==null and not player.playing,"Same-frame cancellation stops and detaches the public stream")
	# Godot 4.7.1 keeps the cancelled setplayback until player reuse/destruction.
	# The existing strict WeakRef release check runs after owner destruction below.

func _run() -> void:
	_check(exit_mode in ["normal","queue-free","pool"],"Exit mode is normal, queue-free, or pool")
	root.size = Vector2i(1280,720)
	seed(0x494e4b)
	game = Game.new()
	game._args = {"nonpersistent":true,"benchmark-background":true,"page":"online"}
	root.add_child(game)
	game.apply_settings({"quality":"low"})
	game.audio.tree_exited.connect(_audio_exited.bind(weakref(game.audio)),CONNECT_ONE_SHOT)
	_quiet()
	var startup: Dictionary = _snapshot(game.audio,"startup")
	_check(int(startup.players)==81,"Real Game initializes the complete audio pool")
	await create_timer(.8).timeout
	game.start_match({"map":"tidewater","mode":"turf","bots":true,"duration":90,"time_of_day":"day","weapon":"shooter","style":{"hair":2,"skin":3,"outfit":4,"eyes":2,"hat":0,"brows":1}})
	_quiet()
	await create_timer(8.0).timeout
	var playing_seen: bool = game.state == "playing"
	_check(playing_seen,"Real Game reaches playing")
	await _exercise_audio()
	_watch_music(game.audio,"music before menu",true)
	game.quit_to_menu()
	_quiet()
	await create_timer(exit_delay).timeout
	var menu_seen: bool = game.state == "menu"
	_check(menu_seen and game.ui.page=="main","Real Game returns to the ordinary menu")
	var menu: Dictionary = _snapshot(game.audio,"menu before exit")
	_check(str(menu.current_track)=="menu" and bool(menu.music_stream),"Menu music remains attached before exit")
	if exit_delay>=1.05:_check(absf(float(menu.music_volume_db))<.01,"Menu music fade still reaches full player gain")
	_check_transient_release()
	_watch_owned(game.audio)
	var audio_ref: WeakRef = weakref(game.audio)
	if exit_mode in ["queue-free","pool"]:_exercise_same_frame_cancel()
	if exit_mode == "pool":
		game.set_process(false)
		game.set_physics_process(false)
		var audio: InkAudio = game.audio
		game.remove_child(audio)
		var released: Dictionary = _snapshot(audio,"pool after tree exit")
		_check(bool(released.shutdown) and int(released.attached_streams)==0 and int(released.playing)==0,"Tree exit synchronously stops and detaches every stream")
		_check(int(released.pooled_handles)==0 and int(released.cached_streams)==0 and int(released.pending)==0 and int(released.active_loops)==0,"Tree exit drops audio ownership handles and caches")
		_check(not bool(released.tween_owned) and not bool(released.boss_owned),"Tree exit releases the Tween and boss director")
		audio.shutdown()
		audio.shutdown()
		audio.play_music("title")
		audio.play("ready")
		audio.loop("late","swim")
		_check(audio.debug_lifecycle_state()==_without_monitors(released),"Repeated shutdown and late playback cannot rebuild the terminal pool")
		game.audio = null
		audio.free()
	if exit_mode in ["queue-free","pool"]:
		game.queue_free()
		game = null
		await process_frame
		await process_frame
		_check(audio_ref.get_ref()==null,"Scene ownership frees the audio node")
		_check_transient_release()
		for entry: Dictionary in watched:
			if entry.label in ["exit tween","exit boss director"]:_check(entry.ref.get_ref()==null,"Scene exit releases "+str(entry.label))
	var report: Dictionary = {"diagnostic_only":true,"real_enet":false,"exit_mode":exit_mode,"exit_delay":exit_delay,"cycles":cycles,"playing_seen":playing_seen,"menu_seen":menu_seen,"native_mm_requested":OS.get_cmdline_user_args().has("--native-locomotion-mm"),"native_extension_present":ClassDB.class_exists("MMAnimationLibrary"),"checks":checks,"failures":failures,"snapshots":snapshots,"resource_references":_resource_rows()}
	if not output.is_empty():
		var path: String = ProjectSettings.globalize_path(output)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var file := FileAccess.open(path,FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(report,"\t"))
			file.close()
		else:_check(false,"Lifecycle JSON output opens successfully")
	print("AUDIO_LIFECYCLE ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _without_monitors(state: Dictionary) -> Dictionary:
	var result: Dictionary = state.duplicate()
	for key: String in ["label","objects","resources","orphan_nodes"]:result.erase(key)
	return result
