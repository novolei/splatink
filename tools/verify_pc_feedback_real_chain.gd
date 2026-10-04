extends SceneTree
## Actual main scene, input events, projectiles, original audio and compositor.
## Prepared target positions are setup, never injected hit/damage events or poses.
## Image readbacks are intentional here; this harness measures no frame pacing.
const Recoil = preload("res://scripts/animation/ink_hit_recoil.gd")
const PEAK_SECONDS:float=0.0531455249188225
class RecoilPhysicsObserver:
	extends Node
	var receiver:Callable
	var before:bool=false
	func _physics_process(delta:float)->void:
		if receiver.is_valid():receiver.call(delta,before)
var game:Node
var actor:Node3D
var enemy:Node3D
var bots:RefCounted
var output:String="res://shots/pc-feedback-real"
var checks:int=0
var failures:Array[String]=[]
var observations:Array[Dictionary]=[]
var phase:String="setup"
var capture_names:Array[String]=[]
var first_hp:float=100.0
var fire_held:bool=false
var live:bool=false
var recoil_cases:Array[Dictionary]=[]
var recoil_case:Dictionary={}
var physics_observers:Array[Node]=[]
var rig_cache:Dictionary={}

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--feedback-real-output="):output=arg.trim_prefix("--feedback-real-output=")
	create_timer(50.0).timeout.connect(func():push_error("PC_FEEDBACK_REAL watchdog");quit(1))
	_run.call_deferred()

func _check(label:String,value:bool)->void:
	checks+=1
	if not value:failures.append(label);push_error("PC_FEEDBACK_REAL "+label)

func _mouse_fire(value:bool)->void:
	var event:=InputEventMouseButton.new()
	event.button_index=MOUSE_BUTTON_LEFT;event.pressed=value
	Input.parse_input_event(event);Input.flush_buffered_events();fire_held=value

func _aim_at(point:Vector3)->void:
	var camera:Camera3D=game.get("camera_rig").get("aim_camera")
	var direction:Vector3=(point-camera.global_position).normalized()
	var desired_yaw:float=atan2(direction.x,direction.z)
	var desired_pitch:float=asin(clampf(direction.y,-1.0,1.0))
	var event:=InputEventMouseMotion.new()
	event.relative=Vector2(-wrapf(desired_yaw-float(game.get("_yaw")),-PI,PI)/.0021,-(desired_pitch-float(game.get("_pitch")))/.0021)
	Input.parse_input_event(event);Input.flush_buffered_events()

func _wait(seconds:float)->void:
	await create_timer(seconds).timeout

func _reset_pair()->void:
	game.get("projectiles").call("clear")
	var stage:Node=game.get("stage")
	var p:=Vector3(0,0,-19)
	p.y=float(stage.call("ground_height",p.x,p.z,8.0))
	var q:=Vector3(0,0,-13)
	q.y=float(stage.call("ground_height",q.x,q.z,8.0))
	actor.call("spawn_at",p,0.0);enemy.call("spawn_at",q,PI)
	actor.set("invuln",0.0);enemy.set("invuln",0.0)
	game.get("camera_rig").call("follow",actor,true)
	bots.set("incoming",false)
	_mouse_fire(false)
	await _wait(.65)
	for attempt:int in 4:
		_aim_at(enemy.call("visual_position")+Vector3.UP*.9)
		await _wait(.12)

func _run()->void:
	_check("windowed renderer required",DisplayServer.get_name()!="headless")
	if not failures.is_empty():quit(1);return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output).get_base_dir())
	root.size=Vector2i(1280,720);seed(37)
	game=load("res://scenes/main.tscn").instantiate()
	game.set("_args",{"nonpersistent":true,"benchmark-background":true,"page":"online","benchmark-fps":"144"})
	root.add_child(game);current_scene=game
	game.call("apply_settings",{"quality":"high","cameraShake":1.0,"sensitivity":1.0,"invertY":false,"aimAssist":0.0,"aimAssistMouse":false})
	game.call("start_match",{"map":"tidewater","mode":"turf","duration":180,"time_of_day":"day","weapon":"shooter","palette":0})
	bots=load("res://tools/pc_feedback_target_bots.gd").new();bots.call("configure",game,"normal");game.set("bots",bots)
	await _wait(4.8)
	actor=game.get("local_player")
	for candidate in game.get("actors"):
		if candidate.get("team_id")!=actor.get("team_id"):enemy=candidate;break
	_check("production playing scene and eight actors",game.get("state")=="playing" and game.get("actors").size()==8 and enemy!=null)
	_check("real mouse capture",Input.mouse_mode==Input.MOUSE_MODE_CAPTURED)
	if not failures.is_empty():quit(1);return
	enemy.set("weapon_id","shooter");enemy.get("avatar").call("configure",enemy.call("team_color"),"shooter",enemy.get("style"));enemy.call("reset_weapon")
	bots.set("shooter",enemy);bots.set("victim",actor)
	Engine.max_fps=144;DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for before:bool in [true,false]:
		var observer:=RecoilPhysicsObserver.new()
		observer.before=before;observer.receiver=Callable(self,"_observe_physics")
		observer.process_physics_priority=-1000 if before else 1000
		root.add_child(observer);physics_observers.append(observer)
	RenderingServer.frame_post_draw.connect(_sample)
	await _reset_pair()
	_check("prepared pair grounded outside spawn barriers",actor.call("is_grounded") and enemy.call("is_grounded") and actor.global_position.distance_to(enemy.global_position)<7.0)
	_check("production targeting sees enemy",game.get("player_controller").get("on_target")==enemy)
	phase="neutral";await _capture("neutral")
	phase="ordinary_hit";first_hp=float(enemy.get("hp"));live=true
	_begin_recoil_case(enemy,actor,true)
	_mouse_fire(true)
	await _wait(.75)
	_mouse_fire(false);live=false
	_check("real mouse shot produces ordinary damage",float(enemy.get("hp"))<first_hp)
	_check("ordinary hit was captured",capture_names.has("ordinary_hit"))
	await _finish_recoil_case()
	await _wait(.6)
	await _reset_pair()
	phase="immune";first_hp=float(enemy.get("hp"));enemy.set("invuln",1.2)
	_begin_recoil_case(enemy,actor,false)
	var marker_before:float=float(game.get("_hit_until"));live=true
	_mouse_fire(true);await _wait(.6);_mouse_fire(false);live=false
	_check("invulnerable target rejects actual projectiles",float(enemy.get("hp"))==first_hp)
	_check("invulnerable target has no new confirmation",float(game.get("_hit_until"))==marker_before)
	await _capture("immune")
	await _finish_recoil_case()
	await _wait(.5);await _reset_pair()
	phase="incoming";first_hp=float(actor.get("hp"));live=true;bots.set("incoming",true)
	_begin_recoil_case(actor,enemy,true)
	await _wait(.8);bots.set("incoming",false);live=false
	_check("real bot projectile damages local player",float(actor.get("hp"))<first_hp)
	_check("incoming feedback captured",capture_names.has("incoming"))
	await _finish_recoil_case()
	await _wait(.6);await _reset_pair()
	game.call("apply_settings",{"cameraShake":0.0})
	phase="incoming_zero_shake";first_hp=float(actor.get("hp"));live=true;bots.set("incoming",true)
	_begin_recoil_case(actor,enemy,true)
	await _wait(.8);bots.set("incoming",false);live=false
	_check("zero shake retains actual damage",float(actor.get("hp"))<first_hp)
	_check("zero shake feedback captured",capture_names.has("incoming_zero_shake"))
	await _finish_recoil_case()
	RenderingServer.frame_post_draw.disconnect(_sample)
	for observer:Node in physics_observers:
		observer.set("receiver",Callable());observer.free()
	physics_observers.clear()
	_mouse_fire(false)
	var serialized_cases:Array=[]
	for original:Dictionary in recoil_cases:
		var item:Dictionary=original.duplicate()
		item.erase("victim_node");item.erase("attacker_node");item.erase("before_tick")
		serialized_cases.append(item)
	var report:Dictionary={"checks":checks,"failures":failures,"scene":game.scene_file_path,"engine":Engine.get_version_info(),"renderer":RenderingServer.get_current_rendering_method(),"observations":observations,"captures":capture_names,"recoil_cases":serialized_cases,"recoil_observation_order":"Read-only nodes at physics priority -1000/+1000 bracket real Game actor ticks and projectile damage; displayed poses sampled at frame_post_draw.","limitations":["Target positions and weapon are prepared through production spawn/configure methods.","All hits originate from real mouse input or production bot commands, not injected damage events.","Original audio players are observed; audible quality still requires listening.","Readback captures exclude this harness from frame-time comparisons.","Peak is an actual displayed 60Hz pose nearest the analytic 53.1455ms peak, not a synthesized exact-time pose.","Foot contact flags, weights and current active-anchor errors are recorded; body recoil can alter transient foot constraints. Released anchors are not treated as locked feet.","Camera aiming ray is distinct from actor muzzle-to-target convergence, which can change as the body reacts.","Offline play only; remote hit authority ACK remains outside scope."]}
	var file:=FileAccess.open(output+".json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("PC_FEEDBACK_REAL ",JSON.stringify({"checks":checks,"failures":failures,"captures":capture_names}))
	quit(0 if failures.is_empty() else 1)

func _sample()->void:
	if not live:
		_sample_recoil_render()
		return
	var hp:float=float(enemy.get("hp")) if phase=="ordinary_hit" else float(actor.get("hp"))
	if hp>=first_hp or (recoil_case.get("hit",{}) as Dictionary).is_empty() or bool(recoil_case.get("legacy_observed",false)):
		_sample_recoil_render()
		return
	if phase=="ordinary_hit":_mouse_fire(false)
	else:bots.set("incoming",false)
	var screen:Node=game.get("fx").get("screen")
	var camera:Camera3D=game.get("camera")
	var aim:Camera3D=game.get("camera_rig").get("aim_camera")
	var sounds:Array=[]
	for voice in game.get("audio").get("_ui_voices"):
		if voice.get("playing") and voice.get("stream")!=null:sounds.append({"path":voice.get("stream").resource_path,"volume_db":voice.get("volume_db"),"pitch":voice.get("pitch_scale")})
	var row:Dictionary={"phase":phase,"clock":game.get("clock"),"hp_before":first_hp,"hp_after":hp,"camera_offset_m":camera.global_position.distance_to(aim.global_position),"camera_basis_error":maxf(camera.global_basis.x.distance_to(aim.global_basis.x),maxf(camera.global_basis.y.distance_to(aim.global_basis.y),camera.global_basis.z.distance_to(aim.global_basis.z))),"hurt_uniform":screen.get("uniforms").get("uHurt",0),"saturation_pop":screen.get("s").get("satPop",0),"display_compositor_enabled":screen.get("enabled"),"ui_audio_voices":sounds,"hit_marker_remaining":float(game.get("_hit_until"))-float(game.get("clock"))}
	observations.append(row)
	if phase=="ordinary_hit":_check("native marker and audio voice in real hit",float(row.hit_marker_remaining)>0.0 and sounds.any(func(sound):return str(sound.path).ends_with("hit_marker.wav")))
	if phase=="incoming":_check("ordinary local damage has edge and camera pulse",float(row.hurt_uniform)>.1 and float(row.camera_offset_m)>.002)
	if phase=="incoming_zero_shake":_check("zero shake keeps edge without camera movement",float(row.hurt_uniform)>.1 and float(row.camera_offset_m)<.000002 and float(row.camera_basis_error)<.000002)
	recoil_case["legacy_observed"]=true
	# Observe marker/audio before a blocking readback. Ordinary pictures are saved
	# alongside the first displayed recoil peak so they cannot swallow that peak.
	_sample_recoil_render()

func _capture(name:String)->void:
	await RenderingServer.frame_post_draw
	var path:String=output+"-"+name+".png"
	var image:Image=root.get_texture().get_image()
	var error:Error=image.save_png(ProjectSettings.globalize_path(path))
	_check("capture saved "+name,error==OK)
	if error==OK:capture_names.append(name)

func _v(value:Vector3)->Array:
	return [value.x,value.y,value.z]

func _v2(value:Vector2)->Array:
	return [value.x,value.y]

func _from_v(value:Array)->Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _from_v2(value:Array)->Vector2:
	return Vector2(float(value[0]),float(value[1]))

func _body_packet(player:Node3D)->Dictionary:
	var avatar:Node3D=player.get("avatar")
	var rig:Skeleton3D=avatar.get("_skeleton")
	var helper:RefCounted=avatar.get("_hit_recoil")
	if not is_instance_valid(rig) or helper==null:return {"available":false}
	var identifier:int=player.get_instance_id()
	if not rig_cache.has(identifier):
		var indices:Dictionary={}
		for name:String in ["hips","footL","footR","thighL","shinL","toeL","thighR","shinR","toeR"]:indices[name]=rig.find_bone(name)
		rig_cache[identifier]=indices
	var bones:Dictionary=rig_cache[identifier]
	var foot:RefCounted=avatar.get("_foot_plant")
	var feet:Array=[]
	var contacts:Array=[]
	for side:int in 2:
		var bone:int=int(bones["footL" if side==0 else "footR"])
		var point:Vector3=rig.global_transform*rig.get_bone_global_pose(bone).origin
		var anchor:Vector3=foot.get("_anchor")[side]
		var active:bool=bool(foot.get("_contact")[side])
		feet.append(_v(point))
		contacts.append({"active":active,"weight":float(foot.get("_weight")[side]),"anchor":_v(anchor),"active_anchor_error_m":point.distance_to(anchor) if active else null})
	var rotations:Array=[]
	for name:String in ["thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]:
		var q:=rig.get_bone_pose_rotation(int(bones[name]))
		rotations.append([q.x,q.y,q.z,q.w])
	var camera:Camera3D=game.get("camera")
	var aim:Camera3D=game.get("camera_rig").get("aim_camera")
	var center:Vector2=root.get_visible_rect().size*.5
	var command:Dictionary=player.get("_prev")
	var offset:Vector2=helper.get("offset")
	var recoil_velocity:Vector2=helper.get("velocity")
	var last_event:Dictionary=helper.get("last_diagnostics")
	return {"available":true,"tick":Engine.get_physics_frames(),"actor_clock":float(player.get("clock")),"match_clock":float(game.get("match_clock")),"hp":float(player.get("hp")),"enemy_ink_damage_accumulator":float(player.get("_damage_from_ink")),"last_damage_age":float(player.get("_last_damage")),"grounded":player.call("is_grounded"),"form":player.get("form"),"root_position":_v(player.global_position),"root_yaw":player.rotation.y,"gameplay_velocity":_v(player.get("velocity")),"avatar_root":_v(avatar.global_position),"command_move":_v(command.get("move",Vector3.ZERO)),"helper":{"offset_m":_v2(offset),"velocity_mps":_v2(recoil_velocity),"active":bool(helper.get("active")),"trigger_count":int(helper.get("trigger_count")),"apply_count":int(helper.get("apply_count")),"offset_clamps":int(helper.get("offset_clamp_count")),"velocity_clamps":int(helper.get("velocity_clamp_count")),"last_event":last_event.get("event",""),"reported_amp":float(last_event.get("amp",0.0))},"hips_local":_v(rig.get_bone_pose_position(int(bones.hips))),"hips_world":_v(rig.global_transform*rig.get_bone_global_pose(int(bones.hips)).origin),"feet_world":feet,"contacts":contacts,"leg_rotations":rotations,"aim":{"ray_origin":_v(aim.project_ray_origin(center)),"ray_normal":_v(aim.project_ray_normal(center)),"input_yaw":float(game.get("_yaw")),"input_pitch":float(game.get("_pitch")),"actor_dir":_v(player.get("aim_dir")),"actor_point":_v(player.get("aim_point"))},"display_camera":{"ray_origin":_v(camera.project_ray_origin(center)),"ray_normal":_v(camera.project_ray_normal(center)),"aim_offset_m":camera.global_position.distance_to(aim.global_position),"aim_basis_error":maxf(camera.global_basis.x.distance_to(aim.global_basis.x),maxf(camera.global_basis.y.distance_to(aim.global_basis.y),camera.global_basis.z.distance_to(aim.global_basis.z)))},"authoritative_muzzle":_v(avatar.call("get_muzzle"))}

func _begin_recoil_case(victim:Node3D,attacker:Node3D,expect_hit:bool)->void:
	var baseline:Dictionary=_body_packet(victim)
	_check("recoil helper and original body available "+phase,bool(baseline.get("available",false)))
	recoil_case={"phase":phase,"victim_node":victim,"attacker_node":attacker,"expected_hit":expect_hit,"baseline":baseline,"physics":[],"render":[],"hit":{},"peak":{},"settled":{},"peak_capture":false,"settled_capture":false,"legacy_observed":false,"shot_command_released":false,"root_shift_maximum_m":0.0,"active_contact_error_maximum_m":0.0,"active_contact_observations":0}
	recoil_cases.append(recoil_case)
	if bool(baseline.get("available",false)):
		_check("frozen zero movement grounded pair "+phase,bool(baseline.grounded) and baseline.form=="kid" and _from_v(baseline.command_move)==Vector3.ZERO and _from_v(baseline.gameplay_velocity)==Vector3.ZERO)
		_check("body recoil settled before actual shots "+phase,_from_v2(baseline.helper.offset_m)==Vector2.ZERO and _from_v2(baseline.helper.velocity_mps)==Vector2.ZERO and not bool(baseline.helper.active))

func _observe_physics(delta:float,before:bool)->void:
	if recoil_case.is_empty():return
	var victim:Node3D=recoil_case.victim_node
	var row:Dictionary=_body_packet(victim)
	if not bool(row.get("available",false)):return
	row["physics_dt"]=delta
	if before:
		recoil_case["before_tick"]=row
		return
	# End the legal mouse/bot command after its first actual shooting tick.
	# Releasing at HP loss would leave later bullets already in flight and
	# would not isolate a single 36-damage spring impulse.
	var shooter:Node3D=recoil_case.attacker_node
	var shoot_command:Dictionary=shooter.get("_prev")
	if not bool(recoil_case.shot_command_released) and bool(shoot_command.get("fire",false)):
		if shooter==actor:_mouse_fire(false)
		else:bots.set("incoming",false)
		recoil_case.shot_command_released=true
		recoil_case["first_real_shooting_tick"]=row.tick
	(recoil_case.physics as Array).append(row)
	var baseline:Dictionary=recoil_case.baseline
	var shift:float=_from_v(row.root_position).distance_to(_from_v(baseline.root_position))
	recoil_case.root_shift_maximum_m=maxf(float(recoil_case.root_shift_maximum_m),shift)
	for contact:Dictionary in row.contacts:
		if bool(contact.active):
			recoil_case.active_contact_observations=int(recoil_case.active_contact_observations)+1
			recoil_case.active_contact_error_maximum_m=maxf(float(recoil_case.active_contact_error_maximum_m),float(contact.active_anchor_error_m))
	if (recoil_case.hit as Dictionary).is_empty() and int(row.helper.trigger_count)>int(baseline.helper.trigger_count):
		var previous:Dictionary=recoil_case.get("before_tick",baseline)
		var hp_loss:float=float(previous.hp)-float(row.hp)
		var ink_loss:float=maxf(0.0,float(row.enemy_ink_damage_accumulator)-float(previous.enemy_ink_damage_accumulator))
		var amount:float=hp_loss-ink_loss
		var attacker:Node3D=recoil_case.attacker_node
		var local:Vector3=(attacker.global_position-victim.global_position).rotated(Vector3.UP,-victim.rotation.y)
		var incoming:=Vector2(local.x,local.z).normalized()
		var expected:Vector2=-incoming*(Recoil.IMPULSE_SPEED*clampf(amount/60.0,.4,1.2))
		recoil_case.hit={"before":previous,"after":row,"actor_clock":float(row.actor_clock),"actual_damage":amount,"hp_loss_during_tick":hp_loss,"independently_observed_enemy_ink_loss_during_tick":ink_loss,"expected_initial_velocity_mps":_v2(expected)}
		if phase=="ordinary_hit":_mouse_fire(false)
		else:bots.set("incoming",false)
		_check("damage observation excludes regeneration and ink "+phase,float(previous.hp)==100.0 or float(previous.last_damage_age)+delta<=float(InkRules.player("regenDelay",1.3)))
		_check("ordinary production damage is exactly 36 "+phase,absf(amount-36.0)<.000001 and row.helper.last_event=="hit" and float(row.helper.reported_amp)==.6)
		_check("real damage triggers body recoil once "+phase,int(row.helper.trigger_count)==int(baseline.helper.trigger_count)+1)
		_check("real hit impulse matches attacker and damage "+phase,_from_v2(row.helper.velocity_mps).distance_to(expected)<.000001)
		_check("damage tick cannot displace gameplay root "+phase,row.root_position==previous.root_position and row.gameplay_velocity==previous.gameplay_velocity)
	if (recoil_case.hit as Dictionary).is_empty():return
	var elapsed:float=float(row.actor_clock)-float(recoil_case.hit.actor_clock)
	row["recoil_elapsed_seconds"]=elapsed
	if bool(row.helper.active):
		var initial:Vector2=_from_v2(recoil_case.hit.expected_initial_velocity_mps)
		var omega:float=TAU*Recoil.FREQUENCY_HZ
		var decay:float=Recoil.DAMPING_RATIO*omega
		var wd:float=omega*sqrt(1.0-Recoil.DAMPING_RATIO*Recoil.DAMPING_RATIO)
		var expected_offset:Vector2=initial*exp(-decay*elapsed)*sin(wd*elapsed)/wd
		var expected_velocity:Vector2=initial*exp(-decay*elapsed)*(cos(wd*elapsed)-decay*sin(wd*elapsed)/wd)
		row["analytic_offset_error_m"]=_from_v2(row.helper.offset_m).distance_to(expected_offset)
		row["analytic_velocity_error_mps"]=_from_v2(row.helper.velocity_mps).distance_to(expected_velocity)
		_check("actual helper keeps analytic hit time "+phase+" tick"+str(row.tick),float(row.analytic_offset_error_m)<.000001 and float(row.analytic_velocity_error_mps)<.00001)
	if elapsed>=.4 and not bool(row.helper.active) and (recoil_case.settled as Dictionary).is_empty():recoil_case.settled=row

func _sample_recoil_render()->void:
	if recoil_case.is_empty() or not bool(recoil_case.expected_hit) or (recoil_case.hit as Dictionary).is_empty():return
	var victim:Node3D=recoil_case.victim_node
	var row:Dictionary=_body_packet(victim)
	if not bool(row.get("available",false)):return
	var elapsed:float=float(row.actor_clock)-float(recoil_case.hit.actor_clock)
	row["recoil_elapsed_seconds"]=elapsed
	(recoil_case.render as Array).append(row)
	var half_tick:float=.5/float(Engine.physics_ticks_per_second)
	if not bool(recoil_case.peak_capture) and absf(elapsed-PEAK_SECONDS)<=half_tick:
		recoil_case.peak=row
		_capture_rendered([str(recoil_case.phase),str(recoil_case.phase)+"_recoil_peak"])
		recoil_case.peak_capture=true
	elif not bool(recoil_case.settled_capture) and not (recoil_case.settled as Dictionary).is_empty():
		_capture_rendered([str(recoil_case.phase)+"_recoil_settled"])
		recoil_case.settled_capture=true

func _capture_rendered(names:Array)->void:
	# Called from frame_post_draw. One readback certifies the actual presented
	# pose; aliases reuse that image, never advance/synthesize animation.
	var image:Image=root.get_texture().get_image()
	for name:String in names:
		var path:String=ProjectSettings.globalize_path(output+"-"+name+".png")
		var error:Error=image.save_png(path)
		_check("capture saved "+name,error==OK)
		if error==OK:capture_names.append(name)

func _finish_recoil_case()->void:
	if recoil_case.is_empty():return
	var victim:Node3D=recoil_case.victim_node
	if not bool(recoil_case.expected_hit):
		var immune:Dictionary=_body_packet(victim)
		_check("immune projectiles cannot trigger body recoil",int(immune.helper.trigger_count)==int(recoil_case.baseline.helper.trigger_count) and not bool(immune.helper.active) and _from_v2(immune.helper.offset_m)==Vector2.ZERO and _from_v2(immune.helper.velocity_mps)==Vector2.ZERO)
		_check("immune phase has no recoil hit event",(recoil_case.hit as Dictionary).is_empty())
		_check("immune test sent actual production firing command",bool(recoil_case.shot_command_released))
		recoil_case={}
		return
	var deadline:int=Time.get_ticks_msec()+2500
	while not bool(recoil_case.settled_capture) and Time.get_ticks_msec()<deadline:await _wait(.02)
	var label:String=str(recoil_case.phase)
	_check("actual displayed 53ms body peak captured "+label,bool(recoil_case.peak_capture) and capture_names.has(label+"_recoil_peak"))
	_check("actual settled body captured "+label,bool(recoil_case.settled_capture) and capture_names.has(label+"_recoil_settled"))
	var peak:Dictionary=recoil_case.peak
	var settled:Dictionary=recoil_case.settled
	var baseline:Dictionary=recoil_case.baseline
	_check("single production firing command observed "+label,bool(recoil_case.shot_command_released))
	if not peak.is_empty():
		var peak_offset:Vector2=_from_v2(peak.helper.offset_m)
		_check("body peak is visible thirty millimetre impulse "+label,peak_offset.length()>.029 and peak_offset.length()<.031)
		_check("body helper applies to live original rig "+label,int(peak.helper.apply_count)>int(baseline.helper.apply_count))
		var hip_change:Vector3=_from_v(peak.hips_local)-_from_v(baseline.hips_local)
		_check("actual hips move in recoil direction "+label,Vector2(hip_change.x,hip_change.z).dot(peak_offset.normalized())>peak_offset.length()*.5)
		if label=="incoming_zero_shake":
			_check("zero camera shake retains body recoil peak",peak_offset.length()>.029 and float(peak.display_camera.aim_offset_m)<.000002 and float(peak.display_camera.aim_basis_error)<.000002)
			_check("zero shake hit does not move actual aiming camera ray",_from_v(peak.aim.ray_origin).distance_to(_from_v(baseline.aim.ray_origin))<.000002 and _from_v(peak.aim.ray_normal).distance_to(_from_v(baseline.aim.ray_normal))<.000002 and float(peak.aim.input_yaw)==float(baseline.aim.input_yaw) and float(peak.aim.input_pitch)==float(baseline.aim.input_pitch))
	if not settled.is_empty():
		_check("helper sleeps with exact zero offset and velocity "+label,not bool(settled.helper.active) and _from_v2(settled.helper.offset_m)==Vector2.ZERO and _from_v2(settled.helper.velocity_mps)==Vector2.ZERO)
	_check("stationary commands prove no gameplay knockback "+label,float(recoil_case.root_shift_maximum_m)==0.0)
	_check("live active foot constraints remain inside three centimetres "+label,int(recoil_case.active_contact_observations)>0 and float(recoil_case.active_contact_error_maximum_m)<=.03)
	var final:Dictionary=_body_packet(victim)
	_check("ordinary recoil was triggered exactly once "+label,int(final.helper.trigger_count)==int(baseline.helper.trigger_count)+1)
	recoil_case={}
