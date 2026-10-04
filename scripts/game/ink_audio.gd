class_name InkAudio
extends Node

## Voices are pooled. Original browser synthesis is baked to native WAV assets.
const SFX_PATH: String = "res://assets/audio/sfx/"
const MUSIC_PATH: String = "res://assets/audio/music/"
const VOICES: int = 40
const LOOP_VOICES: int = 32
const BossDirector=preload("res://scripts/game/ink_boss_audio.gd")
var boss_audio:InkBossAudio
var _streams: Dictionary = {}
var _voices: Array[AudioStreamPlayer3D] = []
var _ui_voices: Array[AudioStreamPlayer] = []
var _loops: Dictionary = {}
var _loop_last_seen: Dictionary = {}
var _music: AudioStreamPlayer
var _next: int = 0
var _ui_next: int = 0
var current_track: String = ""
var master: float = 0.8
var music: float = 0.6
var sfx: float = 0.85
var _music_metadata: Dictionary = {}
var _music_tween: Tween
var _loop_free: Array[AudioStreamPlayer3D] = []
var _backgrounded: bool = false
var _paused: bool = false
var _duck_level: float = 1.0
var _last_hurt_sound: int = -1000
var _pending: Array[Dictionary] = []
var _shutdown: bool = false

func _ready() -> void:
	_setup()

func _exit_tree() -> void:
	shutdown()

## Terminal, synchronous release of this instance's audio ownership.
## Player nodes remain children so scene-tree destruction owns their lifetime.
func shutdown() -> void:
	if _shutdown:return
	_shutdown = true
	set_process(false)
	_kill_music_tween()
	_pending.clear()
	if boss_audio:
		boss_audio.clear()
		boss_audio.audio = null
		boss_audio = null
	for child: Node in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			child.call("stop")
			child.set("stream", null)
			child.set("stream_paused", false)
	_loops.clear()
	_loop_last_seen.clear()
	_voices.clear()
	_ui_voices.clear()
	_loop_free.clear()
	_music = null
	_streams.clear()
	_music_metadata.clear()
	current_track = ""
	_next = 0
	_ui_next = 0
	_paused = false
	_backgrounded = false
	_duck_level = 1.0

func _kill_music_tween() -> void:
	if _music_tween and _music_tween.is_valid():_music_tween.kill()
	_music_tween = null

## Scalar diagnostics do not retain players, streams, or the director.
func debug_lifecycle_state() -> Dictionary:
	var players: int = 0
	var streams: int = 0
	var playing: int = 0
	for child: Node in get_children():
		if child is AudioStreamPlayer or child is AudioStreamPlayer3D:
			players += 1
			if child.get("stream") != null:streams += 1
			if bool(child.get("playing")):playing += 1
	return {
		"shutdown":_shutdown,
		"players":players,
		"attached_streams":streams,
		"playing":playing,
		"pooled_handles":_voices.size()+_ui_voices.size()+_loop_free.size()+_loops.size()+(1 if _music else 0),
		"cached_streams":_streams.size(),
		"active_loops":_loops.size(),
		"pending":_pending.size(),
		"current_track":current_track,
		"music_stream":_music!=null and _music.stream!=null,
		"music_paused":_music!=null and _music.stream_paused,
		"music_volume_db":_music.volume_db if _music else 0.0,
		"tween_owned":_music_tween!=null,
		"boss_owned":boss_audio!=null,
	}

func _setup() -> void:
	if _shutdown:return
	if _music:
		return
	boss_audio=BossDirector.new()
	boss_audio.configure(self)
	if FileAccess.file_exists(MUSIC_PATH + "manifest.json"):
		var metadata = JSON.parse_string(FileAccess.get_file_as_string(MUSIC_PATH + "manifest.json"))
		if metadata is Dictionary:
			_music_metadata = metadata.get("tracks", metadata)
	for bus in ["Music", "SFX", "UI"]:
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			var index: int = AudioServer.bus_count - 1
			AudioServer.set_bus_name(index, bus)
			AudioServer.set_bus_send(index, "Master")
	for i in range(VOICES):
		var voice := AudioStreamPlayer3D.new()
		voice.bus = "SFX"
		voice.unit_size = 7.0
		voice.max_distance = 75.0
		voice.attenuation_filter_cutoff_hz = 16000.0
		add_child(voice)
		_voices.append(voice)
	for i in range(8):
		var voice := AudioStreamPlayer.new()
		voice.bus = "UI"
		add_child(voice)
		_ui_voices.append(voice)
	for i in range(LOOP_VOICES):
		var voice := AudioStreamPlayer3D.new()
		voice.bus = "SFX"
		voice.max_distance = 60.0
		voice.unit_size = 6.0
		add_child(voice)
		_loop_free.append(voice)
	_music = AudioStreamPlayer.new()
	_music.bus = "Music"
	add_child(_music)
	set_volumes({"master": master, "music": music, "sfx": sfx})

func _stream(name: String, folder: String) -> AudioStream:
	var key: String = folder + name
	if _streams.has(key):
		return _streams[key]
	var path: String = folder + name + ".wav"
	if not ResourceLoader.exists(path):
		var aliases: Dictionary = {"shoot_dualies": "shoot_shooter", "shoot_splatling": "shoot_shooter", "shoot_slosher": "slosh_throw", "actor:jump": "jump", "actor:land": "land", "actor:footstep": "step_dry", "special:slam": "special_slam", "superjump": "super_jump", "superjump:land": "land", "match_intro": "ready", "go": "go_horn", "match_end": "times_up", "boss:intro": "boss_title", "boss:phase": "boss_phase", "boss:defeat": "boss_defeat"}
		path = folder + str(aliases.get(name, name)) + ".wav"
	if not ResourceLoader.exists(path):
		return null
	var stream: AudioStream = load(path)
	_streams[key] = stream
	return stream

func set_volumes(values: Dictionary) -> void:
	master = clampf(float(values.get("master", master)), 0.0, 1.0)
	music = clampf(float(values.get("music", music)), 0.0, 1.0)
	sfx = clampf(float(values.get("sfx", sfx)), 0.0, 1.0)
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.00001, pow(master, 1.5))))
	for bus in ["Music", "SFX", "UI"]:
		var index: int = AudioServer.get_bus_index(bus)
		if index >= 0:
			AudioServer.set_bus_volume_db(index, linear_to_db(maxf(0.00001, pow(music if bus == "Music" else sfx, 1.5) * (_duck_level if bus == "Music" else 1.0))))

func play(name: String, options: Dictionary = {}) -> void:
	if _shutdown:return
	_setup()
	if _backgrounded:return
	if _paused and options.has("pos"):return
	if float(options.get("delay",0.0))>0.0:
		if _pending.size()<128:
			var delayed: Dictionary = options.duplicate()
			var delay: float = float(delayed.delay)
			delayed.erase("delay")
			_pending.append({"sound":name,"options":delayed,"left":delay})
		return
	var stream: AudioStream = _stream(name, SFX_PATH)
	if not stream:
		return
	var volume_db: float = linear_to_db(maxf(0.001, float(options.get("volume", 1.0))))
	var pitch: float = float(options.get("pitch", 1.0)) * randf_range(0.95, 1.05)
	if options.has("pos") and options["pos"] is Vector3:
		var voice: AudioStreamPlayer3D = _voices[_next % _voices.size()]
		_next += 1
		voice.stop()
		voice.stream = stream
		voice.global_position = options["pos"]
		voice.volume_db = volume_db
		voice.pitch_scale = pitch
		voice.play()
	else:
		var voice: AudioStreamPlayer = _ui_voices[_ui_next % _ui_voices.size()]
		_ui_next += 1
		voice.stop()
		voice.stream = stream
		voice.volume_db = volume_db
		voice.pitch_scale = pitch
		voice.play()

func play_music(track: String, fade: float = 1.0) -> void:
	if _shutdown:return
	_setup()
	if current_track == track:
		return
	_kill_music_tween()
	current_track = track
	var stream: AudioStream = _stream(track, MUSIC_PATH)
	if not stream:
		_music.stop()
		return
	var duplicate: AudioStream = stream.duplicate()
	if duplicate is AudioStreamWAV:
		var fallback: Dictionary = {"title": [7.5, 75.0], "menu": [4.571428571428571, 59.42857142857143], "battle": [3.2, 60.8], "battle_final": [1.6, 33.6], "results_win": [0.0, 15.483870967741936], "results_lose": [0.0, 22.857142857142858], "boss": [3.4285714285714284, 58.285714285714285], "boss_2": [1.7142857142857142, 29.142857142857142], "boss_3": [1.7142857142857142, 29.142857142857142]}
		var defaults: Array = fallback.get(track, [0.0, duplicate.get_length()])
		var markers: Dictionary = _music_metadata.get(track, {})
		duplicate.loop_mode = AudioStreamWAV.LOOP_FORWARD
		duplicate.loop_begin = int(round(float(markers.get("loop_start", defaults[0])) * duplicate.mix_rate))
		duplicate.loop_end = int(round(minf(duplicate.get_length(), float(markers.get("loop_end", defaults[1]))) * duplicate.mix_rate))
	_music.stream = duplicate
	_music.volume_db = -35.0 if fade > 0.0 else 0.0
	_music.play()
	_music.stream_paused = _backgrounded
	if fade > 0.0:
		_music_tween = create_tween()
		_music_tween.tween_property(_music, "volume_db", 0.0, fade)

func stop_music(fade:float=.4) -> void:
	if _shutdown:return
	current_track=""
	if not _music:return
	_kill_music_tween()
	if fade<=0:_music.stop();return
	_music_tween=create_tween()
	_music_tween.tween_property(_music,"volume_db",-60.0,fade)
	_music_tween.tween_callback(_music.stop)

func match_finish(boss_mode:bool,boss_dead:bool) -> void:
	if not boss_mode or not boss_dead:play("times_up")
	if not boss_mode:stop_music(.4)
	elif not boss_dead:stop_music(.6)

func loop(key: String, sound: String, options: Dictionary = {}) -> void:
	if _shutdown:return
	_setup()
	if _backgrounded or _paused:return
	_loop_last_seen[key] = Time.get_ticks_msec()
	if not _loops.has(key):
		if _loop_free.is_empty():return
		var stream: AudioStream = _stream(sound, SFX_PATH)
		if not stream:
			return
		var duplicate: AudioStream = stream.duplicate()
		if duplicate is AudioStreamWAV:
			duplicate.loop_mode = AudioStreamWAV.LOOP_FORWARD
			duplicate.loop_end = int(duplicate.get_length() * duplicate.mix_rate)
		var voice: AudioStreamPlayer3D = _loop_free.pop_back()
		voice.stream = duplicate
		_loops[key] = voice
		voice.play()
	var player: AudioStreamPlayer3D = _loops[key]
	player.pitch_scale = float(options.get("pitch", 1.0))
	player.volume_db = linear_to_db(maxf(0.0001, float(options.get("volume", 0.5))))
	if options.get("pos") is Vector3:
		player.global_position = options["pos"]

func stop_loop(key: String) -> void:
	if _loops.has(key):
		var player: AudioStreamPlayer3D = _loops[key]
		player.stop()
		player.stream = null
		player.stream_paused = false
		_loop_free.append(player)
		_loops.erase(key)
		_loop_last_seen.erase(key)

func clear_gameplay() -> void:
	if _shutdown:return
	if boss_audio:boss_audio.clear()
	_pending.clear()
	for key in _loops.keys():stop_loop(str(key))
	for voice in _voices:voice.stop()
	_paused = false
	_last_hurt_sound = -1000
	_duck_level = 1.0
	set_volumes({})

func set_paused(value: bool) -> void:
	if _shutdown:return
	_paused = value
	if value:
		_pending.clear()
		for key in _loops.keys():stop_loop(str(key))
		for voice in _voices:voice.stop()

func set_backgrounded(value: bool) -> void:
	if _shutdown:return
	_backgrounded = value
	if value:
		_pending.clear()
		for key in _loops.keys():stop_loop(str(key))
		for voice in _voices:voice.stop()
		for voice in _ui_voices:voice.stop()
	if _music:_music.stream_paused = value

func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED:set_backgrounded(true)
	elif what == NOTIFICATION_APPLICATION_RESUMED:set_backgrounded(false)

func _process(dt: float) -> void:
	if _shutdown:return
	var controller: Node = get_parent()
	if controller and controller.has_method("_pause"):
		var paused: bool = bool(controller.get("paused"))
		if paused != _paused:set_paused(paused)
	var target: float = .5 if _paused else 1.0
	var next: float = move_toward(_duck_level, target, dt * (6.25 if _paused else .8333333333))
	if not is_equal_approx(next, _duck_level):
		_duck_level = next
		set_volumes({})
	if _backgrounded:return
	if boss_audio and not _paused:boss_audio.update(dt)
	for i in range(_pending.size()-1,-1,-1):
		_pending[i].left-=dt
		if float(_pending[i].left)<=0.0:
			var sound: Dictionary = _pending[i]
			_pending.remove_at(i)
			play(str(sound.sound),sound.options)
	var now: int = Time.get_ticks_msec()
	for key in _loop_last_seen.keys():
		if now - int(_loop_last_seen[key]) > 500:
			stop_loop(str(key))

func update_actors(actors: Array) -> void:
	if _shutdown:return
	if _backgrounded or _paused:return
	for actor in actors:
		var camera: Camera3D = get_viewport().get_camera_3d()
		if not actor.alive or (not actor.is_local and camera and camera.global_position.distance_to(actor.global_position) > 26.0):
			continue
		var key: String = str(actor.get_instance_id())
		var speed: float = Vector2(actor.velocity.x, actor.velocity.z).length()
		if actor.submerged:
			loop(key + "_swim", "swim", {"pos": actor.global_position, "volume": 0.20 + speed / 11.8 * 0.38, "pitch": 0.7 + speed / 11.8 * 0.7})
		if actor.climbing:
			loop(key + "_climb", "climb", {"pos": actor.global_position, "volume": 0.30, "pitch": 0.9 + absf(actor.velocity.y) / 7.5 * 0.3})
		if actor.rolling:
			loop(key + "_roll", "roll", {"pos": actor.global_position, "volume": speed / 4.4 * 0.45, "pitch": 0.7 + speed / 4.4 * 0.5})
		if actor.charge > 0.0:
			loop(key + "_charge", "splatling_spin" if actor.weapon_id == "splatling" else "charger_charge", {"pos": actor.global_position, "volume": 0.4, "pitch": 1.0 + actor.charge * 1.5})
		if actor.ground_team >= 0 and actor.ground_team != actor.team_id:
			loop(key + "_enemy_ink", "enemy_ink_sizzle", {"pos": actor.global_position, "volume": 0.25})

func on_event(kind: String, data: Dictionary) -> void:
	if _shutdown:return
	if not boss_audio:_setup()
	if boss_audio.on_event(kind,data):return
	if kind == "storm_rain":
		var actor = data.get("actor")
		var key: String = "storm_%s" % data.get("cloud",actor.get_instance_id() if is_instance_valid(actor) else 0)
		loop(key, "storm_rain", {"pos": data.get("pos", Vector3.ZERO), "volume": data.get("volume", 0.18)})
		return
	if kind=="storm:end":
		stop_loop("storm_%s"%data.get("cloud",0))
		return
	if kind == "damage":
		var victim = data.get("victim")
		var now: int = Time.get_ticks_msec()
		if is_instance_valid(victim) and victim.is_local and now-_last_hurt_sound > 250:
			_last_hurt_sound = now
			play("hurt", {"volume": 0.7})
		return
	if kind == "hit":
		var victim = data.get("victim")
		var attacker = data.get("attacker")
		if not is_instance_valid(victim):return
		var camera: Camera3D = get_viewport().get_camera_3d()
		var near_camera: bool = camera != null and camera.global_position.distance_to(victim.global_position)<26.0
		if victim.is_local or (is_instance_valid(attacker) and attacker.is_local) or near_camera:
			var amount: float = float(data.get("damage",0.0))
			var pos: Vector3 = victim.global_position+Vector3.UP*(.3 if str(victim.form)=="squid" else .9)
			play("ink_hit_body",{"pos":pos,"volume":(.3 if victim.is_local else .4)+minf(.45,amount/260.0),"pitch":.8 if amount>=60.0 else 1.05})
		return
	if kind == "splatted":
		var victim = data.get("victim")
		play("splatted_self" if is_instance_valid(victim) and victim.is_local else "splat_enemy", {"pos": data.get("pos", Vector3.ZERO)})
		return
	if kind == "actor:footstep":
		var surface: int = int(data.get("surface", 0))
		var actor = data.get("actor")
		var local: bool = is_instance_valid(actor) and actor.is_local
		var pos: Vector3 = data.get("pos",Vector3.ZERO)
		var camera: Camera3D = get_viewport().get_camera_3d()
		if not local and camera and camera.global_position.distance_squared_to(pos)>18.0*18.0:return
		var velocity: Vector3 = actor.velocity if is_instance_valid(actor) else Vector3.ZERO
		var speed: float = float(data.get("speed",Vector2(velocity.x,velocity.z).length()))
		var options: Dictionary = {"volume":(.7 if local else .45)*minf(1.0,.45+speed/8.0)}
		if not local:options.pos=pos
		play("step_enemy" if surface == 2 else ("step_ink" if surface == 1 else "step_dry"),options)
		return
	var fire_profiles: Dictionary = {"shoot_shooter":[.55,.4],"shoot_dualies":[.5,.36],"shoot_splatling":[.46,.33],"shoot_blaster":[.7,.5],"shoot_charger":[.8,.6],"roller_flick":[.8,.8],"dualies_roll":[.7,.5],"slosh_throw":[.75,.55],"slosh_land":[.75,.6],"splatling_wind":[.6,.42],"bomb_throw":[.7,.7]}
	if fire_profiles.has(kind):
		var actor = data.get("actor")
		var local: bool = is_instance_valid(actor) and bool(actor.get("is_local"))
		var pos: Vector3 = data.get("pos",actor.global_position if is_instance_valid(actor) else Vector3.ZERO)
		var camera: Camera3D = get_viewport().get_camera_3d()
		if not local and camera and camera.global_position.distance_squared_to(pos)>26.0*26.0:return
		var options: Dictionary = {"volume":fire_profiles[kind][0 if local else 1]}
		if not local or kind=="slosh_land":options.pos=pos
		if kind=="shoot_dualies":options.pitch=1.05 if int(data.get("hand",0))==1 else .97
		elif kind=="shoot_charger":options.pitch=1.08-.16*float(data.get("charge",1.0))
		play(kind,options)
		if kind=="shoot_blaster":
			options.volume=.55 if local else .4
			options.delay=.27
			play("blaster_pump",options)
		return
	var names: Dictionary = {"actor:jump": "jump", "actor:land": "land", "superjump:land": "land", "superjump": "super_jump", "boss:phase": "boss_phase", "boss:defeat": "boss_defeat", "boss:intro": "boss_title", "boss:hit": "boss_crit" if bool(data.get("weak", false)) else "boss_hit"}
	if names.has(kind):
		play(names[kind], data)
		return
	play(kind, data)
