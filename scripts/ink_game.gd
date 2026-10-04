class_name InkGame
extends Node3D

const Stage = preload("res://scripts/world/ink_stage.gd")
const Actor = preload("res://scripts/game/ink_actor.gd")
const Weapons = preload("res://scripts/game/ink_weapons.gd")
const Bots = preload("res://scripts/game/ink_bots.gd")
const Audio = preload("res://scripts/game/ink_audio.gd")
const PlayerController=preload("res://scripts/game/ink_player_controller.gd")
var player_controller:InkPlayerController=PlayerController.new()
var stage: InkStage
var projectiles: InkWeapons
var bots: InkBots
var audio: InkAudio
var fx: InkFx
var ui: InkUI
var camera: Camera3D
var camera_rig:Node
var actors: Array = []
var local_player: InkActor
var boss: Node3D
var network: Node
var lobby: InkLobby
var minimap: Node
var config: Dictionary
var options: Dictionary = {}
var settings: Dictionary = {}
var state := "menu"
var paused := false
var time_left := 180.0
var team_colors: Array = [Color("ff8a14"),Color("2f5bff")]
var clock := 0.0
var match_clock := 0.0
var _yaw := 0.0
var _pitch := -.12
var _pivot := Vector3.ZERO
var _distance := 4.5
var _recoil := 0.0
var _trauma := 0.0
var _hud_clock := 0.0
var _last_count := 180
var _hit_until := 0.0
var _kill_until := 0.0
var _feed: Array = []
var _menu_avatar: Node3D
var _world: Node3D
var _capture_path := ""
var _capture_time := -1.0
var _autopilot := false
var _benchmark: Array = []
var _frame_samples:Array[float]=[]
var _render_samples:Dictionary={}
var _native_profile_counts:Dictionary={}
var _args: Dictionary = {}
var _profile: Dictionary = {"level":1,"xp":0,"matches":0,"wins":0}
var _backgrounded:=false
var _frame_time:=1.0/60.0
var _quality_timer:=0.0
var _lobby_page:=""
var _lobby_viewport:SubViewport
var _lobby_layer:CanvasLayer
var _lobby_image:TextureRect
var _attract_clock:=0.0
var _shot_left:=0.0
var _shot_index:=0
var _attract_follow:InkActor
var _orbit_angle:=0.0
var _last_hit_sound:=-10.0
var _spawn_match_mode:="turf"
var _style_catalog:Dictionary={}

func _ready() -> void:
	process_mode=Node.PROCESS_MODE_ALWAYS
	config=JSON.parse_string(FileAccess.get_file_as_string("res://data/config.json"))
	_style_catalog=JSON.parse_string(FileAccess.get_file_as_string("res://data/styles.json"))
	_read_args();_bind_input();_load_profile()
	player_controller.configure(self)
	if _args.has("profile-render") and DisplayServer.get_name()!="headless":RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(),true)
	if _args.get("smoke","")=="match":_args.autostart=5;_autopilot=true
	_world=Node3D.new();_world.name="World";add_child(_world)
	camera=Camera3D.new();camera.current=true;camera.near=.15;camera.far=6500;add_child(camera)
	camera_rig=load("res://scripts/game/ink_camera_rig.gd").new();add_child(camera_rig);camera_rig.call("configure",self,camera)
	audio=Audio.new();add_child(audio)
	fx=preload("res://scripts/fx/ink_fx.gd").new();_world.add_child(fx);fx.configure(self)
	ui=load("res://scripts/ui/ink_ui.gd").new()
	ui.nonpersistent=_args.has("nonpersistent") or _args.has("smoke") or _args.has("ui-fixture")
	ui.fixture_mode=_args.has("ui-fixture")
	add_child(ui)
	ui.start_requested.connect(start_match);ui.pause_changed.connect(_pause);ui.exit_requested.connect(quit_to_menu)
	ui.style_changed.connect(func(s):preview_character(s,str(ui.options.weapon)))
	ui.weapon_changed.connect(func(w):preview_character(ui.profile,w))
	ui.super_jump_requested.connect(_super_jump);ui.online_requested.connect(_online)
	ui.setup(self)
	if ui.has_signal("judge_finished"):ui.connect("judge_finished",_judge_finished)
	if ResourceLoader.exists("res://scripts/net/ink_network.gd"):
		network=load("res://scripts/net/ink_network.gd").new();add_child(network);network.call("configure",self)
		network.connect("match_started",start_match)
		network.connect("status_changed",func(s):ui.toast(s))
		network.connect("lobby_changed",ui.show_lobby)
		network.connect("match_go",_network_go)
		network.connect("match_finished",_network_results)
		network.connect("match_ended",_network_lobby_return)
		network.connect("match_state_changed",_network_state_changed)
		network.connect("match_aborted",_network_aborted,CONNECT_DEFERRED)
	_setup_lobby_overlay()
	if not _args.has("autostart"):_start_attract()
	preview_character(ui.profile,str(ui.options.weapon))
	audio.play_music("title")
	if not _args.has("autostart") and not _args.has("smoke") and not _args.has("page"):ui.show_title()
	if _args.has("page"):_open_fixture_page.call_deferred(str(_args.page))
	if _args.has("autostart"):
		var start:Dictionary=ui.options.duplicate(true);start.map=str(_args.get("map","tidewater"));start.stage=start.map
		start.time_of_day=str(_args.get("time","day"));start.duration=float(_args.autostart);start.weapon=str(_args.get("weapon","shooter"));start.style=ui.profile
		start.mode=str(_args.get("mode","turf"));start_match.call_deferred(start)
	if _args.has("smoke"):_smoke.call_deferred(str(_args.smoke))

func _read_args() -> void:
	for arg in OS.get_cmdline_user_args():
		var pair:=arg.trim_prefix("--").split("=",true,1);_args[pair[0]]=pair[1] if pair.size()>1 else true
	if _args.has("benchmark-seed"):seed(int(_args["benchmark-seed"]))
	_autopilot=_args.has("autopilot")
	# Explicit unattended GPU probes continue simulation when the automation host takes focus.
	if _args.has("benchmark-background"):_backgrounded=false
	_capture_path=str(_args.get("capture",""));_capture_time=float(_args.get("capture-after",7.0)) if not _capture_path.is_empty() else -1.0

func _open_fixture_page(page_name:String) -> void:
	if _args.has("ui-fixture") and page_name!="results":
		preload("res://scripts/ui/lab_fixture.gd").show(ui,page_name);return
	if page_name!="results":ui.open_page(page_name);return
	var players:Array=[]
	var podium:Array=[]
	for i in 8:
		var weapon:String=config.WEAPON_ORDER[i%7]
		var style:Dictionary=ui.profile.duplicate(true) if i==0 else {"hair":i%8,"outfit":i%10,"skin":i%9,"eyes":i%8,"hat":i%4,"brows":i%4}
		players.append({"name":str(ui.profile.get("name","You")) if i==0 else config.BOT_NAMES[i],"team":0 if i<4 else 1,"weapon":weapon,"style":style,"turf":1094-i*86,"splats":8-i%5,"deaths":i%4,"isSelf":i==0,"bot":i!=0})
		if i<4:podium.append({"style":style,"weapon":weapon,"color":team_colors[0]})
	var before_level:int=int(_profile.level);var before_xp:int=int(_profile.xp)
	var after_level:int=before_level;var after_xp:int=before_xp+1740
	while after_xp>=800+after_level*350:after_xp-=800+after_level*350;after_level+=1
	var xp:Dictionary={"gained":1740,"levelBefore":before_level,"levelAfter":after_level,"xpBefore":before_xp,"xpAfter":after_xp,"xpToNextBefore":800+before_level*350,"xpToNextAfter":800+after_level*350}
	var result:Dictionary={"mode":"turf","win":true,"won":true,"winner":0,"team":0,"local_team":0,"percents":[52.2,38.8],"colors":team_colors,"team_names":config.TEAM_NAMES,"map":stage.stage_id,"map_name":stage.layout.get("name",stage.stage_id),"players":players,"score":1094,"splats":8,"deaths":0,"xp":xp}
	if _args.has("ui-fixture"):
		result=preload("res://scripts/ui/lab_fixture.gd").results(ui)
		podium.clear()
		for player:Dictionary in Array(result.players).slice(0,4):
			podium.append({"style":player.style,"weapon":player.weapon,"color":result.colors[0]})
	state="results";paused=false
	for actor in actors:actor.hide()
	if camera_rig:camera_rig.call("overview")
	_set_lobby_page("results");lobby.set_players(podium,true)
	ui.show_results(result)

func _bind_input() -> void:
	var keys:Dictionary={"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"swim":KEY_SHIFT,"jump":KEY_SPACE,"sub":KEY_E,"special":KEY_F,"map":KEY_TAB,"map_alt":KEY_M}
	for action in keys:
		if not InputMap.has_action(action):InputMap.add_action(action,.18)
		var event:=InputEventKey.new();event.physical_keycode=keys[action];InputMap.action_add_event(action,event)
	for pair in [["move_forward",KEY_UP],["move_back",KEY_DOWN],["move_left",KEY_LEFT],["move_right",KEY_RIGHT],["special",KEY_Q]]:
		var event:=InputEventKey.new();event.physical_keycode=pair[1];InputMap.action_add_event(pair[0],event)
	for action in ["fire","sub"]:
		if not InputMap.has_action(action):InputMap.add_action(action)
		var event:=InputEventMouseButton.new();event.button_index=MOUSE_BUTTON_LEFT if action=="fire" else MOUSE_BUTTON_RIGHT;InputMap.action_add_event(action,event)
	for pair in [["jump",JOY_BUTTON_A],["sub",JOY_BUTTON_RIGHT_SHOULDER],["special",JOY_BUTTON_Y],["special",JOY_BUTTON_RIGHT_STICK],["map",JOY_BUTTON_BACK],["ui_cancel",JOY_BUTTON_START]]:
		var event:=InputEventJoypadButton.new();event.button_index=pair[1];InputMap.action_add_event(pair[0],event)
	for pair in [["fire",JOY_AXIS_TRIGGER_RIGHT],["swim",JOY_AXIS_TRIGGER_LEFT]]:
		var event:=InputEventJoypadMotion.new();event.axis=pair[1];event.axis_value=1.0;InputMap.action_add_event(pair[0],event)

func _load_stage(id: String,time_of_day: String) -> void:
	if is_instance_valid(stage):stage.get_parent().remove_child(stage);stage.queue_free()
	stage=Stage.new();stage.name="InkStage";_world.add_child(stage);stage.build(id,time_of_day,team_colors,str(settings.get("quality","medium" if OS.has_feature("mobile") else "high")))
	if fx:fx.configure_lighting(stage.lighting_theme)
	var world_environment:WorldEnvironment=stage.get_node("WorldEnvironment")
	if lobby and world_environment.environment.sky:lobby.set_studio_radiance(world_environment.environment.sky,.6)
	minimap=load("res://scripts/game/ink_minimap.gd").new();stage.add_child(minimap);minimap.call("configure",stage,self,0);minimap.call("set_theme",time_of_day);stage.external_minimap=true
	minimap.call("set_active",state in ["intro","playing","finish","judge"])

func _setup_lobby_overlay() -> void:
	_lobby_viewport=SubViewport.new();_lobby_viewport.own_world_3d=true;_lobby_viewport.transparent_bg=true;_lobby_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED;add_child(_lobby_viewport)
	lobby=preload("res://scripts/world/ink_lobby.gd").new();_lobby_viewport.add_child(lobby);lobby.configure(self);lobby.set_active(false)
	_lobby_layer=CanvasLayer.new();_lobby_layer.layer=3;add_child(_lobby_layer)
	_lobby_image=TextureRect.new();_lobby_image.texture=_lobby_viewport.get_texture();_lobby_image.mouse_filter=Control.MOUSE_FILTER_IGNORE;_lobby_image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_lobby_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_lobby_layer.add_child(_lobby_image);_lobby_image.hide()
	get_viewport().size_changed.connect(_resize_lobby);_resize_lobby()

func _resize_lobby() -> void:
	if _lobby_viewport:_lobby_viewport.size=Vector2i(get_viewport().get_visible_rect().size)

func _set_lobby_page(page_name:String) -> void:
	var overlay:=page_name in ["online","lobby","loadout","locker","results"]
	lobby.set_active(overlay);_lobby_image.visible=overlay
	_lobby_viewport.render_target_update_mode=SubViewport.UPDATE_ALWAYS if overlay else SubViewport.UPDATE_DISABLED
	get_viewport().disable_3d=page_name in ["online","lobby"]
	if overlay:lobby.show_page("hub" if page_name=="online" else page_name)

func _start_attract() -> void:
	_clear_actors();state="menu";paused=false
	_spawn_match_mode="turf"
	_load_stage(str(_args.get("map","tidewater")),str(_args.get("time","day")))
	projectiles=Weapons.new();_world.add_child(projectiles);projectiles.configure(self)
	bots=Bots.new();bots.configure(self,"normal")
	if stage.stage_id!="cargo":
		var weapons:Array=_pick_team()+_pick_team()
		var names:Array=config.BOT_NAMES.duplicate();names.shuffle()
		for i in 8:
			var actor:=Actor.new();_world.add_child(actor);actor.configure(self,0 if i<4 else 1,false,str(weapons[i]),_random_style());actor.display_name=str(names[i]);actor.spawn_index=i%4;actor.set_meta("bot",true);actors.append(actor);actor.spawn_at(spawn_for(actor.team_id,i%4),0.0 if i<4 else PI);actor.invuln=0.0
			actor.avatar.call("configure_lighting",stage.lighting_theme)
	_attract_clock=0.0;_shot_index=0;_next_attract_shot();camera.current=true
	preview_character(ui.profile,str(ui.options.weapon))

func _pick_team(first:String="") -> Array:
	var pool:Array=config.WEAPON_ORDER.duplicate()
	var selected:Array=[]
	if pool.has(first):selected.append(first);pool.erase(first)
	while selected.size()<4:
		if pool.is_empty():pool=config.WEAPON_ORDER.duplicate()
		selected.append(pool.pop_at(randi_range(0,pool.size()-1)))
	return selected

func _random_style() -> Dictionary:
	return {"hair":randi_range(0,int(_style_catalog.HAIR_STYLES)-1),"skin":randi_range(0,_style_catalog.SKIN_TONES.size()-1),"outfit":randi_range(0,_style_catalog.OUTFITS.size()-1),"eyes":randi_range(0,_style_catalog.IRIS.size()-1),"hat":randi_range(1,_style_catalog.HATS.size()-1) if randf()<.34 else 0,"brows":randi_range(0,_style_catalog.BROWS.size()-1)}

func _next_attract_shot() -> void:
	var shot:=_shot_index%4;_shot_index+=1;_shot_left=7.0 if shot%2 else 10.0
	_attract_follow=null
	if shot%2 and not actors.is_empty():_attract_follow=actors.pick_random()
	_orbit_angle=randf()*TAU
	if camera_rig:
		if is_instance_valid(_attract_follow):camera_rig.call("follow",_attract_follow,true)
		else:camera_rig.call("orbit",Vector3(0,2,-8) if shot==2 else Vector3(0,1,0),18.0 if shot==2 else 34.0,7.0 if shot==2 else 17.0,-.07 if shot==2 else .05,_orbit_angle)

func start_match(selection: Dictionary) -> void:
	options=selection.duplicate(true)
	_benchmark.clear();_frame_samples.clear()
	_render_samples.clear()
	_native_profile_counts.clear()
	var id:=str(selection.get("map",selection.get("stage","tidewater")))
	var online:bool=is_instance_valid(network) and bool(network.get("active"))
	if id=="cargo" and not online:ui.toast("Cargo Terminal 需要联机且两队均有玩家");return
	_clear_actors()
	if lobby:lobby.set_active(false)
	if _lobby_image:_lobby_image.hide();_lobby_viewport.render_target_update_mode=SubViewport.UPDATE_DISABLED
	camera.current=true
	get_viewport().disable_3d=false
	if selection.get("settings") is Dictionary:apply_settings(selection.settings)
	var palettes:Array=config.TEAM_PALETTES
	var pal:Dictionary=config.COLORBLIND_PALETTE if settings.get("colorblind",false) else palettes[int(selection.get("palette",randi()%palettes.size()))%palettes.size()]
	options.team_names=pal.get("names",config.TEAM_NAMES)
	team_colors=[Color(pal.a),Color(pal.b)]
	_load_stage(id,str(selection.get("time_of_day",selection.get("timeOfDay","day"))))
	projectiles=Weapons.new();_world.add_child(projectiles);projectiles.configure(self)
	bots=Bots.new();bots.configure(self,str(selection.get("difficulty","normal")))
	var mode:=str(selection.get("mode","turf"));var roster:Array=selection.get("roster",[])
	_spawn_match_mode=mode
	if roster.is_empty():
		var weapons:Array=_pick_team(str(selection.get("weapon","shooter")))+_pick_team()
		var names:Array=config.BOT_NAMES.duplicate();names.shuffle()
		for i in 8:roster.append({"slot":i,"team":0 if mode=="boss" or i<4 else 1,"bot":i!=0,"weapon":weapons[i],"style":selection.get("style",ui.profile) if i==0 else _random_style(),"name":str(selection.get("profile",ui.profile).get("name","Fresh Kid")) if i==0 else names[i-1]})
	var local_slot:int=int(selection.get("local_slot",0))
	for r in roster:
		var nid:int=int(r.get("nid",r.slot))
		var actor:=Actor.new();actor.name="Actor_%d"%nid;_world.add_child(actor)
		actor.configure(self,int(r.team),nid==local_slot,str(r.weapon),r.get("style",{}));actor.display_name=str(r.get("name","Squidkid"))
		actor.avatar.call("configure_lighting",stage.lighting_theme)
		actor.spawn_index=int(r.slot) if mode=="boss" else int(r.slot)%4;actor.set_meta("slot",nid);actor.set_meta("bot",r.get("bot",false));actor.set_meta("owner",r.get("owner",1))
		actors.append(actor);actor.spawn_at(spawn_for(actor.team_id,actor.spawn_index),0.0 if actor.team_id==0 else PI);actor.invuln=0.0
		if actor.is_local:local_player=actor
	minimap.call("set_viewer_team",local_player.team_id)
	if mode=="boss" and ResourceLoader.exists("res://scripts/game/ink_boss.gd"):
		boss=load("res://scripts/game/ink_boss.gd").new();_world.add_child(boss);boss.call("configure",self,str(selection.get("difficulty","normal")))
		InkAvatar.configure_source_lighting(boss,stage.lighting_theme)
	state="waiting" if selection.get("wait_for_network",false) else "intro";paused=false;match_clock=0;time_left=float(selection.get("duration",240 if mode=="boss" else 180));_last_count=int(time_left)
	minimap.call("set_active",true)
	_yaw=0 if local_player.team_id==0 else PI;_pitch=-.12;_pivot=local_player.global_position+Vector3.UP*1.6
	player_controller.reset()
	ui.show_hud();audio.stop_music(1.2)
	if state=="intro":_begin_intro()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if ui.hud.touch.visible else Input.MOUSE_MODE_CAPTURED
	if online:network.call("bind_match")

func _begin_intro() -> void:
	state="intro";match_clock=0.0
	if camera_rig:camera_rig.call("intro",local_player,boss)
	audio.play("ready")
	if ui.has_method("show_intro"):ui.call("show_intro",options,actors)

func _begin_playing() -> void:
	state="playing";ui.hud.banner("GO!",.8);audio.play("go")
	if not boss:audio.play_music("battle",1.2)
	if camera_rig:camera_rig.call("follow",local_player,true)

func _begin_finish() -> void:
	state="finish";match_clock=0.0;projectiles.clear();ui.hud.banner("TIME'S UP!",2.4)
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if boss and camera_rig:camera_rig.call("boss_finish",boss)
	audio.match_finish(boss!=null,boss!=null and bool(boss.get("dead")))

func _clear_actors() -> void:
	player_controller.reset()
	# Room return detaches actors immediately; the render camera must release them first.
	if camera_rig:
		camera_rig.set("target",null)
		camera_rig.call("overview")
	if fx:fx.clear()
	for actor in actors:
		if is_instance_valid(actor):actor.get_parent().remove_child(actor);actor.queue_free()
	actors.clear();local_player=null
	for node in [projectiles,boss,_menu_avatar]:
		if is_instance_valid(node):node.get_parent().remove_child(node);node.queue_free()
	projectiles=null;bots=null;boss=null;_menu_avatar=null

func spawn_for(team: int,index: int) -> Vector3:
	var point:=InkStage.vec3(stage.layout.spawnPads[team])
	var angle:=float(index)/(8.0 if _spawn_match_mode=="boss" else 4.0)*TAU+.6
	var radius:=1.7 if _spawn_match_mode=="boss" else 1.2
	return point+Vector3(cos(angle)*radius,0,sin(angle)*radius)

func cast(from: Vector3,to: Vector3,exclude: Array=[],mask: int=1) -> Dictionary: return stage.cast(from,to,exclude,mask)
func sample_ink(point: Vector3,normal: Vector3=Vector3.UP) -> int:return stage.sample_ink(point,normal)
func paint_splat(point: Vector3,normal: Vector3,radius: float,team: int,extra: Dictionary={}) -> float:
	var area:=stage.paint_splat(point,normal,radius,team,extra)
	if is_instance_valid(network) and bool(network.get("active")) and network.has_method("paint_event"):network.call("paint_event",point,normal,radius,team,extra)
	return area

func _physics_process(dt: float) -> void:
	if not is_instance_valid(stage):return
	var profile_tick:int=Time.get_ticks_usec() if _args.has("profile-render") and state=="playing" else 0
	if network:network.call("update",dt)
	if state=="results":return
	var online:bool=network and bool(network.get("active"))
	if (paused or _backgrounded) and not online:return
	var authority:bool=not network or not network.get("active") or network.get("is_authority")
	if state=="menu":
		_attract_clock+=dt;_shot_left-=dt
		for actor in actors:actor.tick(dt,bots.command_for(actor,dt))
		if projectiles:projectiles.update(dt)
		if _shot_left<=0.0 and ui.page!="title":_next_attract_shot()
		if _attract_clock>110.0 or stage.coverage().x+stage.coverage().y>.72:_start_attract();return
	if state in ["intro","playing","finish"]:
		match_clock+=dt
		if boss and authority:boss.call("update",dt)
		profile_tick=_record_time("game_boss_and_network_cpu_ms",profile_tick)
		if state=="intro" and match_clock>=(7.2 if boss else 4.2) and authority:
			_begin_playing()
		if state=="playing":
			time_left=maxf(0,time_left-dt)
			var ai_time:int=0;var actor_time:int=0
			for actor in actors:
				if network and bool(network.get("active")) and not network.call("owns_actor",actor):continue
				var ai_start:int=Time.get_ticks_usec() if profile_tick else 0
				var command:Dictionary=_local_command(dt) if actor.is_local and not _autopilot else bots.command_for(actor,dt)
				if profile_tick and (not actor.is_local or _autopilot):
					for measure in bots.navigation_profile:
						var value:=float(bots.navigation_profile[measure])
						_record_metric("ai_"+str(measure).trim_suffix("_us")+"_cpu_ms" if str(measure).ends_with("_us") else "ai_"+str(measure),value/1000.0 if str(measure).ends_with("_us") else value)
				var actor_start:int=Time.get_ticks_usec() if profile_tick else 0
				if profile_tick:ai_time+=actor_start-ai_start
				actor.tick(dt,command)
				if profile_tick:
					actor_time+=Time.get_ticks_usec()-actor_start
					if actor.avatar:
						var avatar_profile:Dictionary=actor.avatar.get("animation_profile")
						var native_count:int=int(avatar_profile.get("native_mm_queries",0))
						var avatar_id:int=actor.avatar.get_instance_id()
						for measure in avatar_profile:
							if measure==&"uniform_updates":continue
							if str(measure)=="native_mm_query_us":
								if native_count>int(_native_profile_counts.get(avatar_id,0)):_record_metric("avatar_native_mm_query_cpu_ms",float(avatar_profile[measure])/1000.0)
							elif str(measure).begins_with("native_mm_"):_record_metric("avatar_"+str(measure),float(avatar_profile[measure]))
							else:_record_metric("avatar_"+str(measure)+"_cpu_ms",float(avatar_profile[measure])/1000.0)
						_native_profile_counts[avatar_id]=native_count
						var presentation:Dictionary=actor.avatar.get("presentation_profile")
						for measure in presentation:
							_record_metric("avatar_presentation_"+str(measure).trim_suffix("_us")+"_cpu_ms" if str(measure).ends_with("_us") else "avatar_presentation_"+str(measure),float(presentation[measure])/1000.0 if str(measure).ends_with("_us") else float(presentation[measure]))
			if profile_tick:
				_record_metric("game_actor_cpu_ms",float(actor_time)/1000.0)
				_record_metric("game_ai_cpu_ms",float(ai_time)/1000.0)
			profile_tick=_record_time("game_actor_and_ai_cpu_ms",profile_tick)
			projectiles.update(dt)
			profile_tick=_record_time("game_projectiles_cpu_ms",profile_tick)
			if int(ceil(time_left))!=_last_count:
				_last_count=int(ceil(time_left))
				if _last_count==60:
					audio.play("one_minute");ui.hud.banner("one_minute",2.3)
					if not boss:audio.play_music("battle_final",1.2)
				if _last_count<=10:audio.play("final_count");ui.hud.banner(str(_last_count),.65)
			if time_left<=0 or boss and bool(boss.get("dead")):
				_begin_finish()
		elif state=="intro":
			for actor in actors:
				if not network or not network.get("active") or network.call("owns_actor",actor):actor.tick(dt,{"move":Vector3.ZERO,"aim_dir":Vector3(0,0,1 if actor.team_id==0 else -1)})
		elif state=="finish" and match_clock>(5.2 if boss and bool(boss.get("dead")) else 3.2 if boss else 2.6):
			if boss:
				if authority:_show_results()
			else:_begin_judge()
	var feedback_started:int=Time.get_ticks_usec() if profile_tick else 0
	if state!="menu":audio.update_actors(actors)
	var fx_started:int=Time.get_ticks_usec() if profile_tick else 0
	if profile_tick:_record_metric("game_audio_cpu_ms",float(fx_started-feedback_started)/1000.0)
	if fx:fx.update(dt,actors)
	if profile_tick:_record_metric("game_fx_cpu_ms",float(Time.get_ticks_usec()-fx_started)/1000.0)
	if profile_tick and fx:
		for measure in fx.update_profile:
			var value:=float(fx.update_profile[measure])
			_record_metric("fx_"+str(measure).trim_suffix("_us")+"_cpu_ms" if str(measure).ends_with("_us") else "fx_"+str(measure),value/1000.0 if str(measure).ends_with("_us") else value)
	profile_tick=_record_time("game_feedback_cpu_ms",profile_tick)
	stage.update(dt,actors)
	profile_tick=_record_time("game_stage_update_cpu_ms",profile_tick)
	if minimap:minimap.call("update",dt)
	if stage.grade and local_player:stage.grade.hurt=clampf((40-local_player.hp)/40,0,1) if local_player.alive else 0
	if stage.grade and fx and fx.screen:stage.grade.update_screen(fx.screen)
	_hud_clock+=dt
	if _hud_clock>=.05 and local_player:_update_hud();_hud_clock=0
	_record_time("game_hud_and_minimap_cpu_ms",profile_tick)

func _record_time(label:String,started:int) -> int:
	if started==0:return 0
	var now:int=Time.get_ticks_usec()
	_record_metric(label,float(now-started)/1000.0)
	return now

func _record_metric(label:String,value:float) -> void:
	if not _render_samples.has(label):_render_samples[label]=[]
	if _render_samples[label].size()<7200:_render_samples[label].append(value)

func _local_command(dt: float) -> Dictionary:
	if paused or _backgrounded:return {"move":Vector3.ZERO,"aim_dir":local_player.aim_dir}
	var touch:Dictionary=ui.get_touch_state()
	var map_held:bool=Input.is_action_pressed("map") or Input.is_action_pressed("map_alt") or bool(touch.get("map",false))
	var map_up:bool=map_held or camera_rig and float(camera_rig.get("map_k"))>.05
	var move:=Vector2(Input.get_action_strength("move_right")-Input.get_action_strength("move_left"),Input.get_action_strength("move_back")-Input.get_action_strength("move_forward"))
	move+=touch.get("move",Vector2.ZERO)
	var pads:=Input.get_connected_joypads()
	var left:=Vector2.ZERO;var right:=Vector2.ZERO
	var pad_fire:bool=false;var pad_swim:bool=false
	if not pads.is_empty():
		var pad:int=pads[0]
		left=Vector2(Input.get_joy_axis(pad,JOY_AXIS_LEFT_X),Input.get_joy_axis(pad,JOY_AXIS_LEFT_Y))
		right=Vector2(Input.get_joy_axis(pad,JOY_AXIS_RIGHT_X),Input.get_joy_axis(pad,JOY_AXIS_RIGHT_Y))
		pad_fire=Input.get_joy_axis(pad,JOY_AXIS_TRIGGER_RIGHT)>.3;pad_swim=Input.get_joy_axis(pad,JOY_AXIS_TRIGGER_LEFT)>.3
	var look:Vector2=touch.get("look",Vector2.ZERO)
	if not map_up:_yaw-=look.x*.004;_pitch-=look.y*.003
	var command:Dictionary=player_controller.update(dt,{"move":move,"left":left,"right":right,"has_pad":not pads.is_empty(),"map_up":map_up})
	command.merge({"fire":not map_held and (Input.is_action_pressed("fire") or pad_fire or touch.get("fire",false)),"swim":Input.is_action_pressed("swim") or pad_swim or touch.get("swim",false),"jump":Input.is_action_pressed("jump") or touch.get("jump",false),"sub":not map_held and (Input.is_action_pressed("sub") or touch.get("sub",false)),"special":Input.is_action_pressed("special") or touch.get("special",false),"map":map_held})
	return command

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED and state=="playing" and not paused:
		if Input.is_action_pressed("map") or Input.is_action_pressed("map_alt") or camera_rig and float(camera_rig.get("map_k"))>.05:return
		player_controller.apply_mouse(event.relative)
	elif event is InputEventJoypadButton and event.pressed:player_controller.last_device="pad"
	elif event is InputEventKey and event.pressed:player_controller.last_device="kbm"
	elif event is InputEventMouseButton and event.pressed:player_controller.last_device="kbm"

func _process(dt: float) -> void:
	clock+=dt
	if OS.has_feature("mobile"):_adapt_resolution(dt)
	if lobby and state=="menu":
		if _lobby_page!=ui.page:
			_lobby_page=ui.page;_set_lobby_page(ui.page)
		if lobby.active:lobby.update(dt)
	if lobby and state=="results":lobby.update(dt)
	if _capture_time>0 and clock>=_capture_time:
		_capture_time=-1;_capture.call_deferred()
	if not stage:return
	_camera_update(dt)
	if state=="menu" and _menu_avatar:_menu_avatar.call("animate",dt,{"form":"kid","speed":0.0,"grounded":true,"tank":1.0})
	if state=="playing" and not paused and not _backgrounded and clock>5 and _frame_samples.size()<7200:
		_benchmark.append(Performance.get_monitor(Performance.TIME_FPS));_frame_samples.append(dt*1000.0)
		if _args.has("presentation-interpolation"):_record_metric("presentation_fraction",Engine.get_physics_interpolation_fraction())
		if _args.has("profile-render"):
			var measures:Dictionary={"main_render_gpu_ms":RenderingServer.viewport_get_measured_render_time_gpu(get_viewport().get_viewport_rid()),"main_render_cpu_ms":RenderingServer.viewport_get_measured_render_time_cpu(get_viewport().get_viewport_rid()),"render_setup_cpu_ms":RenderingServer.get_frame_setup_time_cpu(),"process_cpu_ms":Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,"physics_cpu_ms":Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0}
			measures.merge(ui.combat_profile_metrics())
			for measure in measures:
				if not _render_samples.has(measure):_render_samples[measure]=[]
				_render_samples[measure].append(float(measures[measure]))

func _camera_update(dt: float) -> void:
	if camera_rig:
		var show_map:bool=state=="playing" and not paused and (Input.is_action_pressed("map") or Input.is_action_pressed("map_alt") or ui.hud.get("_map_open")==true)
		camera_rig.call("set_map",show_map,ui.hud.map_cursor_vector())
		if state=="menu" and ui.page=="title" and camera_rig.get("mode")!="orbit":camera_rig.call("orbit",Vector3(0,1,0),34.0,17.0,.05,0.0)
		camera_rig.call("update",dt)
		if state=="playing" and is_instance_valid(local_player):
			player_controller.compute_aim()
			ui.update_combat_reticle(_combat_reticle_frame())
		if state=="menu" and is_instance_valid(_attract_follow) and not _attract_follow.alive:_shot_left=minf(_shot_left,.5)
		return
	_recoil=lerpf(_recoil,0,1-exp(-16*dt));_trauma=maxf(0,_trauma-dt*.8)
	if lobby and lobby.active and state=="results":return
	if state=="menu" or not local_player:
		if is_instance_valid(_attract_follow) and ui.page!="title":
			var actor:=_attract_follow
			var direction:=Vector3(sin(actor.aim_yaw),0,cos(actor.aim_yaw));var center:=actor.global_position+Vector3.UP*1.85
			camera.global_position=camera.global_position.lerp(center-direction*4.5+Vector3.UP*1.25,1-exp(-2*dt));camera.look_at(center+direction*4)
			if not actor.alive:_shot_left=minf(_shot_left,.5)
		else:
			var short_shot:=(_shot_index-1)%4==2 and ui.page!="title"
			var center:=Vector3(0,2,-8) if short_shot else Vector3(0,1,0)
			var angle:=_orbit_angle+_attract_clock*(-.07 if short_shot else .05)
			var target:=center+Vector3(sin(angle)*(18 if short_shot else 34),7 if short_shot else 17,cos(angle)*(18 if short_shot else 34))+Vector3.UP*sin(clock*.13)*1.2
			camera.global_position=camera.global_position.lerp(target,1-exp(-2*dt));camera.look_at(center)
		return
	var center:=local_player.global_position+Vector3.UP*(.5 if local_player.form!="kid" else 1.5)
	if state=="intro":
		var k:=clampf(match_clock/4.2,0,1);var pos:=Vector3(12,13,-16).lerp(center-Vector3(0,-1,4.5),smoothstep(0,1,k));camera.global_position=pos;camera.look_at(Vector3(0,2,0).lerp(center,k));return
	if state in ["finish","judge","waiting_results","results"]:
		camera.global_position=camera.global_position.lerp(Vector3(12,46,-47),1-exp(-2*dt));camera.look_at(Vector3(0,0,0));return
	var show_map:bool=Input.is_action_pressed("map") or Input.is_action_pressed("map_alt") or ui.hud.get("_map_open")==true
	if show_map:
		var len:float=stage.bounds.maxZ-stage.bounds.minZ;var target:=Vector3(0,len*.9,-len*.53 if local_player.team_id==0 else len*.53)
		camera.global_position=camera.global_position.lerp(target,1-exp(-7*dt));camera.look_at(Vector3.ZERO);camera.fov=lerpf(camera.fov,35,1-exp(-7*dt));return
	camera.fov=lerpf(camera.fov,_vertical_fov(float(settings.get("fov",82))),1-exp(-7*dt))
	_pivot=_pivot.lerp(center+local_player.velocity*Vector3(.025,0,.025),1-exp(-20*dt))
	var aim:=Vector3(sin(_yaw)*cos(_pitch),sin(_pitch),cos(_yaw)*cos(_pitch))
	var target:=_pivot-aim*4.5+Vector3.UP*.28
	var obstacle:=stage.cast(_pivot,target,[local_player.get_rid()])
	var length:float=4.5
	if not obstacle.is_empty():length=maxf(.6,_pivot.distance_to(obstacle.position)-.3)
	_distance=lerpf(_distance,length,1-exp(-(30 if length<_distance else 7)*dt))
	camera.global_position=_pivot-aim*_distance+Vector3.UP*.28
	var shake:float=_trauma*_trauma*float(settings.get("cameraShake",1.0));var offset:=Vector3(sin(clock*23.7),sin(clock*31.3),0)*shake*.055
	camera.look_at(_pivot+aim*16+offset+Vector3.UP*_recoil)

func _vertical_fov(horizontal: float) -> float:
	var view:=get_viewport().get_visible_rect().size
	return rad_to_deg(2*atan(tan(deg_to_rad(horizontal)*.5)/maxf(view.x/view.y,1)))

func _update_hud() -> void:
	var p:=stage.coverage();var roster:Array=[];var pins:Array=[]
	for a in actors:
		roster.append({"team":a.team_id,"name":a.display_name,"alive":a.alive,"weapon":a.weapon_id,"special":a.special_fraction(),"isSelf":a.is_local,"respawn":a.respawn_timer if not a.alive else 0.0})
		pins.append({"position":Vector2(a.global_position.x,a.global_position.z),"uv":minimap.call("to_uv",a.global_position) if minimap else Vector2.ZERO,"team":a.team_id,"alive":a.alive,"local":a.is_local,"isSelf":a.is_local,"name":a.display_name,"weapon":a.weapon_id,"respawn":a.respawn_timer if not a.alive else 0.0,"superjump_state":not a.super_jump_state.is_empty(),"aim_yaw":a.aim_yaw,"yaw":-a.aim_yaw+(PI if local_player.team_id==1 else 0.0),"slot":a.get_meta("slot",0)})
	var data:Dictionary={"time_left":time_left,"time":time_left,"hp":local_player.hp,"max_hp":100,"ink":local_player.ink,"max_ink":100,"special":local_player.special_fraction(),"score":local_player.turf_points,"percent_a":p.x*100,"percent_b":p.y*100,"team_color":team_colors[local_player.team_id],"enemy_color":team_colors[1-local_player.team_id],"weapon":local_player.weapon_id,"charge":local_player.charge,"roster":roster,"respawn":local_player.respawn_timer if not local_player.alive else 0,"swimming":local_player.form=="swim","hit":clock<_hit_until,"kill":clock<_kill_until,"feed":_feed,"map":{"texture":stage.minimap_texture(),"players":pins,"size":Vector2(stage.bounds.maxX-stage.bounds.minX,stage.bounds.maxZ-stage.bounds.minZ),"bounds":stage.bounds}}
	data.swimming=local_player.form=="squid"
	data.merge(_combat_reticle_frame(),true)
	if boss:data.boss_hp=boss.get("hp");data.max_boss_hp=boss.get("max_hp");data.boss_phase=boss.get("phase")
	if minimap:
		data.map.texture=minimap.call("get_texture");data.map.texture_size=Vector2(minimap.get("width"),minimap.get("height"));data.map.viewer_team=local_player.team_id;data.map.local_team=local_player.team_id
		var home:Vector3=Stage.vec3(stage.layout.spawnPads[local_player.team_id])
		data.map.base_uv=minimap.call("to_uv",home)
	ui.update_match(data)

func _combat_reticle_frame()->Dictionary:
	var weapon:Dictionary=InkRules.weapon(local_player.weapon_id)
	var cone:float=projectiles.spread_degrees(weapon,local_player.weapon_id,local_player.is_grounded(),float(local_player.weapon_state.get("bloom",0.0)),float(local_player.weapon_state.get("lock",0.0))>0.0)
	var spread:float=28.0 if local_player.weapon_id=="roller" else minf(90.0,tan(deg_to_rad(cone))/tan(deg_to_rad(camera.fov)*.5)*get_viewport().get_visible_rect().size.y*.5)
	var sub:Dictionary=InkRules.section("SUB").get("bomb",{})
	return {"crosshair":{"spread":spread,"onTarget":"enemy" if is_instance_valid(player_controller.on_target) else "none","inRange":player_controller.in_range},"weapon":local_player.weapon_id,"charge":local_player.charge,"weapon_state":local_player.weapon_state,"invuln":local_player.invuln,"alive":local_player.alive,"ink":local_player.ink,"max_ink":100.0,"subCost":float(sub.get("inkCost",70.0))/100.0,"inkLow":local_player.ink<18.0,"aim_yaw":_yaw,"velocity":local_player.velocity,"camera_right":camera.global_basis.x,"team_color":team_colors[local_player.team_id],"enemy_color":team_colors[1-local_player.team_id]}

func notify_event(kind: String,data: Dictionary) -> void:
	if audio and state!="menu":audio.on_event(kind,data)
	if fx:fx.on_event(kind,data)
	if minimap:minimap.call("on_event",kind,data)
	if ui and state!="menu" and ui.has_method("on_event"):ui.call("on_event",kind,data)
	if network and bool(network.get("active")) and network.has_method("on_event"):network.call("on_event",kind,data)
	if camera_rig and state!="menu" and (kind!="recoil" or data.get("actor")==local_player):camera_rig.call("on_event",kind,data)
	if kind=="hit" and data.get("attacker")==local_player:
		_hit_until=clock+.12
		if data.get("killed",false):_kill_until=clock+.45
		if clock-_last_hit_sound>.06:_last_hit_sound=clock;audio.play("hit_marker",{"volume":.6})
	if kind=="damage":
		if data.get("victim")==local_player and float(data.get("amount",0))>=40 and camera_rig:camera_rig.call("add_shake",clampf((float(data.amount)-30)/220,0,.4))
	if kind=="splatted":
		var victim=data.get("victim");var attacker=data.get("attacker")
		_feed.push_front({"text":str(attacker.display_name) + "  →  " + str(victim.display_name) if is_instance_valid(attacker) and is_instance_valid(victim) else "SPLATTED!","time":clock})
		if _feed.size()>4:_feed.pop_back()
		if attacker==local_player:_kill_until=clock+.45
	if local_player:
		var feedback:=Vector3.ZERO
		if kind=="damage" and data.get("victim")==local_player and str(data.get("source",""))!="ink":
			var amount:=float(data.get("amount",0.0))
			feedback=Vector3(clampf(amount/80.0,.25,.8),clampf(amount/110.0,.18,.7),(.09+minf(.12,amount/1000.0)))
		elif kind=="splatted" and data.get("victim")==local_player:feedback=Vector3(.6,.8,.26)
		elif kind in ["special:slam","superjump:land"] and data.get("actor")==local_player:feedback=Vector3(.18,.22,.12)
		var rumble:=clampf(float(settings.get("rumble",1.0)),0,1)
		if feedback.z>0 and rumble>0:
			for pad in Input.get_connected_joypads():Input.start_joy_vibration(pad,feedback.x*rumble,feedback.y*rumble,feedback.z)

func _show_results() -> void:
	state="results";Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var p:=stage.coverage();var won:bool=p[local_player.team_id]>=p[1-local_player.team_id]
	if boss:won=bool(boss.get("dead"))
	var players:Array=actors.map(func(a):return {"name":a.display_name,"team":a.team_id,"weapon":a.weapon_id,"splats":a.splats,"deaths":a.deaths,"turf":roundi(a.turf_points),"isSelf":a.is_local,"bot":bool(a.get_meta("bot",false)),"damage":a.get_meta("boss_damage",0),"weakHits":a.get_meta("weak_hits",0)})
	var result:Dictionary={"mode":options.get("mode","turf"),"won":won,"win":won,"winner":local_player.team_id if won else 1-local_player.team_id,"percent_a":p.x*100,"percent_b":p.y*100,"percents":[p.x*100,p.y*100],"score":local_player.turf_points,"turf":local_player.turf_points,"splats":local_player.splats,"deaths":local_player.deaths,"xp":_award_xp(won),"level":_profile.level,"roster":players,"players":players,"colors":team_colors.map(func(c):return "#"+c.to_html(false)),"teamNames":options.get("team_names",config.TEAM_NAMES),"mapName":str(stage.layout.get("name",stage.stage_id)),"online":network and bool(network.get("active"))}
	if boss:result.boss={"name":"Hullbreaker","defeated":won,"time":float(options.get("duration",240))-time_left,"hpLeft":float(boss.get("hp"))/maxf(1,float(boss.get("max_hp"))),"phase":boss.get("phase"),"maxHp":boss.get("max_hp")}
	ui.show_results(result)
	if network and network.get("active"):network.call("publish_result",result)
	_show_results_world(won)
	audio.play_music("results_win" if won else "results_lose");audio.play("victory_fanfare" if won else "defeat_jingle")

func _begin_judge() -> void:
	state="judge";match_clock=0.0
	if camera_rig:camera_rig.call("overview")
	var coverage:=stage.coverage()
	if ui.has_method("judge"):ui.call("judge",{"colors":team_colors,"percents":[coverage.x*100,coverage.y*100],"names":options.get("team_names",config.TEAM_NAMES)})
	else:_judge_finished(0 if coverage.x>=coverage.y else 1)

func _judge_finished(_winner: int) -> void:
	if not network or not network.get("active") or network.get("is_authority"):_show_results()
	else:state="waiting_results"

func _network_go() -> void:
	_begin_intro()

func _network_state_changed(next_state:String) -> void:
	if next_state=="playing" and is_instance_valid(local_player):
		_begin_playing()
	elif next_state=="finish" and is_instance_valid(local_player):_begin_finish()

func _network_lobby_return() -> void:
	_clear_actors();state="menu";paused=false;match_clock=0
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	if audio:audio.clear_gameplay();audio.play_music("title")
	if minimap:minimap.call("set_active",false)
	if stage and stage.grade:stage.grade.hurt=0.0
	_lobby_page="lobby";_set_lobby_page("lobby")

func _network_aborted(reason:String) -> void:
	quit_to_menu()
	ui.open_page("online")
	_set_lobby_page("online")
	ui.toast(reason)

func _network_results(stats: Dictionary) -> void:
	state="results";Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	var result:Dictionary=stats.duplicate(true)
	var won:bool=int(result.get("winner",0))==local_player.team_id
	result.won=won;result.score=local_player.turf_points;result.turf=local_player.turf_points;result.splats=local_player.splats;result.deaths=local_player.deaths
	result.win=won;result.xp=_award_xp(won)
	var players:Array=result.get("players",result.get("roster",[]))
	for player in players:player.isSelf=player.name==local_player.display_name and int(player.get("team",-1))==local_player.team_id
	ui.show_results(result);audio.play_music("results_win" if won else "results_lose")
	_show_results_world(won)

func _award_xp(won: bool) -> Dictionary:
	var before_level:=int(_profile.level);var before_xp:=int(_profile.xp)
	var gain:=roundi((1200 if won else 500)+roundi(local_player.turf_points)+local_player.splats*40+float(local_player.get_meta("boss_damage",0))*.04)
	_profile.xp+=gain;_profile.matches+=1;_profile.totalTurf=float(_profile.get("totalTurf",0))+roundi(local_player.turf_points)
	if won:_profile.wins+=1
	while int(_profile.xp)>=800+int(_profile.level)*350:_profile.xp-=800+int(_profile.level)*350;_profile.level+=1
	_save_profile()
	return {"gained":gain,"levelBefore":before_level,"levelAfter":_profile.level,"xpBefore":before_xp,"xpAfter":_profile.xp,"xpToNextBefore":800+before_level*350,"xpToNextAfter":800+int(_profile.level)*350}

func _show_results_world(won: bool) -> void:
	if not lobby:return
	for actor in actors:actor.hide()
	lobby.set_team_colors(team_colors[local_player.team_id],team_colors[1-local_player.team_id])
	_set_lobby_page("results")
	var podium:Array=actors.filter(func(a):return a.team_id==local_player.team_id)
	if boss:podium.sort_custom(func(a,b):return float(a.get_meta("boss_damage",0))>float(b.get_meta("boss_damage",0)))
	lobby.set_players(podium.slice(0,4).map(func(a):return {"style":a.style,"weapon":a.weapon_id,"color":team_colors[a.team_id]}),won)

func _pause(value: bool) -> void:
	paused=value
	player_controller.mouse_delta=Vector2.ZERO;player_controller.mouse_active=false;player_controller.assist.has=false
	if audio.has_method("set_paused"):audio.call("set_paused",value and (not network or not network.get("active")))
	ui.hud.touch.reset()
	_release_actions()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if value or ui.hud.touch.visible else Input.MOUSE_MODE_CAPTURED

func quit_to_menu() -> void:
	if network:network.call("leave")
	_clear_actors();state="menu";paused=false;ui.show_menu();preview_character(ui.profile,str(ui.options.weapon));audio.play_music("menu")
	if stage:stage.get_parent().remove_child(stage);stage.queue_free();stage=null;minimap=null
	if lobby:lobby.set_active(true);lobby.show_page("loadout")
	_set_lobby_page("main");_start_attract()
	if audio.has_method("clear_gameplay"):audio.call("clear_gameplay")

func preview_character(style: Dictionary,weapon: String) -> void:
	if is_instance_valid(network) and network.get("active") and network.has_method("set_me"):network.call("set_me",{"name":ui.profile.name,"style":style,"weapon":weapon})
	if lobby and state=="menu":lobby.set_style(style,team_colors[0],weapon);return
	if state!="menu" or not is_instance_valid(stage):return
	if not is_instance_valid(_menu_avatar):
		_menu_avatar=load("res://scripts/characters/ink_avatar.gd").new();_world.add_child(_menu_avatar);_menu_avatar.position=Vector3(4,stage.ground_height(4,-6),-6);_menu_avatar.rotation.y=PI*.78
	_menu_avatar.call("configure",team_colors[0],weapon,style)
	_menu_avatar.call("configure_lighting",stage.lighting_theme)

func apply_settings(values: Dictionary) -> void:
	settings.merge(values,true)
	if audio:audio.set_volumes(values)
	if fx:fx.set_quality(settings)
	var quality:=str(settings.get("quality","high"))
	var mobile:=OS.has_feature("mobile")
	get_viewport().msaa_3d=Viewport.MSAA_DISABLED if mobile or quality=="low" else Viewport.MSAA_2X if quality=="medium" else Viewport.MSAA_4X
	get_viewport().anisotropic_filtering_level=Viewport.ANISOTROPY_16X if not mobile and quality in ["high","ultra"] else Viewport.ANISOTROPY_4X
	get_viewport().scaling_3d_scale=.65 if mobile and quality=="low" else .8 if mobile and quality=="medium" else .7 if quality=="low" else .85 if quality=="medium" else 1.0
	Engine.max_fps=int(_args["benchmark-fps"]) if _args.has("benchmark-fps") else (60 if mobile else 0)
	_frame_time=1.0/60.0;_quality_timer=0.0
	if lobby:lobby.set_quality(quality)
	if is_instance_valid(stage) and stage.environment_detail:stage.environment_detail.set_quality(quality)
	if is_instance_valid(stage) and stage.grade:stage.grade.bloom_enabled=quality!="low" and bool(settings.get("bloom",true))
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)

func _super_jump(index: int) -> void:
	if state!="playing" or paused or not local_player or index<0 or index>3:return
	if index==3:
		local_player.super_jump(InkStage.vec3(stage.layout.spawnPads[local_player.team_id]))
		return
	var allies:Array=actors.filter(func(a):return a.team_id==local_player.team_id and a!=local_player)
	if index>=allies.size():return
	var ally:InkActor=allies[index]
	if ally.alive and ally.super_jump_state.is_empty():local_player.super_jump(ally)

func _online(request: Dictionary) -> void:
	if not network:ui.toast("网络模块正在初始化");return
	match str(request.get("action","host")):
		"host":network.call("host",request)
		"weapon":network.call("set_me",{"weapon":str(request.get("weapon",ui.options.weapon))})
		"join":network.call("join",request)
		"start":network.call("start")
		"ready":network.call("set_ready",request.get("ready",true))
		"leave":network.call("leave")
		"options":network.call("set_lobby_options",request.get("match",{}))
		"team":network.call("set_team",int(request.get("team",0)))
		"emote":
			if network.has_method("emote"):network.call("emote",request.get("name",request.get("emote",request.get("index",0))))
		"return_lobby":
			if network.has_method("return_to_lobby"):network.call("return_to_lobby")

func _adapt_resolution(dt: float) -> void:
	if dt<=0.0 or dt>.1:return
	_frame_time=lerpf(_frame_time,dt,1-exp(-2*dt));_quality_timer+=dt
	if _quality_timer<2.0:return
	_quality_timer=0.0
	var ceiling:=.65 if settings.get("quality")=="low" else .8 if settings.get("quality")=="medium" else 1.0
	var scale:=get_viewport().scaling_3d_scale
	if _frame_time>.020:scale=maxf(.5,scale-.05)
	elif _frame_time<.015:scale=minf(ceiling,scale+.025)
	get_viewport().scaling_3d_scale=scale

func _release_actions() -> void:
	player_controller.mouse_delta=Vector2.ZERO;player_controller.mouse_active=false;player_controller.assist.has=false
	for action in ["fire","sub","swim","jump","special","map","map_alt","move_forward","move_back","move_left","move_right"]:
		Input.action_release(action)
	for pad in Input.get_connected_joypads():Input.stop_joy_vibration(pad)

func _notification(what: int) -> void:
	if what in [NOTIFICATION_APPLICATION_PAUSED,NOTIFICATION_APPLICATION_FOCUS_OUT]:
		if _args.has("benchmark-background"):return
		_backgrounded=true;_release_actions()
		if ui and ui.hud:ui.hud.touch.reset()
		if audio and audio.has_method("set_backgrounded"):audio.call("set_backgrounded",true)
	elif what in [NOTIFICATION_APPLICATION_RESUMED,NOTIFICATION_APPLICATION_FOCUS_IN]:
		_backgrounded=false;_frame_time=1.0/60.0
		if audio and audio.has_method("set_backgrounded"):audio.call("set_backgrounded",false)

func _smoke(kind: String) -> void:
	await get_tree().create_timer(22.0 if kind=="match" else 2.0).timeout
	var passed:=is_instance_valid(ui) and is_instance_valid(lobby)
	if kind=="match":passed=passed and actors.size()==8 and state=="results" and local_player.turf_points>0
	else:passed=passed and state=="menu" and is_instance_valid(stage) and ui.page=="main"
	print("SPLATINK_SMOKE ",JSON.stringify({"kind":kind,"passed":passed,"state":state,"engine":Engine.get_version_info().string,"actors":actors.size()}))
	get_tree().quit(0 if passed else 1)

func _load_profile() -> void:
	if _args.has("smoke") or _args.has("ui-fixture") or _args.has("nonpersistent"):return
	var save:=ConfigFile.new()
	if save.load("user://splatink_progress.cfg")==OK:_profile.merge(save.get_value("profile","data",{}),true)

func _save_profile() -> void:
	if _args.has("smoke") or _args.has("ui-fixture") or _args.has("nonpersistent"):return
	var save:=ConfigFile.new();save.set_value("profile","data",_profile);save.save("user://splatink_progress.cfg")

func _capture() -> void:
	await RenderingServer.frame_post_draw
	var image:=get_viewport().get_texture().get_image()
	var path:String=ProjectSettings.globalize_path(_capture_path)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir());var result:=image.save_png(path)
	var fps:=0.0
	for value in _benchmark:fps+=float(value)
	fps/=maxi(1,_benchmark.size())
	var monitor_fps:float=fps
	var sampled_seconds:float=0.0
	for duration:float in _frame_samples:sampled_seconds+=duration/1000.0
	fps=float(_frame_samples.size())/sampled_seconds if sampled_seconds>0.0 else 0.0
	var times:Array[float]=_frame_samples.duplicate();times.sort()
	var report:Dictionary={"stage":stage.stage_id if stage else "showcase","state":state,"page":ui.page,"actors":actors.size(),"coverage":[stage.coverage().x,stage.coverage().y] if stage else [],"paint_cells":stage.grid.size() if stage else 0,"fps_average":fps,"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),"objects":Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),"screenshot_error":result}
	report.merge({"frame_samples":times.size(),"sampled_render_seconds":sampled_seconds,"engine_fps_monitor_average":monitor_fps,"fps_method":"render frame count / sum of sampled render deltas","frame_median_ms":times[floori(times.size()/2.0)] if not times.is_empty() else 0.0,"frame_p95_ms":times[mini(times.size()-1,floori(times.size()*.95))] if not times.is_empty() else 0.0,"triangles":Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME),"quality":settings.get("quality","medium"),"render_scale":get_viewport().scaling_3d_scale,"atlas":stage.atlas_size if stage else 0,"platform":OS.get_name(),"engine":Engine.get_version_info().string})
	report.merge({"capture_clock_seconds":clock,"playing_seconds":maxf(0.0,float(options.get("duration",180.0))-time_left),"focus_paused":_backgrounded,"unattended_simulation":_args.has("benchmark-background")})
	report.merge({"benchmark_seed":int(_args.get("benchmark-seed",-1)),"frame_hz_limit":Engine.max_fps,"presentation_interpolation":_args.has("presentation-interpolation"),"presentation_active_actors":actors.filter(func(actor):return actor.avatar and bool(actor.avatar.get("presentation_active"))).size()})
	if _args.has("native-locomotion-mm"):
		var native_actors:Array=[]
		for actor in actors:
			if actor.avatar:
				native_actors.append({"active":bool(actor.avatar.get("_native_motion_active")),"motion":actor.avatar.motion_state.duplicate(true)})
		report.native_locomotion={"requested":true,"active_actors":native_actors.filter(func(item):return bool(item.active)).size(),"actors":native_actors}
	if not _render_samples.is_empty():
		report.render_profile={"scope":"Main viewport and separately timed reticle auxiliary passes. Other auxiliary viewport GPU work is excluded. Process/physics CPU include game subsystems."}
		for measure in _render_samples:
			var samples:Array=_render_samples[measure].duplicate();samples.sort()
			report.render_profile[measure]={"median":samples[floori(samples.size()/2.0)],"p95":samples[mini(samples.size()-1,floori(samples.size()*.95))],"max":samples[-1]}
		report.gpu_timing_available=float(report.render_profile.get("main_render_gpu_ms",{}).get("max",0.0))>0.0
	var file:=FileAccess.open(path.get_basename()+".json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close();print("SPLATINK_CAPTURE "+JSON.stringify(report));get_tree().quit()
