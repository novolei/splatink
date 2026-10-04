class_name SplatHudReticle
extends Control
## Production src/ui/hud.js 804–1047 + styles/hud.css 145–247, 595–598.
## Coordinates are CSS pixels, deliberately independent of the HUD's --u canvas.
## Shapes/materials/controls are reused; events only restart scalar animation clocks.
const BODY:Font=preload("res://assets/fonts/ink_body_900_font.tres")
const TANK_SHADER:Shader=preload("res://assets/ui/hud_tank.gdshader")
static var _icon_cache:Dictionary={}
static var _icon_errors:Dictionary={}
var game:Node
var frame:Dictionary={}
var clock:float=0.0
var bloom:float=0.0
var kick:float=0.0
var weapon:String="shooter"
var _drawing:Control
var _shadow:Control
var _shield_shadow:Control
var _tick_box:StyleBoxFlat
var _shield_caps:PackedVector2Array=PackedVector2Array()
var _profile_enabled:bool=false
var _process_usec:int=0
var _mask_seen:bool=false
var _mask_weapon:String=""
var _mask_color:Color
var _mask_light:Color
var _mask_state_a:Vector4
var _mask_state_b:Vector4
var _mask_twins:Vector2
var _mask_far:bool=false
var _geometry_cache_hits:int=0
var _target:bool=false
var _shape:Dictionary={}
var _dashed_shape:Dictionary={}
var _tank:ColorRect
var _tank_material:ShaderMaterial
var _low:Label
var _sub_icon:TextureRect
var _sub_label:Label
var _kill_splat:TextureRect
var _pill:StyleBoxFlat
var _bar:StyleBoxFlat
var _fill:StyleBoxFlat
var _low_style:StyleBoxFlat
var _team:Color=Color("ff8a14")
var _enemy:Color=Color("2f5bff")
var _light:Color=Color("ffbb77")
var _color:Color=Color.WHITE
var _color_from:Color=Color.WHITE
var _color_goal:Color=Color.WHITE
var _color_since:float=-1.0
var _scale:float=1.0
var _scale_from:float=1.0
var _scale_goal:float=1.0
var _scale_since:float=-1.0
var _spread:float=0.0
var _spread_from:float=0.0
var _spread_goal:float=0.0
var _spread_since:float=-1.0
var _blaster_scale:float=1.0
var _blaster_from:float=1.0
var _blaster_goal:float=1.0
var _blaster_since:float=-1.0
var _charge:float=0.0
var _charge_from:float=0.0
var _charge_goal:float=0.0
var _charge_since:float=-1.0
var _far:bool=false
var _opacity:float=1.0
var _opacity_from:float=1.0
var _opacity_goal:float=1.0
var _opacity_since:float=-1.0
var _full:bool=false
var _flash_at:float=-10.0
var _lock:bool=false
var _lock_at:float=-10.0
var _lock_from:float=0.0
var _lock_k:float=0.0
var _lock_alpha:float=0.0
var _lock_alpha_from:float=0.0
var _twins:Vector2=Vector2(-10.5,10.5)
var _twins_from:Vector2=Vector2(-10.5,10.5)
var _hand_at:Vector2=Vector2(-10,-10)
var _hit_at:float=-10.0
var _kill_at:float=-10.0
var _last_hit:float=-10.0
var _combo:int=0
var _hit_scale:float=1.0
var _heavy:bool=false
var _event_hit_at:float=-10.0
var _frame_hit:bool=false
var _frame_kill:bool=false
var _shield_at:float=-10.0
var _shield_up:bool=false
var _shield_alpha:float=0.0
var _shield_from:float=0.0
var _shield_scale:float=.7
var _shield_scale_from:float=.7
var _sub_at:float=-10.0
var _sub_on:bool=false
var _sub_alpha:float=0.0
var _sub_from:float=0.0
var _sub_scale:float=.5
var _sub_scale_from:float=.5
var _short_at:float=-10.0
var _sub_short:bool=false
var _sub_fraction:float=1.0
var _sub_cost:float=.7
var _sub_width:float=116.0
var _tank_level:float=1.0
var _tank_previous:float=1.0
var _tank_full_time:float=0.0
var _tank_alpha:float=1.0
var _tank_from:float=1.0
var _tank_idle:bool=false
var _tank_at:float=-10.0
var _tank_shift:float=0.0
var _tank_shift_from:float=0.0
var _tank_slosh:float=0.0
var _tank_velocity:float=0.0
var _tank_wobble:float=0.0
var _empty_at:float=-10.0
var _previous_yaw:float=0.0
var _yaw_valid:bool=false
var _previous_velocity:Vector3=Vector3.ZERO
var _bubbles:PackedVector4Array=PackedVector4Array()
var _bubble_count:int=0
var _rng:RandomNumberGenerator=RandomNumberGenerator.new()
var _arc_points:PackedVector2Array=PackedVector2Array()
var _arc_dashes:PackedVector2Array=PackedVector2Array()

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_drawing=self
	for argument:String in OS.get_cmdline_user_args():
		if argument.trim_prefix("--").split("=",true,1)[0]=="profile-render":_profile_enabled=true
	_rng.seed=0x494e4b
	_cache_shapes()
	_tick_box=StyleBoxFlat.new();_tick_box.set_corner_radius_all(2);_tick_box.corner_detail=8;_tick_box.anti_aliasing=true;_tick_box.anti_aliasing_size=.5
	_bubbles.resize(14)
	_tank_material=ShaderMaterial.new();_tank_material.shader=TANK_SHADER
	_tank=ColorRect.new();_tank.mouse_filter=Control.MOUSE_FILTER_IGNORE;_tank.material=_tank_material;_tank.size=Vector2(18,76);add_child(_tank)
	_low_style=StyleBoxFlat.new();_low_style.bg_color=Color("ff3d5e");_low_style.border_color=Color("15121c");_low_style.set_border_width_all(2);_low_style.set_corner_radius_all(12);_low_style.content_margin_left=7;_low_style.content_margin_right=7;_low_style.content_margin_top=3;_low_style.content_margin_bottom=3
	_low=_label("LOW INK");_low.add_theme_stylebox_override("normal",_low_style);_low.size=Vector2(64,17);_low.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_low.hide();add_child(_low)
	_pill=StyleBoxFlat.new();_pill.bg_color=Color(.055,.043,.086,.82);_pill.border_color=Color(1,1,1,.14);_pill.set_border_width_all(2);_pill.set_corner_radius_all(16);_pill.shadow_color=Color(0,0,0,.3);_pill.shadow_size=0;_pill.shadow_offset=Vector2(0,3)
	_bar=StyleBoxFlat.new();_bar.bg_color=Color(1,1,1,.15);_bar.set_corner_radius_all(4)
	_fill=StyleBoxFlat.new();_fill.set_corner_radius_all(4)
	_sub_icon=TextureRect.new();_sub_icon.texture=preload("res://assets/ui/source/sub_bomb.svg");_sub_icon.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_sub_icon.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_sub_icon.mouse_filter=Control.MOUSE_FILTER_IGNORE;_sub_icon.size=Vector2(22,22);add_child(_sub_icon)
	_sub_label=_label("70%");_sub_label.size=Vector2(31,22);_sub_label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER;add_child(_sub_label)
	_kill_splat=TextureRect.new();_kill_splat.texture=preload("res://assets/ui/source/splat_icon.svg");_kill_splat.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_kill_splat.stretch_mode=TextureRect.STRETCH_KEEP_ASPECT_CENTERED;_kill_splat.mouse_filter=Control.MOUSE_FILTER_IGNORE;_kill_splat.size=Vector2(48,48);_kill_splat.pivot_offset=Vector2(24,24);_kill_splat.hide();add_child(_kill_splat)
	_shadow=preload("res://scripts/ui/hud_reticle_shadow.gd").new();_shadow.show_behind_parent=true;add_child(_shadow);move_child(_shadow,0);_shadow.configure(self)
	# Shield has its own source filter, unaffected by the target's white shadow stack.
	_shield_shadow=preload("res://scripts/ui/hud_reticle_shadow.gd").new();add_child(_shield_shadow);move_child(_shield_shadow,1);_shield_shadow.configure(self,&"paint_shield_mask",1);_shield_shadow.hide()
	_layout_children()

func configure(controller:Node)->void:
	game=controller

func update_frame(value:Dictionary)->void:
	frame=value
	var next_weapon:String=str(frame.get("weapon","shooter"))
	if next_weapon!=weapon:
		weapon=next_weapon;_full=false;_spread_goal=0;_charge_goal=0;_frame_hit=false;_frame_kill=false
	var team:Color=frame.get("team_color",Color("ff8a14"))
	if team!=_team or not _sub_icon.has_meta("ink"):
		_sub_icon.texture=_colored_icon("sub_bomb","#ff8a14",team)
		_kill_splat.texture=_colored_icon("splat_icon","#ffffff",team)
		_sub_icon.set_meta("ink",true)
	_team=team;_enemy=frame.get("enemy_color",Color("2f5bff"));_light=_team.lerp(Color.WHITE,.45)
	# Compatibility with fixtures and old frame booleans: never restart on every held frame.
	var hit:bool=bool(frame.get("hit",false));var killed:bool=bool(frame.get("kill",false))
	if clock-_event_hit_at>.12:
		if killed and not _frame_kill:hit_marker(true,float(frame.get("hit_damage",36)))
		elif hit and not _frame_hit:hit_marker(false,float(frame.get("hit_damage",36)))
	_frame_hit=hit;_frame_kill=killed

func _local(candidate:Variant)->bool:
	if candidate is Node:
		if not is_instance_valid(candidate):return false
		var flag:Variant=candidate.get("is_local")
		return flag!=null and bool(flag)
	if candidate is Dictionary:return bool(candidate.get("isSelf",candidate.get("is_local",false)))
	return false

func on_event(kind:String,data:Dictionary)->void:
	if kind=="recoil" and (not data.has("actor") or _local(data.get("actor"))):
		bloom=minf(1,bloom+.18+float(data.get("amount",0))*6);_tank_wobble=minf(1,_tank_wobble+.25)
	elif kind in ["weapon:fire","weapon:shot","weapon:flick","weapon:beam"] and _local(data.get("actor")):
		kick=1;_tank_wobble=minf(1,_tank_wobble+.06)
		if weapon=="dualies":
			if int(data.get("hand",0))!=0:_hand_at.y=clock
			else:_hand_at.x=clock
	elif kind=="hit" and _local(data.get("attacker")):
		_event_hit_at=clock;hit_marker(bool(data.get("killed",false)),float(data.get("damage",36)))
	elif kind=="splatted" and _local(data.get("attacker")) and not _local(data.get("victim")):
		if clock-_event_hit_at>.03:_event_hit_at=clock;hit_marker(true,float(data.get("damage",36)))
		else:_kill_at=clock
	elif kind in ["lowink","low_ink","ink:empty"] and _local(data.get("actor")):_empty_at=clock

func hit_marker(killed:bool=false,damage:float=36)->void:
	_combo=mini(_combo+1,6) if clock-_last_hit<.55 else 0
	_last_hit=clock;_hit_at=clock;_heavy=damage>=60
	_hit_scale=clampf(.8+damage/90,.8,1.6)*(1+_combo*.06)
	if killed:_kill_at=clock

func _process(dt:float)->void:
	if not is_visible_in_tree():return
	var process_started:int=Time.get_ticks_usec() if _profile_enabled else 0
	clock+=dt;bloom=maxf(0,bloom-dt*5);kick=maxf(0,kick-dt*16)
	var state:Dictionary=frame.get("weapon_state",{})
	var actor:Node=game.get("local_player") if is_instance_valid(game) else null
	if state.is_empty() and is_instance_valid(actor) and actor.get("weapon_state") is Dictionary:state=actor.get("weapon_state")
	var alive:bool=bool(frame.get("alive",float(frame.get("respawn",0))<=0))
	var ch:Dictionary=frame.get("crosshair",{})
	var target:bool=str(ch.get("onTarget",""))=="enemy"
	_target=target
	_far=not bool(ch.get("inRange",true)) and not target
	var streaming:bool=bool(state.get("streaming",float(state.get("burst",0))>0))
	var charge:float=clampf(float(frame.get("charge",0)),0,1)
	var lock:bool=float(state.get("lock",0))>0
	var roll:bool=bool(state.get("dodge",false))
	var full:bool=charge>=.999 and not (weapon=="splatling" and streaming)
	if weapon in ["charger","splatling"] and full!=_full:
		_full=full
		if full:_flash_at=clock
	if weapon in ["shooter","blaster","dualies","splatling"]:
		var spread:float=clampf(float(ch.get("spread",0))+bloom*(5 if weapon=="blaster" else 2.5)+(0 if weapon=="blaster" else kick*kick*(4 if weapon=="splatling" else 7)),0,90)
		if absf(spread-_spread_goal)>.25:
			_spread_from=_spread;_spread_goal=spread;_spread_since=clock
			_blaster_from=_blaster_scale;_blaster_goal=1+spread*.012;_blaster_since=clock
	_spread=lerpf(_spread_from,_spread_goal,_progress(_spread_since,.06,"linear"))
	_blaster_scale=lerpf(_blaster_from,_blaster_goal,_progress(_blaster_since,.1,"linear"))
	if absf(charge-_charge_goal)>.004:_charge_from=_charge;_charge_goal=charge;_charge_since=clock
	_charge=lerpf(_charge_from,_charge_goal,_progress(_charge_since,.05,"linear"))
	var color_goal:Color=_light if (weapon=="charger" and _full) or (weapon=="dualies" and lock) or (weapon=="splatling" and streaming) else _enemy if target else Color.WHITE
	# .is-target appears before .is-full/.is-lock in CSS but is more specific.
	if target:color_goal=_enemy
	if color_goal!=_color_goal:_color_from=_color;_color_goal=color_goal;_color_since=clock
	_color=_color_from.lerp(_color_goal,_progress(_color_since,.12,"ease"))
	var scale_goal:float=1.14 if target else 1+bloom*.14 if weapon in ["roller","charger","slosher"] else 1.0
	if absf(scale_goal-_scale_goal)>.0028:_scale_from=_scale;_scale_goal=scale_goal;_scale_since=clock
	_scale=lerpf(_scale_from,_scale_goal,_progress(_scale_since,.25,"spring"))
	var alpha_goal:float=.42 if _far else .45 if weapon=="dualies" and roll else 1.0
	if alpha_goal!=_opacity_goal:_opacity_from=_opacity;_opacity_goal=alpha_goal;_opacity_since=clock
	_opacity=lerpf(_opacity_from,_opacity_goal,_progress(_opacity_since,.2,"ease"))
	if lock!=_lock:
		_lock_from=_lock_k;_lock_alpha_from=_lock_alpha;_twins_from=_twins;_lock=lock;_lock_at=clock
	_lock_k=lerpf(_lock_from,1.0 if lock else 0.0,_progress(_lock_at,.22,"spring"))
	_lock_alpha=lerpf(_lock_alpha_from,1.0 if lock else 0.0,_progress(_lock_at,.12,"ease"))
	_twins=_twins_from.lerp(Vector2(-6.5,6.5) if lock else Vector2(-10.5,10.5),_progress(_lock_at,.18,"spring"))
	var invuln:float=float(frame.get("invuln",actor.get("invuln") if is_instance_valid(actor) else 0))
	var shield:bool=alive and invuln>.05
	if shield!=_shield_up:_shield_from=_shield_alpha;_shield_scale_from=_shield_scale;_shield_up=shield;_shield_at=clock
	_shield_alpha=lerpf(_shield_from,.9 if shield else 0.0,_progress(_shield_at,.3,"ease"))
	_shield_scale=lerpf(_shield_scale_from,1.0 if shield else .7,_progress(_shield_at,.4,"spring"))
	var sub:bool=(alive and bool(state.get("aiming_sub",false))) or bool(frame.get("subAim",false))
	if sub!=_sub_on:
		_sub_from=_sub_alpha;_sub_scale_from=_sub_scale;_sub_on=sub;_sub_at=clock
		if sub and is_instance_valid(game) and game.get("audio") is Node:game.audio.play("ui_toggle",{"volume":.35})
	_sub_alpha=lerpf(_sub_from,1.0 if sub else 0.0,_progress(_sub_at,.15,"ease"))
	_sub_scale=lerpf(_sub_scale_from,1.0 if sub else .5,_progress(_sub_at,.3,"spring"))
	_sub_cost=clampf(float(frame.get("subCost",.7)),0,1)
	var ink:float=clampf(float(frame.get("ink",100))/maxf(1,float(frame.get("max_ink",100))),0,1)
	_sub_fraction=clampf(ink/maxf(.01,_sub_cost),0,1)
	var insufficient:bool=ink<_sub_cost-.001
	if insufficient and not _sub_short:_short_at=clock
	_sub_short=insufficient
	_update_tank(dt,ink,actor)
	_layout_children()
	_update_shadow()
	if _mask_changed():_shadow.redraw_mask()
	else:_geometry_cache_hits+=1
	_shield_shadow.visible=_shield_alpha>.001
	if _shield_shadow.visible:
		_shield_shadow.set_stack([{"sigma":1.0,"color":Color("15121c")}])
		_shield_shadow.output.modulate.a=_shield_alpha
		_shield_shadow.redraw_mask()
	queue_redraw()
	if process_started:_process_usec=Time.get_ticks_usec()-process_started

func _mask_changed()->bool:
	var state_a:Vector4=Vector4(_scale,_spread,_charge,_blaster_scale)
	var state_b:Vector4=Vector4(_lock_k,_lock_alpha,kick if weapon=="slosher" else 0,0)
	var animated:bool=clock-_hit_at<.18 or clock-_kill_at<.45 or clock-_flash_at<.35 or (weapon=="dualies" and (clock-_hand_at.x<.13 or clock-_hand_at.y<.13))
	var changed:bool=not _mask_seen or animated or weapon!=_mask_weapon or _color!=_mask_color or _light!=_mask_light or state_a!=_mask_state_a or state_b!=_mask_state_b or _twins!=_mask_twins or _far!=_mask_far
	_mask_seen=true;_mask_weapon=weapon;_mask_color=_color;_mask_light=_light;_mask_state_a=state_a;_mask_state_b=state_b;_mask_twins=_twins;_mask_far=_far
	return changed

func profile_metrics()->Dictionary:
	var reticle:Dictionary=_shadow.profile_metrics();var shield:Dictionary=_shield_shadow.profile_metrics()
	return {"reticle_process_cpu_ms":_process_usec/1000.0 if is_visible_in_tree() else 0.0,"reticle_helper_process_cpu_ms":reticle.process_cpu_ms,"shield_helper_process_cpu_ms":shield.process_cpu_ms,"reticle_mask_draw_cpu_ms":reticle.mask_draw_cpu_ms,"shield_mask_draw_cpu_ms":shield.mask_draw_cpu_ms,"reticle_aux_gpu_last_ms":reticle.gpu_last_ms+shield.gpu_last_ms,"reticle_aux_cpu_last_ms":reticle.cpu_last_ms+shield.cpu_last_ms,"reticle_aux_gpu_recent_ms":reticle.gpu_recent_ms+shield.gpu_recent_ms,"reticle_aux_cpu_recent_ms":reticle.cpu_recent_ms+shield.cpu_recent_ms,"reticle_aux_surface_count":reticle.surface_count+shield.surface_count,"reticle_aux_requested_surfaces":reticle.requested_surface_count+shield.requested_surface_count,"reticle_geometry_cache_hits":_geometry_cache_hits,"reticle_filter_cache_hits":reticle.cache_hits,"reticle_filter_render_batches":reticle.render_batches,"shield_filter_render_batches":shield.render_batches}

func _update_tank(dt:float,ink:float,actor:Node)->void:
	var low:bool=bool(frame.get("inkLow",ink<.18))
	_tank_full_time=_tank_full_time+dt if ink>=.995 and not low and not _sub_on else 0.0
	var idle:bool=_tank_full_time>1.4
	if idle!=_tank_idle:_tank_from=_tank_alpha;_tank_shift_from=_tank_shift;_tank_idle=idle;_tank_at=clock
	_tank_alpha=lerpf(_tank_from,0.0 if idle else 1.0,_progress(_tank_at,.4,"ease"))
	_tank_shift=lerpf(_tank_shift_from,-6.0 if idle else 0.0,_progress(_tank_at,.4,"out"))
	var drive:float=0
	var yaw:Variant=frame.get("aim_yaw",actor.get("aim_yaw") if is_instance_valid(actor) else null)
	if yaw!=null:
		if _yaw_valid and dt>0:drive+=clampf(wrapf(float(yaw)-_previous_yaw,-PI,PI)/dt,-8,8)*.55
		_previous_yaw=float(yaw);_yaw_valid=true
	var velocity:Vector3=frame.get("velocity",actor.get("velocity") if is_instance_valid(actor) else Vector3.ZERO)
	if dt>0:
		var right:Vector3=frame.get("camera_right",Vector3.RIGHT)
		if not frame.has("camera_right") and is_instance_valid(game) and game.get("camera") is Camera3D:right=game.camera.global_basis.x
		drive+=clampf(((velocity-_previous_velocity)/dt).dot(Vector3(right.x,0,right.z))*.05,-3,3)
	_previous_velocity=velocity
	# Stable substeps retain the original 90/7.5 spring on slow frames.
	var steps:int=maxi(1,ceili(dt/.0167));var step:float=dt/steps
	for index:int in steps:
		_tank_velocity+=(-90*_tank_slosh-7.5*_tank_velocity-drive*6)*step
		_tank_slosh=clampf(_tank_slosh+_tank_velocity*step,-.6,.6)
	_tank_wobble=maxf(0,_tank_wobble-dt*1.8)
	if ink>_tank_previous+.0001 and _bubble_count<14 and _rng.randf()<dt*(40 if ink-_tank_previous>dt*.2 else 12):
		_bubbles[_bubble_count]=Vector4(.2+_rng.randf()*.6,0,.6+_rng.randf()*1.4,.5+_rng.randf()*.7);_bubble_count+=1
	_tank_previous=ink;_tank_level+=(ink-_tank_level)*(1-exp(-dt*14))
	for index:int in range(_bubble_count-1,-1,-1):
		var bubble:Vector4=_bubbles[index];bubble.y+=bubble.w*dt
		if 73-bubble.y*70<3+70*(1-_tank_level)+2:
			_bubble_count-=1;_bubbles[index]=_bubbles[_bubble_count];_bubbles[_bubble_count]=Vector4.ZERO
		else:_bubbles[index]=bubble
	_tank_material.set_shader_parameter("ink_color",_team)
	_tank_material.set_shader_parameter("level",_tank_level)
	_tank_material.set_shader_parameter("slosh",_tank_slosh)
	_tank_material.set_shader_parameter("slosh_velocity",_tank_velocity)
	_tank_material.set_shader_parameter("wobble",_tank_wobble)
	_tank_material.set_shader_parameter("clock",clock)
	_tank_material.set_shader_parameter("sub_cost",_sub_cost)
	_tank_material.set_shader_parameter("short_ink",ink<_sub_cost)
	_tank_material.set_shader_parameter("low_ink",low)
	_tank_material.set_shader_parameter("bubble_count",_bubble_count)
	_tank_material.set_shader_parameter("bubbles",_bubbles)
	_low.visible=low

func _layout_children()->void:
	var center:Vector2=size*.5
	if _shadow:_shadow.position=center-Vector2(192,192)
	if _shield_shadow:_shield_shadow.position=center-Vector2(192,192)
	var tank_x:float=82 if weapon=="roller" else 66 if weapon=="charger" else 50
	var empty:float=clampf(1-(clock-_empty_at)/.35,0,1)
	_tank.position=center+Vector2(tank_x+_tank_shift+sin((clock-_empty_at)*100)*3*empty,-38);_tank.modulate.a=_tank_alpha
	_low.position=_tank.position+Vector2(9-_low.size.x*.5,83);_low.pivot_offset=_low.size*.5;_low.scale=Vector2.ONE*(1+.12*(.5-.5*cos(clock*TAU/.9)));_low.modulate.a=_tank_alpha
	_sub_label.text="%d%%"%roundi(_sub_cost*100);_sub_width=4+22+6+46+6+BODY.get_string_size(_sub_label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,11).x+9
	var origin:Vector2=center+Vector2(-22-_sub_width,44)
	if _sub_short and clock-_short_at<.3:origin.x+=sin((clock-_short_at)*100)*3*maxf(0,1-(clock-_short_at)/.3)
	_sub_icon.position=origin+Vector2(4,3);_sub_icon.pivot_offset=Vector2(_sub_width*.5-4,11);_sub_icon.scale=Vector2.ONE*_sub_scale;_sub_icon.modulate=Color(1,1,1,_sub_alpha)
	_sub_label.position=origin+Vector2(84,3);_sub_label.pivot_offset=Vector2(_sub_width*.5-84,11);_sub_label.scale=Vector2.ONE*_sub_scale;_sub_label.modulate=Color(Color("ff7a8c") if _sub_short else Color.WHITE,_sub_alpha)
	var splat_t:float=clock-_kill_at
	_kill_splat.visible=splat_t<.8
	if _kill_splat.visible:
		var splat_scale:float=lerpf(.2,1.25,_bezier(clampf(splat_t/.16,0,1),.26,1.9,.5,1)) if splat_t<.16 else lerpf(1.25,1,_bezier(clampf((splat_t-.16)/.12,0,1),.26,1.9,.5,1)) if splat_t<.28 else 1.0
		_kill_splat.position=center+Vector2(-24,-92-10*clampf((splat_t-.6)/.2,0,1));_kill_splat.scale=Vector2.ONE*splat_scale;_kill_splat.rotation=lerpf(deg_to_rad(-40),0,clampf(splat_t/.28,0,1));_kill_splat.modulate=Color(1,1,1,clampf(splat_t/.16,0,1)*(1-clampf((splat_t-.6)/.2,0,1)))

func _update_shadow()->void:
	var stack:Array=[]
	var hit_age:float=clock-_hit_at;var full_age:float=clock-_flash_at
	if full_age<.35:
		var k:float=clampf(_bezier(full_age/.35,.34,1.56,.64,1),0,1)
		stack=[{"sigma":lerpf(6,1.2 if _target else 1.0,k),"color":Color.WHITE.lerp(Color.WHITE if _target else Color(0,0,0,.95),k)},{"sigma":lerpf(1,1.2 if _target else 2.0,k),"color":Color.BLACK.lerp(Color.WHITE if _target else Color(0,0,0,.45),k),"offset":Vector2(0,0 if _target else k)}]
	elif hit_age<.18:
		var k:float=_bezier(hit_age/.18,0,0,.58,1)
		stack=[{"sigma":lerpf(4,1.2 if _target else 1.0,k),"color":Color.WHITE.lerp(Color.WHITE if _target else Color(0,0,0,.95),k)},{"sigma":lerpf(1,1.2 if _target else 2.0,k),"color":Color.BLACK.lerp(Color.WHITE if _target else Color(0,0,0,.45),k),"offset":Vector2(0,0 if _target else k)}]
	elif _target:
		stack=[{"sigma":1.2,"color":Color.WHITE},{"sigma":1.2,"color":Color.WHITE},{"sigma":3.0,"color":Color(0,0,0,.55)}]
	else:stack=[{"sigma":1.0,"color":Color(0,0,0,.95)},{"sigma":2.0,"color":Color(0,0,0,.45),"offset":Vector2(0,1)}]
	if _target and stack.size()==2:
		# CSS pads the shorter keyframe filter list with a transparent identity shadow.
		var blend:float=clampf(_bezier(full_age/.35,.34,1.56,.64,1),0,1) if full_age<.35 else _bezier(hit_age/.18,0,0,.58,1)
		stack.append({"sigma":3*blend,"color":Color(0,0,0,.55*blend)})
	_shadow.set_stack(stack)
	_shadow.output.modulate.a=_opacity

func _draw()->void:
	if _tank==null:return
	_drawing=self
	var center:Vector2=size*.5
	_drawing.draw_set_transform(center)
	_draw_hit_markers()
	if _sub_alpha>.001:
		var origin:Vector2=Vector2(-22-_sub_width,44)
		if _sub_short and clock-_short_at<.3:origin.x+=sin((clock-_short_at)*100)*3*maxf(0,1-(clock-_short_at)/.3)
		_drawing.draw_set_transform(center+origin+Vector2(_sub_width*.5,14),0,Vector2.ONE*_sub_scale)
		_pill.border_color=Color("ff3d5e") if _sub_short else Color(1,1,1,.14);_pill.bg_color=Color(.055,.043,.086,.82*_sub_alpha);_pill.border_color.a*=_sub_alpha
		_drawing.draw_style_box(_pill,Rect2(Vector2(-_sub_width*.5,-14),Vector2(_sub_width,28)))
		_bar.bg_color=Color(1,1,1,.15*_sub_alpha);_fill.bg_color=Color(Color("ff3d5e") if _sub_short else _team,_sub_alpha)
		_drawing.draw_style_box(_bar,Rect2(Vector2(-_sub_width*.5+32,-3.5),Vector2(46,7)))
		if _sub_fraction>.001:_drawing.draw_style_box(_fill,Rect2(Vector2(-_sub_width*.5+32,-3.5),Vector2(46*_sub_fraction,7)))
	_drawing.draw_set_transform(Vector2.ZERO)

func paint_mask(painter:Control)->void:
	_drawing=painter
	var center:Vector2=Vector2(192,192)
	var ret_scale:float=_scale;var ret_color:Color=_color;var angle:float=0
	var kill_t:float=clock-_kill_at;var hit_t:float=clock-_hit_at;var flash_t:float=clock-_flash_at
	if flash_t<.35:ret_scale=lerpf(1.35,_scale,_bezier(flash_t/.35,.34,1.56,.64,1))
	if hit_t<.18:
		var hit_k:float=1-_bezier(hit_t/.18,0,0,.58,1)
		ret_scale=lerpf(_scale,1.12,hit_k);ret_color=_color.lerp(Color.WHITE,hit_k)
	if kill_t<.45:
		var kill_k:float=1-_bezier(kill_t/.45,.34,1.56,.64,1)
		ret_scale=lerpf(_scale,1.45,kill_k);angle=deg_to_rad(45)*kill_k;ret_color=_color.lerp(_light,clampf(kill_k,0,1))
	_drawing.draw_set_transform(center,angle,Vector2.ONE*ret_scale)
	var dot_color:Color=ret_color
	_drawing.draw_circle(Vector2.ZERO,2.5*(.55 if _far else 1),dot_color,true,-1,true)
	if weapon=="roller":
		_stroke(_path("roller_left"),2.6,ret_color);_stroke(_path("roller_right"),2.6,ret_color);_stroke(_path("roller_bottom"),1.8,_alpha(ret_color,.75))
	elif weapon=="dualies":
		for hand:int in 2:
			var age:float=clock-(_hand_at.x if hand==0 else _hand_at.y)
			var shot_k:float=1-_bezier(clampf(age/.13,0,1),.2,.8,.3,1)
			var twin_x:float=_twins.y if hand==0 else _twins.x
			_drawing.draw_set_transform(center+Vector2(twin_x,0).rotated(angle)*ret_scale,angle,Vector2.ONE*ret_scale*(1+shot_k*.55))
			_stroke(_path("circle6"),lerpf(1.8,2.6,shot_k),_alpha(ret_color,.75))
		_drawing.draw_set_transform(center,angle,Vector2.ONE*ret_scale*(1.5-.5*_lock_k));_stroke(_path("diamond"),2.4,Color(_light,_lock_alpha))
		_drawing.draw_set_transform(center,angle,Vector2.ONE*ret_scale);_ticks(ret_color,4)
	elif weapon=="slosher":
		# CSS transform origin is the arch's bounding-box bottom (y=6).
		_drawing.draw_set_transform(center+Vector2(0,-4*kick-6*.35*kick).rotated(angle)*ret_scale,angle,Vector2(ret_scale,ret_scale*(1+.35*kick)))
		_stroke(_path("arch"),2.6,ret_color)
		_drawing.draw_set_transform(center,angle,Vector2.ONE*ret_scale);_stroke(_path("bucket"),1.8,_alpha(ret_color,.75));_stroke(_path("bucket_sides"),1.8,_alpha(ret_color,.75),false)
	elif weapon=="blaster":
		_drawing.draw_set_transform(center,angle,Vector2.ONE*ret_scale*_blaster_scale)
		_stroke(_shape.blaster_far if _far else _shape.blaster,2.6,ret_color,false);_stroke(_path("circle9"),1.8,_alpha(ret_color,.75))
	elif weapon=="charger":
		_stroke(_path("circle25"),2,_alpha(ret_color,.45))
		_charge_arc(25,4.5,Color(Color.WHITE if _full else _light,1.0),_charge,true)
		_stroke(_path("notches"),2.2,Color(Color.WHITE if _full else ret_color,(1.0 if _full else .55)),false)
		_bar_line(Vector2(-52+_charge*10,0),Vector2(-36+_charge*10,0),2.5,ret_color)
		_bar_line(Vector2(36-_charge*10,0),Vector2(52-_charge*10,0),2.5,ret_color)
		_bar_line(Vector2(0,34),Vector2(0,46),2.5,ret_color)
	elif weapon=="splatling":
		_stroke(_path("circle21"),4.5,_alpha(ret_color,.28))
		var state:Dictionary=frame.get("weapon_state",{})
		var streaming:bool=bool(state.get("streaming",float(state.get("burst",0))>0))
		_charge_arc(21,4.5,Color(_light if _full or streaming else Color.WHITE,1.0),_charge,false)
		_stroke(_path("segments"),1.6,Color(0,0,0,.55),false,false)
		_ticks(ret_color,2)
	else:
		_stroke(_path("circle15"),1.8,_alpha(ret_color,.75));_ticks(ret_color,4)
	_drawing.draw_set_transform(Vector2.ZERO)
	_drawing=self

func paint_shield_mask(painter:Control)->void:
	_drawing=painter
	_drawing.draw_set_transform(Vector2(192,192),clock*TAU/4,Vector2.ONE*_shield_scale)
	_drawing.draw_multiline(_shape.shield,_light,2.5,true)
	# Only the ends of complete dashes receive round SVG caps; interior curve vertices do not.
	for point:Vector2 in _shield_caps:_drawing.draw_circle(point,1.25,_light,true,-1,true)
	_drawing.draw_set_transform(Vector2.ZERO)
	_drawing=self

func _draw_hit_markers()->void:
	var age:float=clock-_hit_at
	if age<.24:
		var t:float=_bezier(age/.24,0,0,.58,1);var color:Color=Color.WHITE.lerp(_light,_combo*.11);color.a=1-t
		var half:float=7.5 if _heavy else 6.0;var width:float=5 if _heavy else 3.5
		for index:int in 4:
			var axis:Vector2=Vector2.from_angle(PI*.25+index*PI*.5)
			var position:Vector2=axis*lerpf(10+_combo,18+_combo*2,t)*_hit_scale
			var length:float=half*lerpf(1.3,1,t)*_hit_scale
			_bar_line(position-axis*length,position+axis*length,width*_hit_scale*lerpf(1.3,1,t),color)
		if _heavy and age<.22:
			var ring_t:float=_bezier(age/.22,0,0,.58,1)
			var ring_scale:float=lerpf(.55,1.45,ring_t)
			_charge_arc(15*ring_scale,lerpf(2.5,1,ring_t)*ring_scale,Color(1,1,1,.95*(1-ring_t)),1,true,false)
	age=clock-_kill_at
	if age<.55:
		var t:float=_bezier(age/.55,.22,1,.36,1);var alpha:float=1.0 if age<.33 else 1-_bezier((age-.33)/.22,.22,1,.36,1)
		for index:int in 4:
			var axis:Vector2=Vector2.from_angle(PI*.25+index*PI*.5)
			var position:Vector2=axis*lerpf(12,28,t);var length:float=10*lerpf(1.6,1,t)
			_bar_line(position-axis*length,position+axis*length,5*lerpf(1.6,1,t),Color(_light,alpha))
		if age<.5:
			var ring_t:float=_bezier(age/.5,.22,1,.36,1)
			var ring_scale:float=lerpf(.3,1.9,ring_t)
			_charge_arc(30*ring_scale,lerpf(4,1,ring_t)*ring_scale,Color(_light,1-ring_t),1,true,false)

func _ticks(color:Color,count:int)->void:
	for index:int in count:
		var axis:Vector2=Vector2.from_angle(index*PI if count==2 else -PI*.5+index*PI*.5)
		var midpoint:Vector2=axis*(17+_spread)
		_bar_line(midpoint-axis*5.5,midpoint+axis*5.5,3,color)

func _path(id:String)->PackedVector2Array:
	return _dashed_shape[id] if _far else _shape[id]

func _stroke(points:PackedVector2Array,width:float,color:Color,polyline:bool=true,shadow:bool=true)->void:
	if points.size()<2 or color.a<=.001:return
	if shadow and _drawing==self:
		if polyline and not _far:_drawing.draw_polyline(points,Color(0,0,0,.82*color.a),width+1.8,true)
		else:_drawing.draw_multiline(points,Color(0,0,0,.82*color.a),width+1.8,true)
	if polyline and not _far:_drawing.draw_polyline(points,color,width,true)
	else:_drawing.draw_multiline(points,color,width,true)
	# Canvas lines have square caps; SVG paths use round caps (circle paths are closed).
	if polyline and not _far and points[0].distance_squared_to(points[-1])>.001:
		_drawing.draw_circle(points[0],width*.5,color,true,-1,true);_drawing.draw_circle(points[-1],width*.5,color,true,-1,true)

func _bar_line(from:Vector2,to:Vector2,width:float,color:Color)->void:
	if color.a<=.001:return
	# CSS ticks and charge bars are rounded rectangles, not overlapping stroke/cap primitives.
	# Cardinal paths preserve the original outside width/height in one antialiased draw.
	if _drawing!=self and (absf(from.x-to.x)<.0001 or absf(from.y-to.y)<.0001):
		_tick_box.bg_color=color
		var origin:Vector2=from.min(to)
		var extent:Vector2=(to-from).abs()
		if extent.x<.0001:origin.x-=width*.5;extent.x=width
		else:origin.y-=width*.5;extent.y=width
		_drawing.draw_style_box(_tick_box,Rect2(origin,extent));return
	# CSS i elements specify their outside width/height; inset the stroke cap centers.
	var direction:Vector2=(to-from).normalized();var inset:float=minf(width*.5,from.distance_to(to)*.5)
	from+=direction*inset;to-=direction*inset
	if _drawing==self:_drawing.draw_line(from,to,Color(0,0,0,.65*color.a),width+1.5,true)
	_drawing.draw_line(from,to,color,width,true);_drawing.draw_circle(from,width*.5,color,true,-1,true);_drawing.draw_circle(to,width*.5,color,true,-1,true)

func _charge_arc(radius:float,width:float,color:Color,fraction:float,round_caps:bool,range_dashes:bool=true)->void:
	if fraction<=.0001:return
	var count:int=maxi(1,ceili(128*fraction));_arc_points.resize(count+1)
	for index:int in count+1:_arc_points[index]=Vector2.from_angle(-PI*.5+TAU*fraction*index/count)*radius
	if _far and range_dashes:
		var norm:float=TAU*radius/100 if weapon=="splatling" else 1.0
		_arc_dashes=_dash(_arc_points,3*norm,4*norm);_stroke(_arc_dashes,width,color,false)
	else:
		if _drawing==self:_drawing.draw_polyline(_arc_points,Color(0,0,0,.7*color.a),width+1.4,true)
		_drawing.draw_polyline(_arc_points,color,width,true)
		if round_caps:_drawing.draw_circle(_arc_points[0],width*.5,color,true,-1,true);_drawing.draw_circle(_arc_points[-1],width*.5,color,true,-1,true)

func _cache_shapes()->void:
	for radius:int in [6,9,15,21,25]:
		var points:PackedVector2Array=PackedVector2Array()
		for index:int in 129:points.append(Vector2.from_angle(TAU*index/128)*(6.2 if radius==6 else radius))
		_shape["circle%d"%radius]=points;_dashed_shape["circle%d"%radius]=_dash(points,3,4)
	var circle:PackedVector2Array=PackedVector2Array()
	for index:int in 129:circle.append(Vector2.from_angle(TAU*index/128)*23)
	_shape.blaster=_dash(circle,TAU*23*.19,TAU*23*.06,TAU*23*.095)
	_shape.blaster_far=_dash(circle,TAU*23*.03,TAU*23*.04,TAU*23*.095)
	circle=PackedVector2Array()
	for index:int in 129:circle.append(Vector2.from_angle(TAU*index/128)*36)
	_shape.shield=_dash(circle,TAU*36*.05,TAU*36*.0333)
	for index:int in range(0,_shape.shield.size(),2):
		if index==0 or _shape.shield[index-1].distance_squared_to(_shape.shield[index])>.0001:_shield_caps.append(_shape.shield[index])
		if index+2>=_shape.shield.size() or _shape.shield[index+1].distance_squared_to(_shape.shield[index+2])>.0001:_shield_caps.append(_shape.shield[index+1])
	_shape.diamond=PackedVector2Array([Vector2(0,-19),Vector2(19,0),Vector2(0,19),Vector2(-19,0),Vector2(0,-19)])
	_shape.arch=_quadratic(Vector2(-24,6),Vector2(0,-26),Vector2(24,6))
	_shape.bucket=PackedVector2Array([Vector2(-10,13),Vector2(-6,18),Vector2(6,18),Vector2(10,13)])
	_shape.bucket_sides=PackedVector2Array([Vector2(-24,6),Vector2(-27,1),Vector2(24,6),Vector2(27,1)])
	_shape.notches=PackedVector2Array([Vector2(0,-31),Vector2(0,-36),Vector2(31,0),Vector2(36,0),Vector2(0,31),Vector2(0,36),Vector2(-31,0),Vector2(-36,0)])
	_shape.segments=PackedVector2Array()
	for index:int in 8:
		_shape.segments.append(Vector2.from_angle(-PI*.5+index*PI*.25)*17);_shape.segments.append(Vector2.from_angle(-PI*.5+index*PI*.25)*25)
	for side:int in [-1,1]:
		var points:PackedVector2Array=PackedVector2Array([Vector2(side*46,-15),Vector2(side*56,-15)])
		points.append_array(_quadratic(Vector2(side*56,-15),Vector2(side*60,-15),Vector2(side*60,-11)))
		points.append(Vector2(side*60,11));points.append_array(_quadratic(Vector2(side*60,11),Vector2(side*60,15),Vector2(side*56,15)));points.append(Vector2(side*46,15))
		_shape["roller_left" if side<0 else "roller_right"]=points
	_shape.roller_bottom=_quadratic(Vector2(-30,22),Vector2(0,30),Vector2(30,22))
	for key:String in ["diamond","arch","bucket","roller_left","roller_right","roller_bottom"]:_dashed_shape[key]=_dash(_shape[key],3,4)
	for key:String in ["bucket_sides","notches","segments"]:
		var dashed:PackedVector2Array=PackedVector2Array();var points:PackedVector2Array=_shape[key]
		for index:int in range(0,points.size(),2):dashed.append_array(_dash(PackedVector2Array([points[index],points[index+1]]),3,4))
		_dashed_shape[key]=dashed

func _quadratic(a:Vector2,b:Vector2,c:Vector2)->PackedVector2Array:
	var points:PackedVector2Array=PackedVector2Array()
	for index:int in 25:
		var t:float=index/24.0;points.append(a*(1-t)*(1-t)+b*(2*t*(1-t))+c*t*t)
	return points

func _dash(points:PackedVector2Array,on:float,off:float,offset:float=0)->PackedVector2Array:
	var result:PackedVector2Array=PackedVector2Array();var phase:float=fposmod(offset,on+off)
	for index:int in points.size()-1:
		var from:Vector2=points[index];var to:Vector2=points[index+1];var length:float=from.distance_to(to);var cursor:float=0
		while cursor<length-.00001:
			var drawing:bool=phase<on;var distance:float=minf(length-cursor,(on if drawing else on+off)-phase)
			if distance<.00001:phase=fposmod(phase+.00001,on+off);continue
			if drawing:result.append(from.lerp(to,cursor/length));result.append(from.lerp(to,(cursor+distance)/length))
			cursor+=distance;phase=fposmod(phase+distance,on+off)
	return result

func _progress(since:float,duration:float,easing:String)->float:
	if since<0:return 1.0
	var t:float=clampf((clock-since)/duration,0,1)
	if easing=="spring":return _bezier(t,.34,1.56,.64,1)
	if easing=="ease":return _bezier(t,.25,.1,.25,1)
	if easing=="out":return _bezier(t,.22,1,.36,1)
	return t

static func _bezier(x:float,x1:float,y1:float,x2:float,y2:float)->float:
	x=clampf(x,0,1)
	if x==0 or x==1:return x
	var lo:float=0;var hi:float=1;var t:float=x
	for iteration:int in 12:
		var sample:float=3*(1-t)*(1-t)*t*x1+3*(1-t)*t*t*x2+t*t*t
		if sample<x:lo=t
		else:hi=t
		t=(lo+hi)*.5
	return 3*(1-t)*(1-t)*t*y1+3*(1-t)*t*t*y2+t*t*t

static func _alpha(color:Color,factor:float)->Color:
	color.a*=factor;return color

static func _colored_icon(id:String,original:String,color:Color)->Texture2D:
	var key:String=id+color.to_html(false)
	if not _icon_cache.has(key):
		# Imported .svg resources can omit the original bytes from PCK. Keep a raw text companion.
		var path:String="res://assets/ui/source_raw/%s.svg.txt"%id
		if not FileAccess.file_exists(path):
			_icon_error(path,"raw SVG text companion missing from package; export assets/ui/source_raw/*.svg.txt")
			return null
		var svg:String=FileAccess.get_file_as_string(path)
		if svg.strip_edges().is_empty():
			_icon_error(path,"raw SVG file empty or unreadable")
			return null
		svg=svg.replace(original,"#"+color.to_html(false))
		var image:Image=Image.new()
		var error:Error=image.load_svg_from_string(svg)
		if error!=OK:
			_icon_error(path,"SVG parse failed: "+error_string(error))
			return null
		_icon_cache[key]=ImageTexture.create_from_image(image)
	return _icon_cache.get(key)

static func _icon_error(path:String,reason:String)->void:
	if _icon_errors.has(path):return
	_icon_errors[path]=true
	push_error("Splatink reticle icon dependency: %s · %s"%[path,reason])

func _label(text:String)->Label:
	var label:Label=Label.new();label.text=text;label.mouse_filter=Control.MOUSE_FILTER_IGNORE;label.add_theme_font_override("font",BODY);label.add_theme_font_size_override("font_size",11);label.add_theme_color_override("font_color",Color.WHITE);return label

func debug_state()->Dictionary:
	return {"weapon":weapon,"spread_px":_spread,"charge":_charge,"target":str(frame.get("crosshair",{}).get("onTarget","")),"far":_far,"full":_full,"lock":_lock,"lock_amount":_lock_k,"twin_positions":_twins,"hand_ages":Vector2(clock-_hand_at.x,clock-_hand_at.y),"bloom":bloom,"kick":kick,"shield":_shield_up,"sub_aim":_sub_on,"sub_short":_sub_short,"tank_idle":_tank_idle,"tank_level":_tank_level,"bubble_count":_bubble_count,"combo":_combo,"heavy":_heavy,"hit_age":clock-_hit_at,"kill_age":clock-_kill_at,"css_pixel_size":size}
