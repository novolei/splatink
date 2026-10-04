extends SceneTree
## Root is the sole Godot runner. Run through tools/run_godot.ps1.
## --script res://scripts/ui/tests/reticle_contract.gd -- --reticle-output=res://shots/reticle-contract
## Native GPU screenshots exercise all seven geometries plus dynamic production states.
const Reticle=preload("res://scripts/ui/hud_reticle.gd")
const Events=preload("res://scripts/ui/hud_events.gd")
const Canvas=preload("res://scripts/ui/lab_canvas.gd")
class Actor:
	extends Node3D
	var is_local:bool=true
	var team_id:int=0
	var weapon_id:String="shooter"
	var display_name:String="Reticle Probe"
	var weapon_state:Dictionary={}
	var invuln:float=0
	var aim_yaw:float=0
	var velocity:Vector3=Vector3.ZERO
class ProbeGame:
	extends Node
	var local_player:Node
	var camera:Camera3D
	var audio:Node
	var actors:Array=[]
	var team_colors:Array=[Color("ff8a14"),Color("2f5bff")]
var controller:ProbeGame
var local_actor:Actor
var reticle:SplatHudReticle
var panel:Control
var output:String="res://shots/reticle-contract"
var report:Dictionary={"checks":[],"screenshots":[],"failures":[]}

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--reticle-output="):output=argument.trim_prefix("--reticle-output=")
	_run.call_deferred()

func _run()->void:
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(1280,720)
	if DisplayServer.get_name()!="headless":DisplayServer.window_set_size(Vector2i(1280,720))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output))
	panel=Control.new();panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(panel)
	var background:ColorRect=ColorRect.new();background.color=Color("6e8899");background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_child(background)
	controller=ProbeGame.new();root.add_child(controller);local_actor=Actor.new();controller.add_child(local_actor);controller.local_player=local_actor;controller.actors=[local_actor]
	reticle=Reticle.new();panel.add_child(reticle);reticle.configure(controller);reticle.set_process(false)
	await process_frame
	var base:Dictionary={"weapon":"shooter","ink":72.0,"max_ink":100.0,"charge":0.0,"alive":true,"team_color":Color("ff8a14"),"enemy_color":Color("2f5bff"),"crosshair":{"spread":4.0,"onTarget":"none","inRange":true},"weapon_state":{},"subCost":.7,"invuln":0.0,"aim_yaw":0.0,"velocity":Vector3.ZERO,"camera_right":Vector3.RIGHT}
	for kind:String in ["shooter","blaster","roller","dualies","slosher","splatling","charger"]:
		var data:Dictionary=base.duplicate(true);data.weapon=kind;data.charge=.72 if kind in ["splatling","charger"] else 0.0
		_feed(data,.5)
		_check("%s has cached geometry"%kind,not reticle._shape.is_empty())
		_check("%s state matches"%kind,reticle.debug_state().weapon==kind)
		await _capture(kind)
	var wide:Dictionary=base.duplicate(true);wide.crosshair.spread=42.0;_feed(wide,.12)
	_check("spread receives screen pixels",absf(reticle.debug_state().spread_px-42)<.01)
	await _capture("shooter-wide")
	wide.crosshair.onTarget="enemy";wide.crosshair.inRange=false;_feed(wide,.35)
	_check("target outranks out-of-range",not reticle.debug_state().far and reticle.debug_state().target=="enemy")
	_check("target uses three sequential Gaussian shadows",reticle._shadow.filters.size()==6 and int(reticle._shadow.filters[1].get_shader_parameter("radius"))==4 and int(reticle._shadow.filters[3].get_shader_parameter("radius"))==4 and int(reticle._shadow.filters[5].get_shader_parameter("radius"))==9)
	await _capture("enemy-target")
	wide.crosshair.onTarget="none";_feed(wide,.35)
	_check("far ghosts reticle",reticle.debug_state().far and absf(reticle._opacity-.42)<.01)
	await _capture("far")
	var charged:Dictionary=base.duplicate(true);charged.weapon="charger";charged.charge=1.0;_feed(charged,.08)
	_check("charger full transition",reticle.debug_state().full and reticle.clock-reticle._flash_at<.35)
	await _capture("charger-full")
	var stream:Dictionary=base.duplicate(true);stream.weapon="splatling";stream.charge=.55;stream.weapon_state={"burst":1.2};_feed(stream,.15)
	_check("splatling streaming avoids full",not reticle.debug_state().full)
	await _capture("splatling-streaming")
	var locked:Dictionary=base.duplicate(true);locked.weapon="dualies";locked.weapon_state={"lock":.6};_feed(locked,.3)
	_check("dualies lock pulls twins inward",reticle.debug_state().lock and reticle._twins.distance_to(Vector2(-6.5,6.5))<.01)
	reticle.on_event("weapon:shot",{"actor":local_actor,"hand":0});reticle._process(.005)
	_check("right pistol independent kick",reticle.clock-reticle._hand_at.x<.02 and reticle.clock-reticle._hand_at.y>.13)
	await _capture("dualies-lock-shot")
	locked.weapon_state={"dodge":.2};_feed(locked,.3)
	_check("dualies dodge fades",absf(reticle._opacity-.45)<.01)
	await _capture("dualies-roll")
	var bucket:Dictionary=base.duplicate(true);bucket.weapon="slosher";_feed(bucket,.3);reticle.on_event("weapon:shot",{"actor":local_actor});reticle._process(.005)
	_check("slosher fire lifts arch",reticle.debug_state().kick>.9)
	await _capture("slosher-kick")
	reticle.on_event("recoil",{"actor":local_actor,"amount":.012});reticle._process(.005)
	_check("source recoil bloom",reticle.debug_state().bloom>.2)
	reticle.on_event("hit",{"attacker":local_actor,"damage":72.0,"killed":false});reticle._process(.015)
	_check("heavy hit state",reticle.debug_state().heavy and reticle.debug_state().hit_age<.05)
	await _capture("heavy-hit")
	reticle.on_event("hit",{"attacker":local_actor,"damage":36.0,"killed":true});reticle._process(.015)
	_check("kill state and combo",reticle.debug_state().kill_age<.05 and reticle.debug_state().combo==1)
	await _capture("kill")
	var shield:Dictionary=base.duplicate(true);shield.invuln=1.0;_feed(shield,1.1)
	_check("spawn shield",reticle.debug_state().shield and absf(reticle._shield_alpha-.9)<.01)
	_check("shadow surfaces remain pooled",reticle._shadow.surfaces.size()==7 and reticle._shadow.debug_state().readbacks==0)
	_check("shield owns one Gaussian layer",reticle._shield_shadow.surfaces.size()==3 and int(reticle._shield_shadow.filters[1].get_shader_parameter("radius"))==3)
	var cached_redraws:int=reticle._shadow.debug_state().mask_redraw_calls
	_feed(shield,.3)
	_check("unchanged source reticle reuses blurred mask",reticle._shadow.debug_state().mask_redraw_calls==cached_redraws)
	await _capture("spawn-shield")
	var sub:Dictionary=base.duplicate(true);sub.weapon_state={"aiming_sub":true};_feed(sub,.5)
	_check("sub aim sufficient",reticle.debug_state().sub_aim and not reticle.debug_state().sub_short)
	await _capture("sub-aim")
	sub.ink=12.0;sub.inkLow=true;_feed(sub,.05)
	_check("sub cost shortage",reticle.debug_state().sub_short)
	await _capture("sub-short-low")
	var full_ink:Dictionary=base.duplicate(true);full_ink.ink=100.0;_feed(full_ink,2.0)
	_check("full idle tank fades after 1.4sec",reticle.debug_state().tank_idle and reticle._tank_alpha<.01)
	# Production regression: Boss nodes have no is_local/team_id/weapon_id fields.
	var boss:Node3D=Node3D.new();controller.add_child(boss);boss.name="Hullbreaker"
	var view:SplatLabCanvas=Canvas.new();panel.add_child(view);view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var events:SplatHudEvents=Events.new();panel.add_child(events);events.configure(view,controller)
	_check("Boss locality safely false",not events.is_local(boss) and not reticle._local(boss))
	_check("Boss team fallback",events.team_of(boss)==1)
	events.on_event("splatted",{"victim":local_actor,"attacker":boss,"respawn":5.0})
	_check("Boss splatted event creates respawn HUD",is_instance_valid(events.respawn_card))
	reticle.on_event("splatted",{"victim":local_actor,"attacker":boss})
	await process_frame
	var file:FileAccess=FileAccess.open(output.path_join("report.json"),FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("RETICLE_CONTRACT checks=",report.checks.size()," failures=",report.failures.size()," screenshots=",report.screenshots.size())
	quit(0 if report.failures.is_empty() else 1)

func _feed(data:Dictionary,seconds:float)->void:
	reticle.update_frame(data)
	for step:int in ceili(seconds/.01):reticle._process(.01)

func _capture(name:String)->void:
	if DisplayServer.get_name()=="headless":return
	await process_frame;await RenderingServer.frame_post_draw
	var captured:Image=root.get_texture().get_image()
	if name=="far":
		var center:Color=captured.get_pixel(640,360)
		_check("GPU far opacity reaches composited pixel",maxf(maxf(center.r,center.g),center.b)<.9)
	var path:String=output.path_join(name+".png");var error:Error=captured.save_png(ProjectSettings.globalize_path(path))
	report.screenshots.append({"name":name,"path":path,"state":reticle.debug_state(),"save_error":error,"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))})
	_check("capture "+name,error==OK)

func _check(label:String,passed:bool)->void:
	report.checks.append({"label":label,"passed":passed})
	if not passed:report.failures.append(label);push_error("RETICLE_CONTRACT "+label)
