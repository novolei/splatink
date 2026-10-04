extends SceneTree

const Game = preload("res://scripts/ink_game.gd")
class IdleBots extends InkBots:
	func command_for(actor, _dt:float) -> Dictionary:
		return {"move":Vector3.ZERO,"aim_dir":actor.aim_dir}

var game:InkGame
var checks:=0
var failures:Array[String]=[]
var report:Dictionary={}

func _initialize() -> void:
	create_timer(45.0).timeout.connect(func():push_error("PC_INPUT watchdog");quit(1))
	call_deferred("_run")

func _check(label:String, passed:bool) -> void:
	checks+=1
	if not passed:failures.append(label);push_error("PC_INPUT "+label)

func _key(code:Key, pressed:bool) -> void:
	var event:=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()

func _mouse(button:MouseButton, pressed:bool) -> void:
	var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed
	Input.parse_input_event(event);Input.flush_buffered_events()

func _wait(seconds:float) -> void:
	await create_timer(seconds).timeout
	await physics_frame

func _run() -> void:
	game=Game.new();root.add_child(game)
	# Prevent this verification from awarding or persisting match progress.
	game._args.smoke="input-contract"
	game.start_match({"map":"tidewater","time_of_day":"day","duration":180,"weapon":"shooter","palette":0,"style":game.ui.profile})
	print("PC_INPUT_START ",game.ui.page," in_match=",game.ui.in_match," menu=",game.ui._menu.visible," mouse=",Input.mouse_mode)
	game.bots=IdleBots.new();game.bots.configure(game)
	await _wait(4.5)
	_check("intro enters playing",game.state=="playing")
	_check("eight native actors",game.actors.size()==8)
	if OS.get_cmdline_user_args().has("--native-locomotion-mm"):
		_check("eight actual native lower-body matchers",game.actors.all(func(item):return item.avatar and bool(item.avatar.get("_native_motion_active"))))
		_check("native lower-body queries run in the actual match",game.actors.all(func(item):return int(item.avatar.motion_state.get("native_queries",0))>0))
	_check("battle HUD remains active after page transition",game.ui.in_match and not game.ui._menu.visible and game.ui.page.is_empty())
	print("PC_INPUT_PLAYING ",game.ui.page," in_match=",game.ui.in_match," menu=",game.ui._menu.visible," mouse=",Input.mouse_mode)
	var actor:InkActor=game.local_player
	var start:Vector3=actor.global_position
	_key(KEY_W,true)
	_check("physical W maps to forward",Input.is_action_pressed("move_forward"))
	await _wait(2.2)
	_key(KEY_W,false)
	await _wait(.25)
	report.walk_distance=start.distance_to(actor.global_position)
	_check("W moves player through physics",float(report.walk_distance)>8.0)
	_check("W release clears action",not Input.is_action_pressed("move_forward"))
	_check("player grounded after walking",actor.is_grounded())
	var yaw_before:float=game._yaw
	var physics_before:int=Engine.get_physics_frames()
	var motion:=InputEventMouseMotion.new();motion.relative=Vector2(24,18)
	Input.parse_input_event(motion);Input.flush_buffered_events()
	_check("raw mouse reaches look before the next physics frame",Engine.get_physics_frames()==physics_before and absf(game._yaw-yaw_before)>.02)
	await process_frame
	_check("mouse relative input turns camera",absf(game._yaw-yaw_before)>.02)
	game._pitch=-.5
	await _wait(.35)
	var ink_before:float=actor.ink
	_mouse(MOUSE_BUTTON_LEFT,true)
	await _wait(2.0)
	report.ink_before=ink_before;report.ink_firing=actor.ink;report.turf=actor.turf_points
	_check("left mouse fires weapon",actor.firing and actor.ink<ink_before-1.0)
	_mouse(MOUSE_BUTTON_LEFT,false)
	await _wait(.35)
	_check("shots paint playable surfaces",actor.turf_points>0.0 and game.stage.coverage().x>0.0)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://shots/pc-input-firing.png"))
	_key(KEY_ESCAPE,true);_key(KEY_ESCAPE,false)
	await _wait(.15)
	_check("Escape opens pause",game.paused and game.ui.page=="pause")
	var pause_position:Vector3=actor.global_position;var pause_time:float=game.time_left
	_key(KEY_W,true);_mouse(MOUSE_BUTTON_LEFT,true)
	await _wait(.5)
	_check("pause freezes offline match",actor.global_position.distance_to(pause_position)<.001 and is_equal_approx(pause_time,game.time_left))
	_key(KEY_W,false);_mouse(MOUSE_BUTTON_LEFT,false)
	_key(KEY_ESCAPE,true);_key(KEY_ESCAPE,false)
	await _wait(.15)
	_check("Escape resumes without held actions",not game.paused and not Input.is_action_pressed("fire") and not Input.is_action_pressed("move_forward"))
	# Move through the ink placed by the player's own firing above.
	_key(KEY_W,true)
	await _wait(.45)
	_key(KEY_W,false)
	await _wait(.2)
	var swim_ink:float=actor.ink
	_key(KEY_SHIFT,true)
	await _wait(.25)
	_check("Shift changes to squid",actor.form=="squid")
	report.swim_ground_team=actor.ground_team;report.submerged=actor.submerged
	await _wait(.5)
	report.ink_before_swim=swim_ink;report.ink_after_swim=actor.ink
	_check("own ink refills squid tank",actor.ground_team==actor.team_id and actor.submerged and actor.ink>swim_ink)
	_key(KEY_SHIFT,false)
	await _wait(.2)
	_check("Shift release restores kid",actor.form=="kid")
	var foot_y:float=actor.global_position.y
	_key(KEY_SPACE,true)
	await _wait(.15)
	report.jump_height=actor.global_position.y-foot_y
	_check("Space produces jump",float(report.jump_height)>.15 and not actor.is_grounded())
	_key(KEY_SPACE,false)
	await _wait(1.0)
	_check("jump lands cleanly",actor.is_grounded() and actor.alive)
	if OS.get_cmdline_user_args().has("--native-locomotion-mm"):
		report.native_locomotion=actor.avatar.motion_state.duplicate(true)
		_check("native provider remains active after swim and jump",bool(actor.avatar.get("_native_motion_active")) and int(report.native_locomotion.get("native_queries",0))>5)
	_key(KEY_TAB,true)
	await _wait(.85)
	_check("Tab opens tactical map",game.ui.hud.get("_map_open")==true)
	_check("Tab uses live vertical camera",(-game.camera.global_basis.z).dot(Vector3.DOWN)>.99999)
	_check("live map hides image-map panel",not game.ui.hud._map_panel.visible)
	var diorama:SplatHudDiorama=game.ui.hud._diorama
	_check("live map projects five world beacons",diorama.on and diorama.pins.size()==5 and bool(diorama.pins[4].visible))
	var map_ink:float=actor.ink
	_mouse(MOUSE_BUTTON_LEFT,true)
	_key(KEY_E,true)
	await _wait(.2)
	_check("map selection cannot fire or throw",not actor.firing and actor.ink>=map_ink-.001)
	_mouse(MOUSE_BUTTON_LEFT,false);_key(KEY_E,false)
	var map_yaw:float=game._yaw
	var cursor_before:Vector2=diorama.cursor
	var map_motion:=InputEventMouseMotion.new();map_motion.relative=Vector2(120,90)
	Input.parse_input_event(map_motion);Input.flush_buffered_events()
	await _wait(.1)
	_check("map mouse steers cursor without aim rotation",diorama.cursor.distance_to(cursor_before)>.05 and absf(game._yaw-map_yaw)<.000001)
	_check("map cursor preserves vertical view",(-game.camera.global_basis.z).dot(Vector3.DOWN)>.99999)
	if DisplayServer.get_name()!="headless":
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://shots/pc-input-live-map.png"))
	var allies:Array=game.actors.filter(func(a):return a.team_id==actor.team_id and a!=actor)
	allies[0].alive=false
	game._super_jump(0)
	_check("dead teammate retains unavailable first jump slot",actor.super_jump_state.is_empty())
	game._super_jump(1)
	_check("second jump slot selects second teammate",actor.super_jump_state.get("target")==allies[1])
	actor.super_jump_state.clear();allies[0].alive=true
	_key(KEY_4,true);_key(KEY_4,false)
	_check("map key4 jumps to base",actor.super_jump_state.get("target") is Vector3 and Vector3(actor.super_jump_state.target).distance_to(InkStage.vec3(game.stage.layout.spawnPads[actor.team_id]))<.000001)
	_key(KEY_TAB,false)
	await _wait(.4)
	_check("Tab release closes map",game.ui.hud.get("_map_open")==false)
	report.merge({"checks":checks,"passed":failures.is_empty(),"failures":failures,"state":game.state,"position":str(actor.global_position),"hp":actor.hp,"engine":Engine.get_version_info().string})
	var output:=FileAccess.open("res://shots/pc-input-contract.json",FileAccess.WRITE);output.store_string(JSON.stringify(report,"\t"));output.close()
	print("PC_INPUT_CONTRACT "+JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)
