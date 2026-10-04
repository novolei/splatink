extends SceneTree
## Event/authority contract with production damage, camera, screen and reticle
## methods. Empty collision casts and recorded audio replace world/audio I/O.
## This does not assess the visual or audible quality of the tuned amplitudes.

class FixtureGame:
	extends InkGame
	func _ready() -> void:pass
	func _process(_dt:float) -> void:pass
	func _physics_process(_dt:float) -> void:pass
	func cast(_from:Vector3,_to:Vector3,_exclude:Array=[],_mask:int=1) -> Dictionary:return {}
	func paint_splat(_point:Vector3,_normal:Vector3,_radius:float,_team:int,_extra:Dictionary={}) -> float:return 0.0

class FixtureActor:
	extends InkActor
	var last_controller_ray:Array[Vector3]=[]
	func controller_cast(from:Vector3,to:Vector3,_skip_grates:bool=false) -> Dictionary:
		last_controller_ray=[from,to]
		return {}
	func visual_position() -> Vector3:return global_position
	func is_grounded() -> bool:return true

class RecordedAudio:
	extends InkAudio
	var plays:Array[Dictionary]=[]
	var events:Array[String]=[]
	func _ready() -> void:pass
	func _process(_dt:float) -> void:pass
	func on_event(kind:String,_data:Dictionary) -> void:events.append(kind)
	func play(sound:String,options:Dictionary={}) -> void:
		plays.append({"name":sound,"options":options.duplicate(true)})

class EventFx:
	extends InkFx
	func on_event(kind:String,data:Dictionary) -> void:screen.on_event(kind,data)

class EventReticle:
	extends SplatHudReticle
	func _ready() -> void:pass
	func _process(_dt:float) -> void:pass

class EventUi:
	extends InkUI
	var reticle:EventReticle
	var events:Array[String]=[]
	var hit_payloads:Array[Dictionary]=[]
	func _ready() -> void:pass
	func _process(_dt:float) -> void:pass
	func on_event(kind:String,data:Dictionary) -> void:
		events.append(kind)
		if kind=="hit":hit_payloads.append(data.duplicate())
		reticle.on_event(kind,data)

class RoutedNetwork:
	extends Node
	var active:bool=true
	var applying:bool=false
	var owned_actor:Node
	var send_hit_calls:int=0
	var routed_requests:int=0
	func owns_actor(actor:Node) -> bool:return actor==owned_actor
	func send_hit(_attacker:Node,victim:Node,_amount:float,_cause:String) -> bool:
		send_hit_calls+=1
		if owns_actor(victim):return false
		routed_requests+=1
		return true
	func on_event(_kind:String,_data:Dictionary) -> void:pass

var checks:int=0
var failures:Array[String]=[]
var output:String="res://shots/pc-hit-feedback-contract.json"
var max_aim_position_error_m:float=0.0
var max_aim_basis_error:float=0.0
var max_ray_error_m:float=0.0
var max_display_position_offset_m:float=0.0
var max_display_angle_rad:float=0.0
var assist_authority_rows:Array[Dictionary]=[]
var zero_shake_pose:Dictionary={}
var panel_layout_rows:Array[Dictionary]=[]
var main_layout_only:bool=false
var layout_map:String="tidewater"
var actual_layout_map:Variant=null
var layout_effect_settings:Dictionary={}
var main_cache_rows:Array[Dictionary]=[]
var _cache_snapshot_pending:bool=false

func _initialize() -> void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--feedback-output="):output=arg.trim_prefix("--feedback-output=")
		if arg=="--feedback-main-layout":main_layout_only=true
		if arg.begins_with("--feedback-layout-map="):layout_map=arg.trim_prefix("--feedback-layout-map=")
	_run.call_deferred()

func _check(label:String,passed:bool) -> void:
	checks+=1
	if passed:return
	failures.append(label)
	if failures.size()<=8:push_error("PC_HIT_FEEDBACK_CONTRACT "+label)

func _basis_error(a:Basis,b:Basis) -> float:
	return maxf(a.x.distance_to(b.x),maxf(a.y.distance_to(b.y),a.z.distance_to(b.z)))

func _vec3(value:Vector3)->Array:
	return [value.x,value.y,value.z]

func _pose_json(value:Transform3D)->Dictionary:
	return {"origin":_vec3(value.origin),"basis_columns":[_vec3(value.basis.x),_vec3(value.basis.y),_vec3(value.basis.z)]}

func _pose_residual(a:Transform3D,b:Transform3D)->Dictionary:
	return {"exact_equal":a==b,"origin_delta_m":_vec3(a.origin-b.origin),"origin_error_m":a.origin.distance_to(b.origin),"basis_column_deltas":[_vec3(a.basis.x-b.basis.x),_vec3(a.basis.y-b.basis.y),_vec3(a.basis.z-b.basis.z)],"basis_column_error":_basis_error(a.basis,b.basis),"basis_determinants":[a.basis.determinant(),b.basis.determinant()]}

func _verify_zero_shake_pose(rig:InkCameraRig)->void:
	var displayed:Transform3D=rig.camera.global_transform
	var aimed:Transform3D=rig.aim_camera.global_transform
	# Camera3D disables scale by default. Node3D consequently orthonormalizes
	# its global basis when a copied transform becomes dirty. Reproduce that
	# exact engine copy with the same parent instead of widening a tolerance.
	var copy_probe:=Camera3D.new()
	copy_probe.name="ZeroShakeCopyProbe"
	copy_probe.current=false
	copy_probe.set_disable_scale(rig.aim_camera.is_scale_disabled())
	rig.aim_camera.get_parent().add_child(copy_probe)
	copy_probe.global_transform=displayed
	var engine_copy:Transform3D=copy_probe.global_transform
	zero_shake_pose={"display_world":_pose_json(displayed),"aim_world":_pose_json(aimed),"display_local":_pose_json(rig.camera.transform),"aim_local":_pose_json(rig.aim_camera.transform),"raw_display_minus_aim":_pose_residual(displayed,aimed),"independent_engine_copy_world":_pose_json(engine_copy),"engine_copy_minus_aim":_pose_residual(engine_copy,aimed),"display_camera_transform":_pose_json(rig.camera.get_camera_transform()),"aim_camera_transform":_pose_json(rig.aim_camera.get_camera_transform()),"display_scale_disabled":rig.camera.is_scale_disabled(),"aim_scale_disabled":rig.aim_camera.is_scale_disabled(),"display_parent_world":_pose_json((rig.camera.get_parent() as Node3D).global_transform),"aim_parent_world":_pose_json((rig.aim_camera.get_parent() as Node3D).global_transform),"camera_shake_setting":rig.game.settings.cameraShake,"shake_scale":rig.shake_scale,"trauma":rig.trauma,"trauma_in":rig._trauma_in,"damage_impulse":rig.damage_impulse,"damage_roll":rig._damage_roll,"map_open":rig.map_open,"map_k":rig.map_k,"mode":rig.mode,"blend_active":rig._blend.get("active"),"blend_time_s":rig._blend.get("t"),"blend_duration_s":rig._blend.get("duration"),"interpretation":"Raw Transform3D equality remains reported. The independent Camera3D copy must explain all basis residual exactly; no tolerance is used."}
	_check("zero shake has exact render/aim origin",displayed.origin==aimed.origin)
	_check("zero shake has no residual map transform",rig.map_k==0.0 and not rig.map_open)
	_check("zero shake has exact engine-copy render/aim pose",aimed==engine_copy)
	copy_probe.free()

func _verify_panel_layout(screen:InkScreenFx,label:String)->void:
	var panel:Control=screen.panel
	var viewport_rect:Rect2=screen.get_viewport().get_visible_rect()
	var rect:Rect2=panel.get_rect()
	var anchors:Array=[panel.anchor_left,panel.anchor_top,panel.anchor_right,panel.anchor_bottom]
	var offsets:Array=[panel.offset_left,panel.offset_top,panel.offset_right,panel.offset_bottom]
	panel_layout_rows.append({"case":label,"viewport_rect":[viewport_rect.position.x,viewport_rect.position.y,viewport_rect.size.x,viewport_rect.size.y],"panel_rect":[rect.position.x,rect.position.y,rect.size.x,rect.size.y],"anchors":anchors,"offsets":offsets,"panel_visible":panel.visible,"screen_use_compositor":screen.use_compositor,"parent_class":panel.get_parent().get_class()})
	_check(label+" full rect anchors",anchors==[0.0,0.0,1.0,1.0])
	_check(label+" zero layout offsets",offsets==[0.0,0.0,0.0,0.0])
	_check(label+" panel follows viewport rect",rect.position==Vector2.ZERO and rect.size==viewport_rect.size)

func _helper_cache_snapshot(helper:RefCounted,device:RenderingDevice)->Dictionary:
	if not helper or not device:return {"available":false,"coverage":"uncovered"}
	var entries:Dictionary=helper.get("_framebuffers")
	var context_states:Dictionary=helper.get("_framebuffer_contexts")
	var rows:Array[Dictionary]=[]
	var invalid:int=0
	for texture:RID in entries:
		var cached:Dictionary=entries[texture]
		var framebuffer:RID=cached.framebuffer
		var valid:bool=framebuffer.is_valid() and device.framebuffer_is_valid(framebuffer)
		if not valid:invalid+=1
		var context_ids:Array[String]=[]
		for id in cached.contexts:context_ids.append(str(id))
		rows.append({"output_rid":str(texture.get_id()),"framebuffer_rid":str(framebuffer.get_id()),"texture_format":cached.texture_format,"framebuffer_valid":valid,"output_texture_valid":texture.is_valid() and device.texture_is_valid(texture),"context_ids":context_ids})
	var contexts:Array[Dictionary]=[]
	for id in context_states:
		var state:Dictionary=context_states[id]
		var owner:WeakRef=state.owner
		contexts.append({"context_id":str(id),"size":[state.size.x,state.size.y],"weak_owner_available":owner!=null,"weak_owner_alive":owner.get_ref()!=null if owner else null})
	return {"available":true,"entry_count":entries.size(),"context_count":context_states.size(),"invalid_framebuffers":invalid,"entries":rows,"contexts":contexts}

func _sample_main_cache(grade:RefCounted,label:String,reflection:Dictionary)->void:
	var device:RenderingDevice=grade.get("_rd") if grade else null
	var owned_bloom:RefCounted=grade.get("_bloom") if grade else null
	var packet:Dictionary={"case":label,"grade":_helper_cache_snapshot(grade,device),"bloom":_helper_cache_snapshot(owned_bloom,device),"bloom_enabled":grade.get("bloom_enabled") if grade else null,"reflection":reflection,"scope":"read-only render-thread resource snapshot after main frame_post_draw; no GPU-present or timing measurement"}
	var grade_cache:Dictionary=packet.grade
	var bloom_cache:Dictionary=packet.bloom
	var grade_context_count:Variant=grade_cache.get("context_count")
	var bloom_context_count:Variant=bloom_cache.get("context_count")
	var matching_grade_contexts:Array[String]=[]
	var matching_bloom_contexts:Array[String]=[]
	if reflection.get("exists")==true:
		for context:Dictionary in grade_cache.get("contexts",[]):
			if context.get("size")==reflection.get("size"):matching_grade_contexts.append(str(context.context_id))
		for context:Dictionary in bloom_cache.get("contexts",[]):
			if context.get("size")==reflection.get("size"):matching_bloom_contexts.append(str(context.context_id))
	var grade_multiple:bool=grade_context_count is int and grade_context_count>1
	var bloom_multiple:bool=bloom_context_count is int and bloom_context_count>1
	packet.reflection_cache_observation={"grade_context_count":grade_context_count,"bloom_context_count":bloom_context_count,"multiple_grade_contexts_observed":grade_multiple,"multiple_bloom_contexts_observed":bloom_multiple,"grade_contexts_matching_reflection_size":matching_grade_contexts,"bloom_contexts_matching_reflection_size":matching_bloom_contexts,"multi_context_coverage":"covered" if reflection.get("exists")==true and grade_multiple and bloom_multiple else "uncovered","limitation":"A reflection viewport alone does not prove it runs these effects. Context-size matches are observations, not direct viewport attribution; one context leaves multi-context production coverage uncovered."}
	_accept_main_cache.call_deferred(packet)

func _accept_main_cache(packet:Dictionary)->void:
	main_cache_rows.append(packet)
	_cache_snapshot_pending=false

func _make_rig(game:FixtureGame,actor:FixtureActor) -> InkCameraRig:
	var display:=Camera3D.new()
	game.add_child(display)
	var rig:=InkCameraRig.new()
	game.add_child(rig)
	rig.configure(game,display)
	rig.shake_seed=4.25
	rig.follow(actor,true)
	return rig

func _compare_authority(game:FixtureGame,actor:FixtureActor,control:InkCameraRig,feedback:InkCameraRig,label:String) -> void:
	var position_error:float=control.aim_camera.global_position.distance_to(feedback.aim_camera.global_position)
	var basis_error:float=_basis_error(control.aim_camera.global_basis,feedback.aim_camera.global_basis)
	max_aim_position_error_m=maxf(max_aim_position_error_m,position_error)
	max_aim_basis_error=maxf(max_aim_basis_error,basis_error)
	_check(label+" aim transform",position_error<.000002 and basis_error<.000002)
	_check(label+" aim lens",is_equal_approx(control.aim_camera.fov,feedback.aim_camera.fov))
	game.camera_rig=control
	var base_point:Vector3=game.player_controller.compute_aim()
	var base_ray:Array[Vector3]=actor.last_controller_ray.duplicate()
	game.camera_rig=feedback
	var hit_point:Vector3=game.player_controller.compute_aim()
	var ray_error:float=maxf(base_ray[0].distance_to(actor.last_controller_ray[0]),base_ray[1].distance_to(actor.last_controller_ray[1]))
	max_ray_error_m=maxf(max_ray_error_m,ray_error)
	_check(label+" production controller ray",ray_error<.000002 and base_point.distance_to(hit_point)<.000002)
	var display_offset:float=feedback.camera.global_position.distance_to(feedback.aim_camera.global_position)
	var display_angle:float=feedback.camera.global_basis.get_rotation_quaternion().angle_to(feedback.aim_camera.global_basis.get_rotation_quaternion())
	max_display_position_offset_m=maxf(max_display_position_offset_m,display_offset)
	max_display_angle_rad=maxf(max_display_angle_rad,display_angle)
	_check(label+" bounded presentation",display_offset<=.065 and display_angle<=.05)

func _step(game:FixtureGame,control:InkCameraRig,feedback:InkCameraRig,dt:float) -> void:
	game.clock+=dt
	control.update(dt)
	feedback.update(dt)

func _assist_query_snapshot(game:FixtureGame,actor:FixtureActor,controller:InkPlayerController,rig:InkCameraRig,strength:float) -> Dictionary:
	game.camera=rig.camera;game.camera_rig=rig
	# Observe the production query without advancing the cache used by update's
	# target-motion magnetism. Score is local in production; reconstruct its
	# selected-target formula independently from the actual LOS query origin.
	var previous:Dictionary=controller.assist.duplicate()
	var candidate:Dictionary=controller.assist_target(strength).duplicate()
	controller.assist=previous
	if candidate.is_empty():return {"covered":false}
	var enemy:FixtureActor=candidate.target as FixtureActor
	var center:Vector3=enemy.visual_position()+Vector3.UP*(.3 if enemy.form=="squid" else .95)
	var query_origin:Vector3=actor.last_controller_ray[0]
	var vector:Vector3=center-query_origin
	var distance:float=vector.length()
	var angle:float=acos(clampf((vector/distance).dot(-rig.aim_camera.global_basis.z),-1.0,1.0))
	var cone:float=clampf(atan2(1.0,distance),deg_to_rad(2.5),deg_to_rad(10.0))
	var expected_closeness:float=clampf((1.0-angle/cone)*1.3,0.0,1.0)
	return {"covered":true,"target":enemy,"candidate":candidate,"selected_score_reconstructed":angle/cone+distance*.01,"friction":lerpf(1.0,.58,float(candidate.closeness)*float(candidate.strength)),"query_origin":query_origin,"closeness_matches_unshaken_geometry":float(candidate.closeness)==expected_closeness}

func _verify_assist_authority(game:FixtureGame,actor:FixtureActor,enemy:FixtureActor,control:InkCameraRig,feedback:InkCameraRig) -> void:
	var saved_settings:Dictionary=game.settings.duplicate(true)
	var saved_position:Vector3=enemy.position
	var saved_hp:float=enemy.hp
	var saved_alive:bool=enemy.alive
	var saved_invuln:float=enemy.invuln
	var saved_submerged:bool=enemy.submerged
	var saved_form:String=enemy.form
	var saved_command:Dictionary=actor._prev.duplicate(true)
	var saved_yaw:float=game._yaw
	var saved_pitch:float=game._pitch
	game.settings.cameraShake=1.0;game.settings.aimAssist=1.0
	enemy.hp=100.0;enemy.alive=true;enemy.invuln=0.0;enemy.submerged=false;enemy.form="kid"
	actor._prev={"fire":true}
	game._yaw=.23;game._pitch=-.16
	control.follow(actor,true);feedback.follow(actor,true)
	for tick:int in 60:_step(game,control,feedback,1.0/60.0)
	for device:String in ["pad","mouse"]:
		game.settings.aimAssistMouse=device=="mouse"
		for dt:float in [1.0/30.0,1.0/144.0]:
			var baseline_controller:=InkPlayerController.new()
			var feedback_controller:=InkPlayerController.new()
			baseline_controller.configure(game);feedback_controller.configure(game)
			for tick:int in 12:
				# Moving, slightly off-axis target exercises target selection,
				# non-unit friction and the previous-target yaw/pitch share.
				var aim:Camera3D=control.aim_camera
				enemy.global_position=aim.global_position-aim.global_basis.z*8.0+aim.global_basis.x*(.35+.007*tick)-Vector3.UP*.95
				feedback.damage_feedback(36.0,enemy);feedback.add_shake(.5)
				_step(game,control,feedback,dt)
				var strength:float=1.0 if device=="pad" else .5
				var label:String="assist %s %.6f %d"%[device,dt,tick]
				var base_query:Dictionary=_assist_query_snapshot(game,actor,baseline_controller,control,strength)
				var feedback_query:Dictionary=_assist_query_snapshot(game,actor,feedback_controller,feedback,strength)
				_check(label+" real enemy target covered",base_query.covered and feedback_query.covered)
				if not base_query.covered or not feedback_query.covered:continue
				_check(label+" target and complete candidate exact",base_query.target==enemy and feedback_query.target==enemy and base_query.candidate==feedback_query.candidate)
				_check(label+" selected score and LOS origin exact",base_query.selected_score_reconstructed==feedback_query.selected_score_reconstructed and base_query.query_origin==feedback_query.query_origin)
				_check(label+" unshaken score geometry",base_query.closeness_matches_unshaken_geometry and feedback_query.closeness_matches_unshaken_geometry)
				_check(label+" strength and nontrivial friction exact",base_query.candidate.strength==strength and feedback_query.candidate.strength==strength and base_query.friction==feedback_query.friction and float(base_query.friction)<1.0)
				_check(label+" visible display shake covered",feedback.camera.global_position.distance_to(feedback.aim_camera.global_position)>.004)
				var input:Dictionary={"has_pad":device=="pad","right":Vector2(.4,-.15) if device=="pad" else Vector2.ZERO,"move":Vector2(.3,0)}
				var yaw_before:float=game._yaw
				var pitch_before:float=game._pitch
				game.camera=control.camera;game.camera_rig=control
				if device=="mouse":baseline_controller.queue_mouse(Vector2(.75,-.35))
				var base_command:Dictionary=baseline_controller.update(dt,input)
				var base_yaw:float=game._yaw
				var base_pitch:float=game._pitch
				game._yaw=yaw_before;game._pitch=pitch_before
				game.camera=feedback.camera;game.camera_rig=feedback
				if device=="mouse":feedback_controller.queue_mouse(Vector2(.75,-.35))
				var feedback_command:Dictionary=feedback_controller.update(dt,input)
				_check(label+" production input yaw/pitch exact",game._yaw==base_yaw and game._pitch==base_pitch and base_command.aim_yaw==feedback_command.aim_yaw and base_command.aim_pitch==feedback_command.aim_pitch)
				_check(label+" controller command and cached assist exact",base_command==feedback_command and baseline_controller.assist==feedback_controller.assist)
				if tick>0:_check(label+" target-motion magnetism cache covered",bool(feedback_controller.assist.prev_valid))
				if device=="mouse":
					game._yaw=base_yaw;game._pitch=base_pitch
					baseline_controller.apply_mouse(Vector2(.5,-.25))
					var immediate_yaw:float=game._yaw
					var immediate_pitch:float=game._pitch
					game._yaw=base_yaw;game._pitch=base_pitch
					feedback_controller.apply_mouse(Vector2(.5,-.25))
					_check(label+" immediate mouse friction yaw/pitch exact",game._yaw==immediate_yaw and game._pitch==immediate_pitch)
				assist_authority_rows.append({"device":device,"dt_s":dt,"tick":tick,"strength":strength,"selected_score_reconstructed":base_query.selected_score_reconstructed,"friction":base_query.friction,"previous_target_valid":feedback_controller.assist.prev_valid,"display_position_offset_m":feedback.camera.global_position.distance_to(feedback.aim_camera.global_position),"yaw":game._yaw,"pitch":game._pitch})
	_check("assist all 48 paired samples written",assist_authority_rows.size()==48)
	# Existing no-rig fallback remains a gameplay camera query.
	game.camera_rig=null;game.camera=control.aim_camera
	enemy.global_position=control.aim_camera.global_position-control.aim_camera.global_basis.z*8.0-Vector3.UP*.95
	var fallback:=InkPlayerController.new();fallback.configure(game)
	var fallback_candidate:Dictionary=fallback.assist_target(1.0)
	_check("assist existing camera fallback covered",not fallback_candidate.is_empty() and fallback_candidate.target==enemy)
	game.settings=saved_settings;game._yaw=saved_yaw;game._pitch=saved_pitch
	game.camera=feedback.camera;game.camera_rig=feedback
	enemy.position=saved_position;enemy.hp=saved_hp;enemy.alive=saved_alive;enemy.invuln=saved_invuln;enemy.submerged=saved_submerged;enemy.form=saved_form
	actor._prev=saved_command

func _clear_confirmation(game:FixtureGame,screen:InkScreenFx,audio:RecordedAudio,ui:EventUi) -> void:
	game.clock+=.1;ui.reticle.clock=game.clock
	screen.reset();screen._state="playing"
	audio.plays.clear();audio.events.clear();ui.events.clear();ui.hit_payloads.clear()

func _verify_applied_hits(game:FixtureGame,actor:FixtureActor,enemy:FixtureActor,screen:InkScreenFx,audio:RecordedAudio,ui:EventUi) -> void:
	var weapons:=InkWeapons.new()
	game.add_child(weapons);weapons.match_node=game
	enemy.hp=100.0;enemy.alive=true;enemy.invuln=1.0;enemy.special_active=""
	_clear_confirmation(game,screen,audio,ui)
	var previous_marker:float=ui.reticle._hit_at
	var rejected_kill:bool=weapons.apply_hit(actor,enemy,36.0,"shooter")
	_check("invulnerable shot preserves damage rule",not rejected_kill and enemy.hp==100.0)
	_check("invulnerable shot emits no hit or damage event",ui.events.is_empty() and audio.events.is_empty())
	_check("invulnerable shot has no marker/sound/pop",ui.reticle._hit_at==previous_marker and audio.plays.is_empty() and float(screen.s.satPop)==0.0 and float(screen.s.punchV)==0.0)
	for rejected:String in ["dead","zero"]:
		_clear_confirmation(game,screen,audio,ui)
		enemy.invuln=0.0;enemy.alive=rejected!="dead"
		weapons.apply_hit(actor,enemy,0.0 if rejected=="zero" else 36.0,"shooter")
		_check(rejected+" shot emits no hit confirmation",ui.hit_payloads.is_empty() and audio.plays.is_empty() and float(screen.s.satPop)==0.0)
	enemy.alive=true;enemy.hp=100.0
	_clear_confirmation(game,screen,audio,ui)
	var normal_kill:bool=weapons.apply_hit(actor,enemy,36.0,"shooter")
	_check("normal 36 shot applies original damage",not normal_kill and enemy.hp==64.0)
	_check("normal 36 shot emits one actual hit",ui.hit_payloads.size()==1)
	if not ui.hit_payloads.is_empty():
		var hit:Dictionary=ui.hit_payloads.back()
		_check("normal hit payload is actual 36",float(hit.damage)==36.0 and float(hit.actual_damage)==36.0 and not bool(hit.predicted))
	_check("normal 36 shot reaches native marker/sound/pop",ui.reticle._hit_at==ui.reticle.clock and audio.plays.size()==1 and float(screen.s.satPop)>0.0)
	enemy.hp=100.0;enemy.special_active="slam"
	_clear_confirmation(game,screen,audio,ui)
	weapons.apply_hit(actor,enemy,90.0,"blaster")
	_check("slam protection arithmetic unchanged",enemy.hp==77.5)
	_check("reduced damage is not confirmed at requested intensity",ui.hit_payloads.size()==1 and float(ui.hit_payloads.back().damage)==22.5 and float(ui.hit_payloads.back().requested_damage)==90.0)
	enemy.hp=17.0;enemy.special_active=""
	_clear_confirmation(game,screen,audio,ui)
	var splats_before:int=actor.splats
	var deaths_before:int=enemy.deaths
	var killed:bool=weapons.apply_hit(actor,enemy,140.0,"roller")
	_check("overkill preserves death/scoring rule",killed and not enemy.alive and enemy.hp==0.0 and actor.splats==splats_before+1 and enemy.deaths==deaths_before+1)
	_check("overkill has splatted and one hit confirmation",ui.events.has("splatted") and ui.hit_payloads.size()==1)
	if not ui.hit_payloads.is_empty():
		var finish:Dictionary=ui.hit_payloads.back()
		_check("overkill reports only remaining HP removed",float(finish.damage)==17.0 and float(finish.actual_damage)==17.0 and float(finish.requested_damage)==140.0 and bool(finish.killed) and not bool(finish.predicted))
	_check("overkill retains kill marker and confirmation sound",ui.reticle._kill_at==ui.reticle.clock and audio.plays.size()==1 and float(audio.plays.back().options.volume)==1.0)
	# Only route behaviour is stubbed here. The existing wire protocol has no
	# ordinary-hit ACK; a remote prediction must never claim actual HP loss.
	var peer:=RoutedNetwork.new()
	game.add_child(peer);game.network=peer;peer.owned_actor=actor
	enemy.hp=100.0;enemy.alive=true;enemy.invuln=1.0
	_clear_confirmation(game,screen,audio,ui)
	weapons.apply_hit(actor,enemy,36.0,"shooter")
	_check("known remote invulnerability does not route or confirm",peer.send_hit_calls==0 and ui.hit_payloads.is_empty() and audio.plays.is_empty())
	enemy.invuln=0.0
	_clear_confirmation(game,screen,audio,ui)
	weapons.apply_hit(actor,enemy,36.0,"shooter")
	_check("remote damage request is routed exactly once",peer.send_hit_calls==1 and peer.routed_requests==1 and enemy.hp==100.0)
	_check("remote hit still has immediate predicted feedback",ui.hit_payloads.size()==1 and audio.plays.size()==1 and float(screen.s.satPop)>0.0)
	if not ui.hit_payloads.is_empty():
		var predicted:Dictionary=ui.hit_payloads.back()
		_check("remote prediction cannot claim actual damage",bool(predicted.predicted) and not predicted.has("actual_damage") and float(predicted.requested_damage)==36.0 and not bool(predicted.killed))
	peer.owned_actor=enemy
	_clear_confirmation(game,screen,audio,ui)
	weapons.apply_hit(actor,enemy,36.0,"shooter")
	_check("owned online victim applies real HP loss",enemy.hp==64.0 and peer.routed_requests==1 and ui.hit_payloads.size()==1)
	if not ui.hit_payloads.is_empty():_check("owned online hit is actual",not bool(ui.hit_payloads.back().predicted) and float(ui.hit_payloads.back().actual_damage)==36.0)
	game.network=null

func _run() -> void:
	if main_layout_only:
		_run_main_layout.call_deferred()
		return
	var time_scale_before:float=Engine.time_scale
	var game:=FixtureGame.new()
	root.add_child(game)
	game.state="playing"
	game.settings={"cameraShake":1.0,"reduce_motion":false,"rumble":0.0,"fov":82.0}
	game._yaw=.23;game._pitch=-.16
	game.player_controller.configure(game)
	var actor:=FixtureActor.new()
	game.add_child(actor)
	actor.is_local=true;actor.match_node=game;actor.position=Vector3(1,0,2)
	var enemy:=FixtureActor.new()
	game.add_child(enemy)
	enemy.team_id=1;enemy.match_node=game;enemy.position=Vector3(100,0,100)
	game.local_player=actor;game.actors=[actor,enemy]
	var feedback:=_make_rig(game,actor)
	var control:=_make_rig(game,actor)
	game.camera=feedback.camera;game.camera_rig=feedback
	var audio:=RecordedAudio.new()
	game.add_child(audio);game.audio=audio
	var fx:=EventFx.new()
	game.add_child(fx);game.fx=fx
	var screen:=InkScreenFx.new()
	game.add_child(screen);screen.configure(game);screen.set_quality(game.settings,1.0)
	screen._state="playing";fx.screen=screen
	var ui:=EventUi.new()
	game.add_child(ui);game.ui=ui
	ui.reticle=EventReticle.new();ui.add_child(ui.reticle);ui.reticle.configure(game)
	for tick:int in 90:_step(game,control,feedback,1.0/60.0)
	var root_before:Transform3D=actor.global_transform
	var yaw_before:float=game._yaw
	var pitch_before:float=game._pitch
	actor.damage(36.0,enemy,"shooter")
	_check("production damage rule stays 36",actor.hp==64.0)
	_check("36 damage reaches local camera immediately",feedback.damage_impulse>0.0)
	_check("36 damage reaches local screen immediately",float(screen.s.hurtImpulse)>0.0)
	_check("damage traverses central audio and UI event dispatch",audio.events.has("damage") and ui.events.has("damage"))
	_check("camera feedback does not move actor",actor.global_transform==root_before)
	for dt:float in [1.0/30.0,1.0/60.0,1.0/144.0,.05]:
		feedback.damage_impulse=0.0;feedback._damage_roll=0.0
		screen.reset();screen._state="playing";actor.hp=100.0
		game.notify_event("damage",{"victim":actor,"attacker":enemy,"amount":36.0,"source":"shooter"})
		var elapsed:float=0.0
		var previous:float=feedback.damage_impulse
		while elapsed<.4:
			_step(game,control,feedback,dt)
			screen.update(dt)
			elapsed+=dt
			_compare_authority(game,actor,control,feedback,"damage %.6f %.3f"%[dt,elapsed])
			if elapsed==dt:
				_check("36 damage is visibly present on first rendered step",feedback.camera.global_position.distance_to(feedback.aim_camera.global_position)>.004 and _basis_error(feedback.camera.global_basis,feedback.aim_camera.global_basis)>.002)
				_check("high-health damage edge reaches composite",float(screen.uniforms.uHurt)>.1)
			_check("damage envelope decays",feedback.damage_impulse<=previous)
			previous=feedback.damage_impulse
		_check("damage envelope settles by 400ms",feedback.damage_impulse==0.0 and float(screen.s.hurtImpulse)==0.0)
		_check("damage edge is independent of low-health state",float(screen.s.hurt)==0.0)
	_check("input yaw/pitch unchanged",game._yaw==yaw_before and game._pitch==pitch_before)
	_check("physics root unchanged across feedback",actor.global_transform==root_before)
	feedback.damage_impulse=0.0;feedback._damage_roll=0.0;screen.reset();screen._state="playing"
	game.notify_event("damage",{"victim":enemy,"attacker":actor,"amount":36.0,"source":"shooter"})
	_check("remote damage has no local impulse",feedback.damage_impulse==0.0 and float(screen.s.hurtImpulse)==0.0)
	for source:String in ["ink","storm"]:
		game.notify_event("damage",{"victim":actor,"attacker":enemy,"amount":.5,"source":source})
		_check(source+" continuous damage has no repeated impact kick",feedback.damage_impulse==0.0 and float(screen.s.hurtImpulse)==0.0)
	# Saturation and existing explosion shake must share the same aim invariant.
	for hit:int in 24:game.notify_event("damage",{"victim":actor,"attacker":enemy,"amount":60.0,"source":"blaster"})
	_check("damage accumulation is capped",feedback.damage_impulse<=1.0 and absf(feedback._damage_roll)<=1.0 and float(screen.s.hurtImpulse)<=.65)
	feedback.add_shake(1.0)
	for tick:int in 90:
		_step(game,control,feedback,1.0/144.0)
		_compare_authority(game,actor,control,feedback,"saturated/explosion %d"%tick)
	# These modes interpolate their previous camera position; restoring the
	# authoritative pose is essential to prevent one-frame visual feedback leaks.
	for camera_mode:String in ["orbit","spectate","overview"]:
		if camera_mode=="orbit":
			control.orbit(Vector3(2,1,3),8,3);feedback.orbit(Vector3(2,1,3),8,3)
		elif camera_mode=="spectate":
			control.spectate(actor,enemy);feedback.spectate(actor,enemy)
		else:control.overview();feedback.overview()
		for tick:int in 36:
			if tick%9==0:feedback.add_shake(.65);feedback.damage_feedback(36.0,enemy)
			_step(game,control,feedback,1.0/60.0)
			_compare_authority(game,actor,control,feedback,camera_mode+" %d"%tick)
	control.follow(actor,true);feedback.follow(actor,true)
	_check("follow snap clears damage envelope",feedback.damage_impulse==0.0 and feedback._damage_roll==0.0)
	game.settings.cameraShake=0.0
	screen.reset();screen._state="playing"
	game.notify_event("damage",{"victim":actor,"attacker":enemy,"amount":36.0,"source":"shooter"})
	feedback.add_shake(1.0)
	_step(game,control,feedback,1.0/60.0);screen.update(1.0/60.0)
	_compare_authority(game,actor,control,feedback,"zero shake")
	_verify_zero_shake_pose(feedback)
	_check("zero shake has no screen warp/chroma",float(screen.uniforms.uPunch)==0.0 and float(screen.uniforms.uChroma)==0.0)
	_check("zero shake retains damage awareness",float(screen.uniforms.uHurt)>0.0)
	var plays_before:int=audio.plays.size()
	ui.reticle.clock=game.clock
	game.notify_event("hit",{"attacker":actor,"victim":enemy,"damage":36.0,"killed":false})
	_check("ordinary hit marker arrives immediately",ui.reticle._hit_at==ui.reticle.clock and ui.reticle._hit_scale>1.0)
	_check("ordinary hit sound retains native WAV",audio.plays.size()==plays_before+1 and audio.plays.back().name=="hit_marker")
	var regular_volume:float=float(audio.plays.back().options.volume)
	game.clock+=.01;ui.reticle.clock=game.clock
	game.notify_event("hit",{"attacker":actor,"victim":enemy,"damage":36.0,"killed":false})
	_check("ordinary hit sound spam is throttled",audio.plays.size()==plays_before+1)
	game.notify_event("hit",{"attacker":actor,"victim":enemy,"damage":36.0,"killed":true})
	_check("kill sound bypasses ordinary hit throttle",audio.plays.size()==plays_before+2 and float(audio.plays.back().options.volume)>regular_volume)
	_check("kill marker is immediate",ui.reticle._kill_at==ui.reticle.clock)
	_check("no global time scaling",Engine.time_scale==time_scale_before)
	screen.reset()
	_check("screen reset clears added impulse",float(screen.s.hurtImpulse)==0.0)
	_verify_applied_hits(game,actor,enemy,screen,audio,ui)
	_verify_assist_authority(game,actor,enemy,control,feedback)
	_verify_panel_layout(screen,"production screen fixture")
	game.free()
	_finish()

func _run_main_layout()->void:
	_check("actual main layout uses windowed renderer",DisplayServer.get_name()!="headless")
	_check("requested layout map has source data",FileAccess.file_exists("res://data/%s.json"%layout_map))
	if not failures.is_empty():_finish();return
	var main_scene:PackedScene=load("res://scenes/main.tscn")
	var main_game:Node=main_scene.instantiate()
	main_game.set("_args",{"nonpersistent":true,"benchmark-background":true,"page":"online"})
	root.add_child(main_game)
	current_scene=main_game
	# QA explicitly enables the high-quality PC bloom/reflection path, rather
	# than allowing saved low-quality or disabled-bloom preferences to omit it.
	main_game.call("apply_settings",{"quality":"high","bloom":true})
	main_game.call("start_match",{"map":layout_map,"mode":"turf","duration":180,"time_of_day":"day","weapon":"shooter","palette":0})
	await create_timer(4.8).timeout
	_check("actual main enters playing",main_game.get("state")=="playing")
	var loaded_stage:Node=main_game.get("stage")
	actual_layout_map=loaded_stage.get("stage_id") if is_instance_valid(loaded_stage) else null
	_check("actual main loaded requested layout map",actual_layout_map==layout_map)
	var settings:Dictionary=main_game.get("settings")
	layout_effect_settings={"quality":settings.get("quality"),"bloom":settings.get("bloom"),"mobile_feature":OS.has_feature("mobile")}
	_check("actual main uses high quality with bloom",settings.get("quality")=="high" and settings.get("bloom")==true)
	var fx:Node=main_game.get("fx")
	var screen:InkScreenFx=fx.get("screen") if is_instance_valid(fx) else null
	_check("actual main screen exists",is_instance_valid(screen) and is_instance_valid(screen.panel))
	if is_instance_valid(screen):
		for window_size:Vector2i in [Vector2i(1280,720),Vector2i(1024,768),Vector2i(1600,900)]:
			root.size=window_size
			await process_frame
			await process_frame
			await RenderingServer.frame_post_draw
			var label:String="actual main %dx%d"%[window_size.x,window_size.y]
			_verify_panel_layout(screen,label)
			var stage:Node=main_game.get("stage")
			var environment:Node=stage.get("environment_detail") if is_instance_valid(stage) else null
			var reflection:SubViewport=environment.get("_reflection") if is_instance_valid(environment) else null
			var reflection_row:Dictionary={"exists":is_instance_valid(reflection),"size":[reflection.size.x,reflection.size.y] if is_instance_valid(reflection) else null,"update_mode":reflection.render_target_update_mode if is_instance_valid(reflection) else null}
			if layout_map=="halyard":
				_check(label+" halyard reflection viewport exists",is_instance_valid(reflection))
				_check(label+" halyard reflection viewport size valid",is_instance_valid(reflection) and reflection.size.x>0 and reflection.size.y>0)
			var grade:RefCounted=stage.get("grade") if is_instance_valid(stage) else null
			_cache_snapshot_pending=true
			RenderingServer.call_on_render_thread(_sample_main_cache.bind(grade,label,reflection_row))
			var deadline:int=Time.get_ticks_usec()+2000000
			while _cache_snapshot_pending and Time.get_ticks_usec()<deadline:await process_frame
			_check(label+" cache snapshot completed",not _cache_snapshot_pending)
			if not _cache_snapshot_pending:
				var packet:Dictionary=main_cache_rows.back()
				var grade_cache:Dictionary=packet.grade
				_check(label+" actual grade cache covered and valid",grade_cache.get("available")==true and int(grade_cache.get("entry_count",0))>0 and int(grade_cache.get("invalid_framebuffers",-1))==0)
	main_game.free()
	_finish()

func _finish() -> void:
	if not main_layout_only:_check("assisted-aim contract completed every required sample",assist_authority_rows.size()==48)
	var result:Dictionary={"version":2,"checks":checks,"failures":failures,"max_aim_position_error_m":max_aim_position_error_m,"max_aim_basis_error":max_aim_basis_error,"max_controller_ray_error_m":max_ray_error_m,"max_display_position_offset_m":max_display_position_offset_m,"max_display_angle_rad":max_display_angle_rad,"zero_shake_pose":zero_shake_pose,"panel_layout_rows":panel_layout_rows,"main_cache_rows":main_cache_rows,"main_layout_only":main_layout_only,"requested_layout_map":layout_map,"actual_layout_map":actual_layout_map,"layout_effect_settings":layout_effect_settings,"coverage":{"event_authority":not main_layout_only,"zero_shake_pose":not zero_shake_pose.is_empty(),"actual_main_layout":main_layout_only and not panel_layout_rows.is_empty()},"scope":"actual main viewport/layout and readonly RD resource snapshots only" if main_layout_only else "production apply_hit/event/damage/camera/screen/reticle methods, audio recorded and world casts empty; remote route is stubbed with no ACK, perceptual quality and live networking require real PC play","engine_copy_basis_reason":{"source_commit":"a13da4feb","camera_constructor":"https://github.com/godotengine/godot/blob/a13da4feb/scene/3d/camera_3d.cpp#L816-L824","node_global_transform":"https://github.com/godotengine/godot/blob/a13da4feb/scene/3d/node_3d.cpp#L599-L614"}}
	result.version=3
	result.assist_authority_rows=assist_authority_rows
	result.coverage.assisted_aim=not main_layout_only and assist_authority_rows.size()==48
	result.assist_score_observation="Production best_score is local, so the selected-target score formula is reconstructed from the actual LOS query origin and unshaken aim direction. The complete returned candidate, cached assist state, query origin, non-unit friction, controller command and yaw/pitch are compared exactly; no production score telemetry was added. Empty world casts and a moving fixture enemy cover semantics, not live aim-assist playability."
	var absolute:String=ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(absolute.get_base_dir())
	var file:=FileAccess.open(absolute,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(result,"\t"));file.close()
	print("PC_HIT_FEEDBACK_CONTRACT "+JSON.stringify(result))
	quit(0 if failures.is_empty() else 1)
