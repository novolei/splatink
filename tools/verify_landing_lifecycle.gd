extends SceneTree
## Integration lifecycle, using actual main/stage/Actor/Avatar source resolve.
## Explicit scene setup and controlled production Actor.tick commands; no
## injected landing, hand-edited bone pose, replaced physics or helper calls.
var checks := 0
var failures:Array[String] = []
var output := "res://shots/pc-landing-lifecycle-v3.json"
var game:Node3D
var actor:Node3D
var avatar:Node3D
var landing:RefCounted
var recoil:RefCounted
var rows:Array = []
var coverage:Dictionary = {"superjump_source_landing":false,"spawn_clear":false,"lethal_respawn_clear":false,"short_jump_abort":"uncovered"}

func _initialize() -> void:
	create_timer(120.0).timeout.connect(func():push_error("LANDING_LIFECYCLE watchdog");quit(1))
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--landing-lifecycle-output="):output=arg.trim_prefix("--landing-lifecycle-output=")
	_run.call_deferred()

func _check(label:String,passed:bool) -> void:
	checks += 1
	if passed:return
	failures.append(label)
	push_error("LANDING_LIFECYCLE " + label)

func _run() -> void:
	var packed:PackedScene = load("res://scenes/main.tscn")
	_check("late loaded production main",packed!=null)
	if packed==null:_finish();return
	game = packed.instantiate()
	game.set("_args",{"nonpersistent":true,"benchmark-background":true,"page":"online"})
	root.add_child(game)
	current_scene = game
	game.call("start_match",{"map":"tidewater","mode":"turf","duration":180,"time_of_day":"day","weapon":"shooter","palette":0})
	for frame:int in 420:
		await physics_frame
		if game.get("state")=="playing":break
	_check("production intro reaches playing with eight actors",game.get("state")=="playing" and game.get("actors").size()==8)
	if not failures.is_empty():_finish();return
	# Keep the actual scene/query/event services, while eliminating random bot
	# input and duplicate actor ticks. The controlled command loop is explicit.
	game.set_physics_process(false)
	game.set_process(false)
	game.get("projectiles").call("clear")
	actor = game.get("local_player")
	_check("production actor script",actor!=null and actor.get_script().resource_path=="res://scripts/game/ink_actor.gd")
	if actor==null:_finish();return
	avatar = actor.get("avatar")
	_check("production avatar and source physics",avatar!=null and actor.get("source_physics")!=null)
	if avatar==null or actor.get("source_physics")==null:_finish();return
	landing = avatar.get("_landing_response")
	recoil = avatar.get("_hit_recoil")
	_check("both reaction providers available",landing!=null and recoil!=null)
	if landing==null or recoil==null:_finish();return
	var stage:Node = game.get("stage")
	var origin := Vector3(0,0,-19)
	var destination := Vector3(0,0,-13)
	origin.y = float(stage.call("ground_height",origin.x,origin.z,8.0))
	destination.y = float(stage.call("ground_height",destination.x,destination.z,8.0))
	_check("finite real stage ground at both setup points",origin.is_finite() and destination.is_finite())
	if not origin.is_finite() or not destination.is_finite():_finish();return
	actor.call("spawn_at",origin,0.0)
	for frame:int in 3:await _tick()
	_check("setup grounded and pending landing clear",actor.call("is_grounded")==true and landing.get("active")==false)
	var triggers_before := int(landing.get("trigger_count"))
	var recoil_triggers_before := int(recoil.get("trigger_count"))
	_check("public super_jump accepted",actor.call("super_jump",destination)==true)
	var completed := false
	var saw_flight := false
	for frame:int in 300:
		await _tick()
		var state:Dictionary = actor.get("super_jump_state")
		if state.get("phase","")=="flight":saw_flight=true
		if state.is_empty():
			completed = true
			break
	var completion := _snapshot("superjump_completion")
	completion["trigger_count_before"] = triggers_before
	completion["public_entry"] = "InkActor.super_jump(Vector3)"
	rows.append(completion)
	_check("production charge flight and completion observed",saw_flight and completed)
	_check("source resolve reports landing",completion.source_landed==true and completion.grounded==true and float(completion.source_land_speed)>3.0)
	_check("one landing pulse survives completion presentation reset",int(completion.trigger_count)-triggers_before==1 and completion.active==true and float(completion.age)<=.1)
	_check("landing is separate from damage recoil",recoil.get("active")==false and int(recoil.get("trigger_count"))==recoil_triggers_before)
	coverage.superjump_source_landing = saw_flight and completed and completion.source_landed==true and completion.active==true and int(completion.trigger_count)-triggers_before==1
	# Prepare pending recoil only through the real damage API, then verify the
	# actual public spawn reset clears both reaction states without a new land.
	actor.set("invuln",0.0)
	var hp_before := float(actor.get("hp"))
	actor.call("damage",36.0,null,"weapon")
	_check("production damage prepares pending recoil",float(actor.get("hp"))==hp_before-36.0 and recoil.get("active")==true and landing.get("active")==true)
	var spawn_triggers := int(landing.get("trigger_count"))
	actor.call("spawn_at",origin,0.0)
	var spawn := _snapshot("spawn_reset")
	spawn["recoil_active"] = recoil.get("active")
	spawn["recoil_offset"] = _v2(recoil.get("offset"))
	spawn["recoil_velocity"] = _v2(recoil.get("velocity"))
	rows.append(spawn)
	_check("spawn clears landing and recoil exactly",spawn.active==false and landing.get("pelvis")==Vector2.ZERO and landing.get("lean_pitch")==Vector2.ZERO and landing.get("head_pitch")==Vector2.ZERO and recoil.get("active")==false and recoil.get("offset")==Vector2.ZERO and recoil.get("velocity")==Vector2.ZERO)
	_check("spawn does not add duplicate landing pulse",int(landing.get("trigger_count"))==spawn_triggers)
	coverage.spawn_clear = spawn.active==false and recoil.get("active")==false and int(landing.get("trigger_count"))==spawn_triggers
	for frame:int in 3:await _tick()
	await _normal_jump()
	await _lethal_respawn()
	_finish()

func _lethal_respawn() -> void:
	var hit:RefCounted=avatar.get("_hit")
	actor.set("invuln",0.0)
	var lethal:float=float(actor.get("hp"))+1.0
	actor.call("damage",lethal,null,"weapon")
	_check("lethal damage hides actual actor",actor.get("alive")==false and avatar.visible==false)
	_check("lethal damage prepares frozen source reaction",hit.get("active")==true)
	var values:PackedFloat32Array=hit.get("values").duplicate()
	for frame:int in 3:await _tick()
	_check("dead actor leaves source springs frozen until respawn",hit.get("values")==values and actor.get("alive")==false)
	var respawned:=false
	for frame:int in 420:
		await _tick()
		if actor.get("alive")==true:respawned=true;break
	var empty:=PackedFloat32Array()
	empty.resize(values.size())
	var catch:RefCounted=avatar.get("_catch_step")
	_check("automatic production respawn observed",respawned and avatar.visible==true)
	_check("respawn clears frozen source hit and settle",hit.get("active")==false and hit.get("values")==empty and hit.get("accumulated")==0.0 and hit.get("step_offset")==Vector2.ZERO and catch.get("active")==false and catch.get("_feet").is_empty())
	_check("respawn clears both new reactions",recoil.get("active")==false and landing.get("active")==false)
	await _tick()
	_check("first alive animation does not replay lethal reaction",hit.get("active")==false and hit.get("values")==empty and recoil.get("active")==false and catch.get("active")==false)
	coverage.lethal_respawn_clear=respawned and hit.get("active")==false and hit.get("values")==empty

func _tick(jump:bool=false) -> void:
	await physics_frame
	actor.call("tick",1.0/float(Engine.physics_ticks_per_second),{"move":Vector3.ZERO,"aim_dir":Vector3.BACK,"jump":jump,"fire":false,"swim":false})

func _normal_jump() -> void:
	var before := int(landing.get("trigger_count"))
	await _tick(true)
	var airborne:bool = actor.call("is_grounded")==false
	_check("production jump command takes off",airborne)
	var previous_action:Dictionary = {}
	var touchdown := false
	for frame:int in 180:
		previous_action = _action_state()
		await _tick(false)
		if actor.call("is_grounded")==false:airborne=true
		if airborne and actor.call("is_grounded")==true:
			touchdown=true
			break
	var row := _snapshot("normal_jump_touchdown")
	row["previous_action"] = previous_action
	row["touchdown"] = touchdown
	rows.append(row)
	_check("production ordinary touchdown observed",touchdown and int(landing.get("trigger_count"))-before==1)
	_check("touchdown gait and aim action gates open",row.grounded==true and row.action.full_body==false and avatar.get("_foot_plant").get("_was_enabled")==true)
	if previous_action.get("active",false)==true and str(previous_action.get("clip","")).ends_with("_jump"):
		coverage.short_jump_abort = "covered"
		_check("remaining jump one shot aborted at contact",row.action.active==false)
	# A naturally completed jump clip leaves this optional branch uncovered.

func _action_state() -> Dictionary:
	var tree:AnimationTree = avatar.get("_tree")
	var node:AnimationNodeOneShot = avatar.get("_action_node")
	var clip:AnimationNodeAnimation = avatar.get("_action_clip")
	var active:bool = tree.get("parameters/Action/active")==true
	return {"active":active,"clip":String(clip.animation),"full_body":active and not node.filter_enabled,"request":tree.get("parameters/Action/request")}

func _snapshot(phase:String) -> Dictionary:
	var motion:RefCounted = actor.get("_source_motion")
	return {"phase":phase,"tick":Engine.get_physics_frames(),"grounded":actor.call("is_grounded"),"source_landed":motion.get("landed"),"source_land_speed":motion.get("land_speed"),"land_speed":actor.get("land_speed"),"root_position":_v3(actor.global_position),"active":landing.get("active"),"age":landing.get("age"),"amplitude":landing.get("amplitude"),"trigger_count":landing.get("trigger_count"),"apply_count":landing.get("apply_count"),"action":_action_state()}

func _v2(value:Vector2) -> Array:return [value.x,value.y]
func _v3(value:Vector3) -> Array:return [value.x,value.y,value.z]

func _finish() -> void:
	_check("required lifecycle coverage",coverage.superjump_source_landing==true and coverage.spawn_clear==true and coverage.lethal_respawn_clear==true)
	var report := {"diagnostic_version":3,"checks":checks,"failures":failures,"coverage":coverage,"observations":rows,"scene":"res://scenes/main.tscn","physics_hz":Engine.physics_ticks_per_second,"time_scale":Engine.time_scale,"limitations":["Production scene/Actor/Avatar and source collision queries used; setup uses spawn_at and measured stage ground.","Game automatic process/physics disabled after normal intro; production Actor.tick is driven by explicit neutral/jump commands at physics_frame.","Superjump and all land events come from public actor.super_jump and production source resolve; no injected land/helper or bone pose calls.","Damage API prepares recoil solely for spawn-clear coverage; this is not projectile/input or visual feedback acceptance.","Optional short-jump ABORT is uncovered when no active jump clip remains before naturally observed touchdown.","This certifies reaction lifecycle, not final FK foot quality, aim correctness, performance or displayed frames."]}
	var file := FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("LANDING_LIFECYCLE cannot write "+output);quit(1);return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("LANDING_LIFECYCLE ",checks," checks / ",failures.size()," failures -> ",output)
	quit(0 if failures.is_empty() else 1)
