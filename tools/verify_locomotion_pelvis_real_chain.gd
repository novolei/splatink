extends SceneTree
## Observe the production app after it renders. No detached avatar, pose injection,
## movement handler calls, frame interpolation, or physics-root changes.
var game:Node
var actor:Node3D
var rig:Skeleton3D
var output:String="res://shots/locomotion-pelvis-real"
var fps:int=144
var scale:float=1.0
var capture:bool=false
var extended_turns:bool=false
var finish_time:float=12.8
var start_clock:float=0.0
var live:bool=false
var finishing:bool=false
var phase:String="idle"
var event_index:int=0
var rows:Array=[]
var physics_rows:Array=[]
var process_rows:Array=[]
var physics_observer:Node
var latest_physics:Dictionary={}
var failures:Array[String]=[]
var checks:int=0
var events:Array[Dictionary]=[
	{"t":.5,"phase":"start_forward","keys":[KEY_W]},
	{"t":2.1,"phase":"stop_forward","keys":[]},
	{"t":2.5,"phase":"start_right","keys":[KEY_D]},
	{"t":3.7,"phase":"reverse_right_left","keys":[KEY_A]},
	{"t":4.9,"phase":"stop_left","keys":[]},
	{"t":5.4,"phase":"diagonal","keys":[KEY_W,KEY_D]},
	{"t":6.6,"phase":"reverse_diagonal","keys":[KEY_S,KEY_A]},
	{"t":7.8,"phase":"stop_diagonal","keys":[]},
	{"t":8.3,"phase":"aim_walk","keys":[KEY_W],"fire":true},
	{"t":9.5,"phase":"aim_stop","keys":[],"fire":false},
	{"t":10.0,"phase":"jump","keys":[KEY_SPACE]},
	{"t":10.2,"phase":"land","keys":[]},
	{"t":11.4,"phase":"squid","keys":[KEY_SHIFT]},
	{"t":11.8,"phase":"kid_return","keys":[]},
]
var held:Array=[]
var fire_held:bool=false
var last_wall:int=0
var last_tick:int=-1
var last_root:=Vector3.ZERO
var previous_legs:Array[Quaternion]=[]
var leg_ids:=PackedInt32Array()
var foot_ids:=PackedInt32Array()
var hips_id:int=-1
var frame_intervals:Array[float]=[]
var same_tick_moving:int=0
var moving_frames:int=0
var maximum_root_step:float=0.0
var maximum_leg_step:float=0.0
var maximum_contact_error:float=0.0
var contact_samples:int=0
var input_events:Array[Dictionary]=[]
var captured:Dictionary={}
var capture_next_sample:bool=false

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--loco-output="):output=arg.trim_prefix("--loco-output=")
		if arg.begins_with("--loco-fps="):fps=clampi(int(arg.trim_prefix("--loco-fps=")),15,240)
		if arg.begins_with("--loco-scale="):scale=clampf(float(arg.trim_prefix("--loco-scale=")),.25,6.0)
		if arg=="--loco-capture":capture=true
		if arg=="--loco-extended-turns":extended_turns=true
	if extended_turns:
		finish_time=18.0
		events.append_array([
			{"t":12.9,"phase":"aim_strafe","keys":[KEY_D],"fire":true},
			{"t":13.5,"phase":"aim_mouse_90","keys":[KEY_D],"fire":true,"mouse_x":PI/.0021*.5},
			{"t":14.1,"phase":"aim_strafe_reverse","keys":[KEY_A],"fire":true},
			{"t":14.7,"phase":"aim_mouse_180","keys":[KEY_A],"fire":true,"mouse_x":-PI/.0021},
			{"t":15.5,"phase":"aim_backward","keys":[KEY_S],"fire":true},
			{"t":16.3,"phase":"aim_stop_mouse_90","keys":[],"fire":true,"mouse_x":PI/.0021*.5},
			{"t":16.9,"phase":"extended_release","keys":[],"fire":false},
		])
	_run.call_deferred()

func _check(label:String,pass_value:bool)->void:
	checks+=1
	if not pass_value:failures.append(label);push_error("LOCOMOTION_REAL "+label)

func _run()->void:
	_check("windowed renderer required",DisplayServer.get_name()!="headless")
	if not failures.is_empty():quit(1);return
	root.size=Vector2i(1280,720)
	seed(37)
	# Load the same root scene as the player, after SceneTree initialization.
	game=load("res://scenes/main.tscn").instantiate()
	game.set("_args",{"nonpersistent":true,"benchmark-background":true,"page":"online","benchmark-fps":str(fps)})
	root.add_child(game)
	current_scene=game
	game.call("apply_settings",{"quality":"low","cameraShake":0.0,"aimAssist":0.0,"aimAssistMouse":false})
	if extended_turns:game.call("apply_settings",{"sensitivity":1.0})
	game.call("start_match",{"map":"tidewater","mode":"turf","duration":180,"time_of_day":"day","weapon":"shooter","palette":0,"style":{"hair":2,"skin":3,"outfit":4,"eyes":2,"hat":0,"brows":1}})
	var quiet:RefCounted=load("res://tools/locomotion_quiet_bots.gd").new()
	quiet.call("configure",game,"normal")
	game.set("bots",quiet)
	await create_timer(4.8).timeout
	_check("real app enters playing",game.get("state")=="playing")
	_check("eight production actors",(game.get("actors") as Array).size()==8)
	actor=game.get("local_player")
	_check("local player exists",is_instance_valid(actor))
	if not failures.is_empty():quit(1);return
	var avatar:Node3D=actor.get("avatar")
	rig=avatar.get("_skeleton")
	hips_id=rig.find_bone("hips")
	for name:String in ["thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]:
		leg_ids.append(rig.find_bone(name))
		previous_legs.append(rig.get_bone_pose_rotation(leg_ids[-1]))
	foot_ids=PackedInt32Array([rig.find_bone("footL"),rig.find_bone("footR")])
	_check("original 87 bone rig",rig.get_bone_count()==87 and not leg_ids.has(-1))
	_check("real local source physics",actor.get("source_physics")!=null)
	if extended_turns:_check("production match captures mouse look",Input.mouse_mode==Input.MOUSE_MODE_CAPTURED)
	if OS.get_cmdline_user_args().has("--native-locomotion-mm"):
		_check("native lower-body provider actually active",bool(avatar.get("_native_motion_active")) and int(avatar.get("motion_state").get("native_queries",0))>0)
	Engine.max_fps=fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.time_scale=scale
	start_clock=float(game.get("match_clock"))
	last_wall=Time.get_ticks_usec()
	last_root=avatar.global_position
	physics_observer=load("res://tools/locomotion_pelvis_physics_observer.gd").new()
	root.add_child(physics_observer)
	physics_observer.call("configure",game,actor,Callable(self,"_sample_physics"))
	physics_observer.call("configure_process",Callable(self,"_sample_process"))
	live=true
	RenderingServer.frame_post_draw.connect(_sample)
	print("LOCOMOTION_REAL_BEGIN ",JSON.stringify({"scene":scene_file_path(game),"current_scene":current_scene==game,"fps_limit":fps,"scale":scale,"physics_hz":Engine.physics_ticks_per_second,"native":bool(avatar.get("_native_motion_active")),"presentation_mode":avatar.get("presentation_mode")}))

func scene_file_path(node:Node)->String:
	return node.scene_file_path

func _process(_delta:float)->bool:
	if not live or finishing or not is_instance_valid(actor):return false
	var elapsed:float=float(game.get("match_clock"))-start_clock
	while event_index<events.size() and elapsed>=float(events[event_index].t):
		var event:Dictionary=events[event_index]
		phase=event.phase
		_set_input(event.keys,bool(event.get("fire",false)))
		var yaw_before:float=float(game.get("_yaw"))
		if event.has("mouse_x"):
			var look:=InputEventMouseMotion.new()
			look.relative=Vector2(float(event.mouse_x),0.0)
			Input.parse_input_event(look)
			Input.flush_buffered_events()
			_check("real mouse look reaches controller "+phase,absf(float(game.get("_yaw"))-yaw_before)>.1)
		input_events.append({"requested_t":event.t,"applied_t":elapsed,"wall_us":Time.get_ticks_usec(),"phase":phase,"physics_frame":Engine.get_physics_frames(),"render_frame":Engine.get_process_frames(),"keys":event.keys,"fire":fire_held,"mouse_x":event.get("mouse_x",0.0),"look_yaw_before":yaw_before,"look_yaw_after":game.get("_yaw")})
		event_index+=1
	if elapsed>=finish_time:
		finishing=true
		_finish.call_deferred()
	return false

func _set_input(keys:Array,fire_value:bool)->void:
	for key:Key in held:
		if not keys.has(key):_key(key,false)
	for key:Key in keys:
		if not held.has(key):_key(key,true)
	held=keys.duplicate()
	if fire_held!=fire_value:
		var mouse:=InputEventMouseButton.new()
		mouse.button_index=MOUSE_BUTTON_LEFT;mouse.pressed=fire_value
		Input.parse_input_event(mouse)
		fire_held=fire_value
	Input.flush_buffered_events()

func _key(key:Key,pressed:bool)->void:
	var event:=InputEventKey.new()
	event.keycode=key;event.physical_keycode=key;event.pressed=pressed
	Input.parse_input_event(event)

func _sample_physics(observation:Dictionary)->void:
	if not live or finishing:return
	observation["t"]=float(observation.match_clock)-start_clock
	observation["phase"]=phase
	observation["applied_input_event_count"]=event_index
	physics_rows.append(observation)
	latest_physics=observation

func _sample_process(observation:Dictionary)->void:
	if not live or finishing:return
	observation["t"]=float(observation.match_clock)-start_clock
	observation["phase"]=phase
	observation["applied_input_event_count"]=event_index
	process_rows.append(observation)

func _sample()->void:
	if not live or finishing or not is_instance_valid(actor):return
	var now:int=Time.get_ticks_usec()
	var wall_dt:float=float(now-last_wall)/1000000.0
	last_wall=now
	var had_capture:bool=capture_next_sample
	capture_next_sample=false
	if not had_capture:frame_intervals.append(wall_dt)
	var tick:int=Engine.get_physics_frames()
	var avatar:Node3D=actor.get("avatar")
	var cam:Camera3D=game.get("camera")
	var velocity:Vector3=actor.get("velocity")
	var speed:float=Vector2(velocity.x,velocity.z).length()
	var step:float=avatar.global_position.distance_to(last_root)
	maximum_root_step=maxf(maximum_root_step,step)
	if speed>1 and actor.call("is_grounded") and actor.get("form")=="kid":
		moving_frames+=1
		if tick==last_tick:same_tick_moving+=1
	var leg_step:float=0
	var leg_rotations:Array=[]
	for i:int in leg_ids.size():
		var q:=rig.get_bone_pose_rotation(leg_ids[i])
		leg_step=maxf(leg_step,q.angle_to(previous_legs[i]))
		previous_legs[i]=q
		leg_rotations.append([q.x,q.y,q.z,q.w])
	if actor.call("is_grounded") and actor.get("form")=="kid" and phase not in ["kid_return","jump","land"]:maximum_leg_step=maxf(maximum_leg_step,leg_step)
	var contacts:RefCounted=avatar.get("_foot_plant")
	var errors:Array[float]=[-1.0,-1.0]
	var feet:Array[Vector3]=[]
	for i:int in 2:
		var point:Vector3=rig.global_transform*rig.get_bone_global_pose(foot_ids[i]).origin
		feet.append(point)
		if actor.get("form")=="kid" and actor.call("is_grounded") and bool(contacts.get("_contact")[i]) and float(contacts.get("_weight")[i])>.999:
			errors[i]=point.distance_to(contacts.get("_anchor")[i])
			maximum_contact_error=maxf(maximum_contact_error,errors[i]);contact_samples+=1
	var hips:Vector3=rig.global_transform*rig.get_bone_global_pose(hips_id).origin
	var pixel:Vector2=cam.unproject_position(hips)
	var aim_cam:Camera3D=game.get("camera_rig").get("aim_camera")
	var muzzle:Vector3=avatar.call("get_muzzle")
	var motion:Dictionary=avatar.get("motion_state")
	rows.append({"t":float(game.get("match_clock"))-start_clock,"wall_us":now,"wall_dt":wall_dt,"capture_following":had_capture,"phase":phase,"tick":tick,"physics_ticks_since_last_render":0 if last_tick<0 else tick-last_tick,"alpha":Engine.get_physics_interpolation_fraction(),"root":_v(actor.global_position),"shown_root":_v(avatar.global_position),"speed":speed,"yaw":actor.rotation.y,"hips":_v(hips),"screen":[pixel.x,pixel.y],"camera":_v(cam.global_position),"static_screen":_v2(cam.unproject_position(Vector3(0,1,0))),"aim_camera":_v(aim_cam.global_position),"aim_point":_v(actor.get("aim_point")),"muzzle":_v(muzzle),"feet":[_v(feet[0]),_v(feet[1])],"contact_error":errors,"leg_step_rad":leg_step,"leg_rotations":leg_rotations,"shown_root_step_m":step,"grounded":actor.call("is_grounded"),"form":actor.get("form"),"avatar_form":avatar.get("_form"),"avatar_form_time":avatar.get("_form_time"),"submerged":actor.get("submerged"),"firing":actor.get("firing"),"native_queries":avatar.get("motion_state").get("native_queries",0),"clip":avatar.get("motion_state").get("clip",""),"presentation_active":avatar.get("presentation_active")})
	last_tick=tick;last_root=avatar.global_position
	# Observe provider decisions without altering its query, sample clock, or pose.
	rows[-1]["motion_queries"]=motion.get("queries",0)
	rows[-1]["motion_transitions"]=motion.get("transitions",0)
	rows[-1]["matched_pose"]=motion.get("pose",-1)
	rows[-1]["motion_time"]=motion.get("time",0.0)
	rows[-1]["motion_rate"]=motion.get("rate",1.0)
	rows[-1]["hysteresis"]=motion.get("discriminative_hysteresis",{}).duplicate(true)
	rows[-1]["look_yaw"]=game.get("_yaw")
	rows[-1]["process_frame"]=Engine.get_process_frames()
	var process_packet:Dictionary=physics_observer.get("latest_process")
	rows[-1]["process_packet"]=process_packet.duplicate(true)
	rows[-1]["post_draw_process_packet_age_s"]=float(now-int(process_packet.wall_us))/1000000.0 if not process_packet.is_empty() else null
	rows[-1]["runtime_helper"]=physics_observer.call("runtime_helper_observation")
	rows[-1]["pose_observation"]=physics_observer.call("pose_observation")
	# New observations supplement the original schema. Getter muzzle above is
	# authoritative; visible FK/node sockets below are measured independently.
	var root_observation:Dictionary=physics_observer.call("render_root_observation",Engine.get_physics_interpolation_fraction())
	var socket:Dictionary=physics_observer.call("muzzle_observation")
	var contact_state:Dictionary=physics_observer.call("contact_observation")
	var contact_vectors:Array=[]
	for leg:int in 2:
		var anchor:Array=contact_state.anchor[leg]
		contact_vectors.append(_v(feet[leg]-Vector3(float(anchor[0]),float(anchor[1]),float(anchor[2]))))
	rows[-1]["root_observation"]=root_observation
	rows[-1]["actor_root_transform"]=physics_observer.call("transform_packet",actor.global_transform)
	rows[-1]["velocity"]=_v(velocity)
	rows[-1]["contacts"]=contact_state
	rows[-1]["contact_error_vectors"]=contact_vectors
	rows[-1]["muzzle_observation"]=socket
	rows[-1]["camera_transform"]=physics_observer.call("transform_packet",cam.global_transform)
	rows[-1]["camera_fov"]=cam.fov
	rows[-1]["aim_camera_transform"]=physics_observer.call("transform_packet",aim_cam.global_transform)
	rows[-1]["aim_camera_fov"]=aim_cam.fov
	rows[-1]["aim_dir"]=_v(actor.get("aim_dir"))
	rows[-1]["aim_yaw"]=actor.get("aim_yaw")
	rows[-1]["aim_pitch"]=actor.get("aim_pitch")
	rows[-1]["latest_physics_tick"]=latest_physics.get("tick",-1)
	rows[-1]["contact_state_matches_latest_physics"]=contact_state==latest_physics.get("contacts",{}) if int(latest_physics.get("tick",-1))==tick else null
	# A fixed root-local point excludes gait. Projection of the same preceding
	# world point through the current camera isolates camera movement from root
	# movement; screen values are diagnostic, not a smoothness acceptance gate.
	var fixed_point:Vector3=avatar.global_transform*Vector3(0,.64,0)
	rows[-1]["fixed_root_world"]=_v(fixed_point)
	rows[-1]["fixed_root_screen"]=_v2(cam.unproject_position(fixed_point))
	if rows.size()>1:
		var old:Array=rows[-2].get("fixed_root_world",[])
		if old.size()==3:rows[-1]["previous_fixed_root_in_current_camera"]=_v2(cam.unproject_position(Vector3(float(old[0]),float(old[1]),float(old[2]))))
	if capture and phase in ["start_forward","reverse_right_left","reverse_diagonal","aim_walk","kid_return"] and not captured.has(phase) and float(game.get("match_clock"))-start_clock>float(events[maxi(0,event_index-1)].t)+.4:
		var path:String=ProjectSettings.globalize_path(output+"-"+phase+".png")
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		root.get_texture().get_image().save_png(path)
		captured[phase]=path
		capture_next_sample=true

func _finish()->void:
	live=false
	if physics_observer!=null:physics_observer.set("enabled",false)
	_set_input([],false)
	RenderingServer.frame_post_draw.disconnect(_sample)
	_check("entire real-input timeline",event_index==events.size())
	_check("render samples recorded",rows.size()>60)
	_check("grounded moving frames observed",moving_frames>30)
	# Coverage is quality evidence. A pressure run can legitimately have no
	# moving full-weight contacts; retain its structural/authority observations.
	var moving_full:int=0
	var partial_acquisition:int=0
	var partial_release:int=0
	var stationary_full:int=0
	for row:Dictionary in rows:
		if not bool(row.grounded) or row.form!="kid":continue
		var state:Dictionary=row.contacts
		for leg:int in 2:
			var weight:float=state.weight[leg]
			if weight<=.0001:continue
			var full:bool=bool(state.contact[leg]) and weight>.999
			if float(row.speed)>1.0:
				if full:moving_full+=1
				elif bool(state.contact[leg]):partial_acquisition+=1
				else:partial_release+=1
			elif full:stationary_full+=1
	var quality_findings:Array[String]=[]
	if moving_full==0:quality_findings.append("moving full-weight FK contact coverage uncovered")
	if contact_samples<=20:quality_findings.append("legacy fully planted contact coverage insufficient")
	_check("post-game physics observer sampled",physics_rows.size()>50)
	_check("late readonly process observer sampled",not process_rows.is_empty())
	var capture_eligible:int=0
	var capture_mismatches:int=0
	for physics_row:Dictionary in physics_rows:
		var packet:Dictionary=physics_row.capture
		if not bool(packet.eligible):continue
		capture_eligible+=1
		if not bool(packet.components_exact) or not bool(packet.root_global_exact) or not bool(packet.root_local_exact) or bool(packet.packet_rendered):capture_mismatches+=1
	if capture_eligible>0:_check("physics tick packet matches exact authority components",capture_mismatches==0)
	_check("player remains alive",bool(actor.get("alive")))
	var avatar:Node3D=actor.get("avatar")
	var report:Dictionary={"diagnostic_only":true,"accepted_for_production":false,"scene":"res://scenes/main.tscn","current_scene_is_real_app":current_scene==game,"engine":Engine.get_version_info().string,"renderer":RenderingServer.get_current_rendering_method(),"native_requested":OS.get_cmdline_user_args().has("--native-locomotion-mm"),"provider":avatar.get("motion_state"),"presentation_mode":avatar.get("presentation_mode"),"fps_limit":fps,"time_scale":scale,"physics_hz":Engine.physics_ticks_per_second,"real_input_events":input_events,"sample_count":rows.size(),"moving_frames":moving_frames,"same_tick_moving_frames":same_tick_moving,"maximum_shown_root_step_m":maximum_root_step,"maximum_adjacent_render_leg_step_rad":maximum_leg_step,"fully_planted_samples":contact_samples,"maximum_world_contact_error_m":maximum_contact_error,"render_wall_intervals_without_capture_following":_stats(frame_intervals),"captures":captured,"checks":checks,"failures":failures,"samples":rows}
	report["synchronous_capture_requested"]=capture
	report["extended_mouse_turns_requested"]=extended_turns
	report["leg_order"]=["thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]
	report["physics_samples"]=physics_rows
	report["physics_sample_count"]=physics_rows.size()
	report["physics_capture_eligible_samples"]=capture_eligible
	report["physics_capture_mismatch_samples"]=capture_mismatches
	report["contact_coverage_counts"]={"moving_full":moving_full,"moving_acquisition":partial_acquisition,"moving_release":partial_release,"stationary_full":stationary_full}
	report["moving_full_contact_coverage_status"]="covered" if moving_full>0 else "uncovered"
	report["quality_findings"]=quality_findings
	report["telemetry_version"]=3
	report["process_samples"]=process_rows
	report["process_sample_count"]=process_rows.size()
	report["process_observation_order"]="Node.process_priority=1000 after Avatar.present priority=-10 and game/camera priority=0; getter observation time only"
	report["presentation_timestamp_status"]="unknown: neither Avatar.present call time nor GPU/display presentation time is measured"
	report["runtime_transform_array_layout"]="four columns: basis x/y/z vectors then origin; full affine values retained"
	report["physics_observation_order"]="Node.process_physics_priority=1000 after game priority=0; getters only, no restore/present/animation calls"
	var path:String=ProjectSettings.globalize_path(output+".json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:=FileAccess.open(path,FileAccess.WRITE)
	file.store_string(JSON.stringify(report));file.close()
	report.erase("samples")
	report.erase("physics_samples")
	report.erase("process_samples")
	print("LOCOMOTION_REAL_REPORT ",JSON.stringify(report))
	Engine.time_scale=1
	if physics_observer!=null:physics_observer.queue_free();physics_observer=null
	game.queue_free();game=null;actor=null;rig=null
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _stats(values:Array[float])->Dictionary:
	if values.is_empty():return {}
	var sorted:Array[float]=values.duplicate();sorted.sort()
	var total:float=0
	for v:float in sorted:total+=v
	return {"count":sorted.size(),"wall_fps":float(sorted.size())/total,"median_s":sorted[sorted.size()/2],"p95_s":sorted[int(sorted.size()*.95)],"max_s":sorted[-1]}

func _v(value:Vector3)->Array:return [value.x,value.y,value.z]
func _v2(value:Vector2)->Array:return [value.x,value.y]
