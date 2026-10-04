class_name SplatBossHud
extends SplatLabCanvas
## Literal BossHud state and timings from src/ui/hud-boss.js; display only.
const C=preload("res://scripts/ui/lab_canvas.gd")
const LABELS:Dictionary={"slam":"SLAM!","barrage":"INCOMING!","sweep":"SWEEP!","charge":"CHARGE!","crablets":"BROOD!","frenzy":"FRENZY!","open":"OPEN!"}
var game:Node
var match_hud:Control
var boss:Node3D
var active:bool=false
var clock:float=0.0
var hp:float=1.0
var shown:float=1.0
var chip:float=1.0
var chip_hold:float=0.0
var phase:int=1
var stun_left:float=0.0
var stun_duration:float=1.0
var shield_left:float=0.0
var intro_age:float=-1.0
var visible_age:float=0.0
var hit_left:float=0.0
var weak_left:float=0.0
var dead:bool=false
var ended:bool=false
var death_age:float=0.0
var _last_crit:float=-9.0
var _last_immune:float=-9.0
var _bar:Control
var _plate:Control
var _emblem:TextureRect
var _splat:TextureRect
var _cross:TextureRect
var _stars:Array[TextureRect]=[]
var _track:ColorRect
var _track_material:ShaderMaterial
var _pct:Label
var _pips:Array[Control]=[]
var _notches:Array[Control]=[]
var _rage:Control
var _lock:TextureRect
var _stun:Control
var _stun_fill:Control
var _open:Control
var _call:Control
var _call_face:Control
var _call_icon:TextureRect
var _call_word:Label
var _call_arrow:TextureRect
var _edge:Label
var _call_id:String=""
var _call_age:float=0.0
var _call_position:Vector2=Vector2.ZERO
var _over:Control
var _numbers:Array[Dictionary]=[]
var _combo:Dictionary={}

func configure(controller:Node,hud:Control)->void:
	game=controller;match_hud=hud
	if _bar==null:_build()

func _frame(parent:Node,x:float,y:float,w:float,h:float,color:Color,radius:float=1.0)->Control:
	C.panel(parent,x-.47,y-.47+.35,w+.94,h+.94,SplatUiTheme.INK,radius+.47)
	var face:Control=C.panel(parent,x-.24,y-.24,w+.48,h+.48,Color.WHITE,radius+.24)
	return C.panel(face,.24,.24,w,h,color,radius)

func _build()->void:
	if canvas==null:return
	_bar=Control.new();canvas.add_child(_bar);C.at(_bar,width_u*.5-26,6.7,52,7.6)
	_plate=_frame(_bar,4.7,1.1,43.2,5.45,Color("15121c"),1.1);_plate.rotation=deg_to_rad(-1)
	C.label(_plate,"HULLBREAKER",3.4,.2,23,2.2,1.85,true)
	_rage=C.panel(_plate,22.0,.55,7.7,1.3,Color("ff2d55"),.35);C.label(_rage,"ENRAGED",0,0,7.7,1.3,.8).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_rage.rotation=deg_to_rad(-4);_rage.hide()
	C.label(_plate,"PHASE",31.2,.6,4.8,1,.8,false,Color(1,1,1,.66))
	for index:int in 3:
		var pip:Control=C.panel(_plate,36.5+index*1.4,.65,1,1,Color(1,1,1,.14),.12);pip.pivot_offset=pip.size*.5;pip.rotation=PI*.25;_pips.append(pip)
	_track=ColorRect.new();_track.mouse_filter=Control.MOUSE_FILTER_IGNORE;_plate.add_child(_track);C.at(_track,3.4,2.9,38.5,2.15)
	_track_material=ShaderMaterial.new();_track_material.shader=preload("res://assets/ui/lab_boss_track.gdshader");_track_material.set_shader_parameter("panel_size",_track.size);_track.material=_track_material
	for fraction:float in [2.0/3.0,1.0/3.0]:
		var notch:Control=C.panel(_track,38.5*fraction-.19,-.35,.39,2.85,SplatUiTheme.INK,.1)
		var diamond:Control=C.panel(notch,-.36,-.6,1.1,1.1,Color.WHITE,.1);diamond.pivot_offset=diamond.size*.5;diamond.rotation=PI*.25;_notches.append(diamond)
	_lock=C.icon(_track,"glyph_lock",18, -.22,2.6,2.6);_lock.hide()
	_stun=Control.new();_plate.add_child(_stun);C.at(_stun,3.4,5.7,38.5,.75)
	var stun_track:Control=_frame(_stun,0,0,38.5,.75,SplatUiTheme.INK,.38)
	_stun_fill=C.panel(stun_track,0,0,38.5,.75,SplatUiTheme.GOLD,.38);(_stun_fill.material as ShaderMaterial).set_shader_parameter("bottom_color",Color("fff6b8"));_stun.hide()
	_splat=C.icon(_bar,"boss_bar_splat",-1.67,-1.67,10.94,10.94);_splat.pivot_offset=_splat.size*.5;_splat.z_index=1
	var circle:Control=_frame(_bar,.3,.3,7.0,7.0,Color("3a3150"),3.5);circle.z_index=2;circle.rotation=deg_to_rad(-6)
	_emblem=C.icon(circle,"boss_emblem",-.3,-.05,7.6,7.6)
	_cross=C.icon(circle,"glyph_close",1,1,5,5);_cross.hide()
	for index:int in 3:
		var star:TextureRect=C.icon(circle,"glyph_star",0,0,1.6,1.6);star.modulate=SplatUiTheme.GOLD;star.hide();_stars.append(star)
	var percentage:Control=_frame(_bar,46.6,1.1,5.4,5.4,SplatUiTheme.INK,2.7);percentage.rotation=deg_to_rad(5);percentage.z_index=2
	_pct=C.label(percentage,"100",.3,1.3,4.3,2.3,1.75);_pct.add_theme_font_override("font",SplatUiTheme.DISPLAY);_pct.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	C.label(percentage,"%",4.1,2.35,1.0,1.2,.8,false,Color(1,1,1,.7))
	_open=C.panel(_bar,52.0,2.4,10.4,2.9,SplatUiTheme.GOLD,1.45);_open.rotation=deg_to_rad(-7);_open.pivot_offset=_open.size*.5
	C.icon(_open,"boss_move_open",.45,.4,2.1,2.1);C.label(_open,"OPEN!",2.9,.3,6.5,2.4,2.0,false,SplatUiTheme.INK).add_theme_font_override("font",SplatUiTheme.DISPLAY);_open.hide()
	_call=Control.new();canvas.add_child(_call);C.at(_call,0,0,16,3.0);_call.pivot_offset=_call.size*.5
	_call_face=_frame(_call,0,0,16,3.0,Color("15121c"),1.5)
	_call_icon=C.icon(_call_face,"boss_move_slam",.3,.45,2.1,2.1)
	_call_word=C.label(_call_face,"SLAM!",2.8,.15,12.4,2.6,1.4,true)
	_call_arrow=C.icon(_call_face,"glyph_right",13.5,.25,2.4,2.4);_call_arrow.modulate=SplatUiTheme.GOLD;_call_arrow.pivot_offset=_call_arrow.size*.5;_call_arrow.hide()
	_edge=C.label(_call,"›",15.7,.3,2.8,2.5,2.4,true);_edge.hide();_call.hide()
	_over=Control.new();_over.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.add_child(_over)
	layout_changed.connect(_layout_boss)
	_layout_boss();_write_bar();hide()

func _layout_boss()->void:
	if _bar:C.at(_bar,width_u*.5-26,6.7,52,7.6)
	if _over:C.at(_over,0,0,width_u,height_u)

func clear()->void:
	active=false;boss=null;dead=false;ended=false;phase=1;hp=1;shown=1;chip=1;stun_left=0;shield_left=0;intro_age=-1;visible_age=0;_combo.clear()
	for item:Dictionary in _numbers:
		if is_instance_valid(item.node):item.node.queue_free()
	_numbers.clear()
	if _over:
		for node:Node in _over.get_children():node.queue_free()
	if _call:_call.hide()
	hide()

func _colors()->Array[Color]:
	if is_instance_valid(game) and game.get("team_colors") is Array:return [game.team_colors[0],game.team_colors[1]]
	return [SplatUiTheme.ORANGE,SplatUiTheme.BLUE]

func on_event(kind:String,data:Dictionary)->void:
	if not kind.begins_with("boss:"):return
	if is_instance_valid(data.get("boss")):boss=data.boss as Node3D
	match kind:
		"boss:spawn":
			clear();boss=data.get("boss") as Node3D;active=is_instance_valid(boss);show()
			if active:hp=clampf(float(boss.get("hp"))/maxf(1,float(boss.get("max_hp"))),0,1);shown=hp;chip=hp
		"boss:intro":
			active=true;show();intro_age=0;shown=0;chip=0;visible_age=0;_title_card()
		"boss:hp":_hp_event(float(data.get("hp",0)),float(data.get("max",1)))
		"boss:move":
			if dead:return
			var move:String=str(data.get("id",""));var move_phase:String=str(data.get("phase",""))
			if move_phase=="tele" and stun_left<=0 and LABELS.has(move):_show_call(move)
			elif move_phase=="act" and _call_id==move:_pop(_call,.35,1.35)
			elif move_phase=="rec" and stun_left<=0:_call.hide()
		"boss:stun":stun_duration=maxf(.5,float(data.get("dur",3)));stun_left=stun_duration;_show_call("open")
		"boss:phase":
			var next:int=clampi(int(data.get("phase",1)),1,3)
			if next>phase:
				phase=next;shield_left=1.8;_phase_banner(next);_pop(_bar,.5,1.08)
		"boss:hit":_hit(data)
		"boss:defeat":
			if dead:return
			dead=true;death_age=0;hp=0;stun_left=0;_call.hide();_ending(true)

func _hp_event(value:float,maximum:float)->void:
	var fraction:float=clampf(value/maxf(.00001,maximum),0,1)
	if fraction<hp-.00001:
		if chip<=shown+.003:chip_hold=.6
		hit_left=.14;_pop(_pct.get_parent() as Control,.2,1.12)
		for index:int in 2:
			var mark:float=(2.0-index)/3.0
			if hp>mark and fraction<=mark:_pop(_notches[index],.5,2.2)
	hp=fraction

func times_up()->bool:
	if not active:return false
	if not dead and not ended:_ending(false)
	return true

func _show_call(id:String)->void:
	_call_id=id;_call_age=0;_call_position=Vector2.ZERO
	_call_icon.texture=load("res://assets/ui/source/boss_move_%s.svg"%id) as Texture2D
	_call_word.text=str(LABELS[id]);_call_word.add_theme_color_override("font_color",SplatUiTheme.INK if id=="open" else Color.WHITE)
	(_call_face.material as ShaderMaterial).set_shader_parameter("top_color",SplatUiTheme.GOLD if id=="open" else SplatUiTheme.INK)
	(_call_face.material as ShaderMaterial).set_shader_parameter("bottom_color",SplatUiTheme.GOLD if id=="open" else SplatUiTheme.INK)
	_call_arrow.visible=id=="charge";_call.show();_pop(_call,.42,.2)

func _project(world:Vector3)->Dictionary:
	var camera:Camera3D=game.get("camera") as Camera3D if is_instance_valid(game) else null
	if not is_instance_valid(camera):return {}
	var point:Vector2=camera.unproject_position(world)
	return {"p":point/canvas.scale,"behind":camera.is_position_behind(world)}

func _place_call(delta:float)->void:
	if not is_instance_valid(boss):return
	var anchor:Vector3=boss.call("get_socket","shellTop",boss.global_position+Vector3.UP*5.2) if boss.has_method("get_socket") else boss.global_position+Vector3.UP*5.2
	var screen:Dictionary=_project(anchor+Vector3.UP*1.9)
	if screen.is_empty():return
	var point:Vector2=screen.p;var center:Vector2=Vector2(width_u,height_u)*6.4;var direction:Vector2=point-center;var edge:bool=false
	if bool(screen.behind):direction=-direction
	var min_point:=Vector2(7,16)*12.8;var max_point:=Vector2(width_u-7,height_u-7)*12.8
	if not bool(screen.behind) and point.x>=min_point.x and point.x<=max_point.x and point.y<min_point.y:point.y=min_point.y
	if bool(screen.behind) or point.x<min_point.x or point.x>max_point.x or point.y>max_point.y:
		edge=true
		if direction.length_squared()<1:direction=Vector2.DOWN
		var angle:float=direction.angle();var radius_x:float=center.x-min_point.x;var radius_y:float=(max_point.y-min_point.y)*.5
		var k:float=minf(radius_x/maxf(.001,absf(cos(angle))),radius_y/maxf(.001,absf(sin(angle))))
		point=Vector2(center.x,min_point.y+radius_y)+Vector2(cos(angle),sin(angle))*k
		_edge.rotation=angle
	else:
		var difference:Vector2=point-center;var r:float=pow(difference.x/(15*12.8),2)+pow(difference.y/(10.5*12.8),2)
		if r<1:point=center+Vector2(0,-10.5*12.8) if r<.0001 else center+difference/sqrt(r)
	if _call_position==Vector2.ZERO:_call_position=point
	_call_position=_call_position.lerp(point,minf(1,delta*12));_call.position=_call_position-_call.size*.5;_edge.visible=edge
	if _call_id=="charge":
		var a:Dictionary=_project(boss.global_position+Vector3.UP)
		var b:Dictionary=_project(boss.global_position+Vector3.UP+boss.global_basis.z*6)
		if not a.is_empty() and not b.is_empty():_call_arrow.rotation=(Vector2(b.p)-Vector2(a.p)).angle()

func _write_bar()->void:
	if not _track_material:return
	var colors:Array[Color]=_colors();_track_material.set_shader_parameter("boss",colors[1]);_track_material.set_shader_parameter("hp",shown);_track_material.set_shader_parameter("chip",chip);_track_material.set_shader_parameter("enraged",phase>=3);_track_material.set_shader_parameter("shield",shield_left>0 or (is_instance_valid(boss) and bool(boss.get("invuln"))))
	_track_material.set_shader_parameter("flash",maxf(hit_left/.14,weak_left/.3));_track_material.set_shader_parameter("flash_color",colors[0].lightened(.65) if weak_left>0 else Color.WHITE)
	_pct.text=str(1 if shown>0 and shown<.01 else ceili(shown*100-.000001));_pct.add_theme_color_override("font_color",SplatUiTheme.GOLD if shown>0 and shown<=.2 else Color.WHITE)
	_splat.modulate=colors[1];_rage.visible=phase>=3;_cross.visible=dead
	_emblem.texture=load("res://assets/ui/source/boss_emblem_cracked.svg" if phase>=3 else "res://assets/ui/source/boss_emblem.svg") as Texture2D
	_lock.visible=shield_left>0 or (is_instance_valid(boss) and bool(boss.get("invuln")))
	_stun.visible=stun_left>0;_open.visible=stun_left>0;_stun_fill.scale.x=clampf(stun_left/maxf(.01,stun_duration),0,1)
	for index:int in _pips.size():
		var pip:Control=_pips[index];var color:Color=Color("ff2d55") if phase>=3 and index==phase-1 else Color.WHITE if index==phase-1 else colors[1].lightened(.4) if index<phase else Color(1,1,1,.14)
		(pip.material as ShaderMaterial).set_shader_parameter("top_color",color);(pip.material as ShaderMaterial).set_shader_parameter("bottom_color",color);pip.scale=Vector2.ONE*(1.25 if index==phase-1 else 1.0)
	for index:int in _stars.size():
		var star:TextureRect=_stars[index];star.visible=stun_left>0;var angle:float=(clock+index*.37)*TAU/1.1;star.position=Vector2(3.5,0)*12.8+Vector2(cos(angle),sin(angle))*3*12.8-star.size*.5;star.scale=Vector2.ONE*(1.05+.15*sin(angle))

func _process(delta:float)->void:
	if not active or not _bar:return
	clock+=delta
	if is_instance_valid(game) and str(game.get("state")) in ["menu","results"]:clear();return
	_bar.visible=is_instance_valid(match_hud) and match_hud.visible and bool(match_hud.call("is_chrome_visible")) and (not dead or death_age<1.9)
	if is_instance_valid(boss):
		var fraction:float=clampf(float(boss.get("hp"))/maxf(1,float(boss.get("max_hp"))),0,1)
		if absf(fraction-hp)>.00001:_hp_event(float(boss.get("hp")),float(boss.get("max_hp")))
		if bool(boss.get("dead")) and not dead:on_event("boss:defeat",{"boss":boss})
	if intro_age>=0:
		intro_age+=delta;visible_age=visible_age+delta if _bar.visible else 0
		var k:float=clampf(minf(intro_age-2.25,visible_age-.2)/1.05,0,1);shown=hp*(1-pow(1-k,3));chip=shown
		if k>=1:intro_age=-1
	else:
		shown=lerpf(shown,hp,minf(1,delta*16));chip_hold=maxf(0,chip_hold-delta)
		if chip_hold<=0:chip=maxf(shown,chip-delta*maxf(.2,(chip-shown)*2.2))
	stun_left=maxf(0,stun_left-delta);shield_left=maxf(0,shield_left-delta);hit_left=maxf(0,hit_left-delta);weak_left=maxf(0,weak_left-delta)
	if _call.visible:
		_call_age+=delta
		if (_call_id=="open" and stun_left<=0) or (_call_id!="open" and _call_age>3.2):_call.hide()
		else:_place_call(delta)
	if dead:
		death_age+=delta
		if death_age>1.3:_bar.modulate.a=clampf(1-(death_age-1.3)/.6,0,1)
	_splat.rotation=clock*TAU/22;_open.scale=Vector2.ONE*(1+.12*(.5-.5*cos(clock*TAU/.55)));_rage.scale=Vector2.ONE*(1+.1*(.5-.5*cos(clock*TAU/.8)))
	_write_bar();_update_numbers()

func _hit(data:Dictionary)->void:
	if not active or dead:return
	var attacker:Node=data.get("attacker") as Node
	if not is_instance_valid(attacker) or not bool(attacker.get("is_local")):return
	var point:Vector3=boss.global_position+Vector3.UP*3.8 if is_instance_valid(boss) else Vector3.ZERO
	if data.get("pos") is Vector3:point=data.pos
	if bool(data.get("blocked",false)):
		if clock-_last_immune>.6:_last_immune=clock;_crit(point,"IMMUNE")
		return
	if bool(data.get("crab",false)):return
	var weak:bool=bool(data.get("weak",false));weak_left=.3 if weak else weak_left
	if _combo.is_empty() or clock-float(_combo.last)>.45:
		var number:Label=C.label(canvas,"0",0,0,20,4,1.75,true,SplatUiTheme.GOLD if weak else Color.WHITE);number.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;number.pivot_offset=number.size*.5
		_combo={"node":number,"world":point,"sum":0.0,"last":clock,"born":clock,"weak":weak,"jx":randf_range(-1,1)};_numbers.append(_combo)
		while _numbers.size()>6:
				var old:Dictionary=_numbers.pop_front()
				if is_instance_valid(old.node):old.node.queue_free()
	_combo.sum+=float(data.get("damage",0));_combo.last=clock;_combo.world=Vector3(_combo.world).lerp(point,.35);_combo.weak=bool(_combo.weak) or weak
	var text:Label=_combo.node as Label;text.text=str(roundi(float(_combo.sum)));text.add_theme_color_override("font_color",SplatUiTheme.GOLD if bool(_combo.weak) else Color.WHITE)
	var scale_factor:float=clampf(.85+log(maxf(1,float(_combo.sum)))/log(10)*.16+(.2 if bool(_combo.weak) else 0),.85,1.6);text.add_theme_font_size_override("font_size",roundi(1.75*12.8*scale_factor));_pop(text,.22,1.35)
	if weak and clock-_last_crit>.22:_last_crit=clock;_crit(point)

func _update_numbers()->void:
	for index:int in range(_numbers.size()-1,-1,-1):
		var row:Dictionary=_numbers[index];var age:float=clock-float(row.last);var node:Control=row.node as Control
		if age>1.05 or not is_instance_valid(node):
			if is_instance_valid(node):node.queue_free()
			_numbers.remove_at(index);continue
		var screen:Dictionary=_project(row.world)
		node.visible=not screen.is_empty() and not bool(screen.get("behind",false))
		if not node.visible:continue
		var rise:float=(clock-float(row.born))*1.6+maxf(0,age-.45)*5
		node.position=Vector2(screen.p)+Vector2(float(row.jx)*12.8,-(1.5+rise)*12.8)-node.size*.5;node.modulate.a=clampf(1-(age-.45)/.5,0,1)

func _crit(point:Vector3,text:String="CRIT!")->void:
	var screen:Dictionary=_project(point)
	if screen.is_empty() or bool(screen.behind):return
	var group:=Control.new();canvas.add_child(group);C.at(group,Vector2(screen.p).x/12.8-6,Vector2(screen.p).y/12.8-4.5,12,5);group.pivot_offset=group.size*.5
	if text=="CRIT!":C.icon(group,"boss_bar_splat",2.8,-.7,6.4,6.4).modulate=_colors()[0].lightened(.65)
	var words:Label=C.label(group,text,0,0,12,4,2.1 if text=="CRIT!" else 1.5,true,SplatUiTheme.GOLD if text=="CRIT!" else Color("c9c3d8"));words.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;words.rotation=deg_to_rad(-9)
	group.scale=Vector2.ONE*.3;group.modulate.a=0
	var tween:Tween=group.create_tween();tween.tween_property(group,"scale",Vector2.ONE*1.2,.112);tween.parallel().tween_property(group,"modulate:a",1.0,.112);tween.tween_property(group,"scale",Vector2.ONE,.096);tween.tween_interval(.352);tween.tween_property(group,"modulate:a",0.0,.24);tween.parallel().tween_property(group,"position:y",group.position.y-2.2*12.8,.24);tween.tween_callback(group.queue_free)

func _pop(node:Control,duration:float,from:float)->void:
	if not is_instance_valid(node):return
	node.scale=Vector2.ONE*from;node.pivot_offset=node.size*.5
	node.create_tween().tween_property(node,"scale",Vector2.ONE,duration).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func _letters(parent:Control,value:String,x:float,y:float,w:float,h:float,fs:float,start:float,interval:float)->void:
	var whole:float=SplatUiTheme.DISPLAY.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(fs*12.8)).x/12.8
	var left:float=x+(w-whole)*.5
	for index:int in value.length():
		var letter_w:float=SplatUiTheme.DISPLAY.get_string_size(value[index],HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(fs*12.8)).x/12.8
		var letter:Label=C.label(parent,value[index],left,y,letter_w+.2,h,fs,true);letter.pivot_offset=letter.size*.5;letter.scale=Vector2.ONE*2.6;letter.modulate.a=0;letter.rotation=deg_to_rad(14)
		var tween:Tween=letter.create_tween().set_parallel(true);tween.tween_property(letter,"scale",Vector2.ONE,.42).set_delay(start+index*interval).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);tween.tween_property(letter,"modulate:a",1.0,.168).set_delay(start+index*interval);tween.tween_property(letter,"rotation",0.0,.42).set_delay(start+index*interval);left+=letter_w

func _remove_later(node:Control,duration:float)->void:
	var tween:Tween=node.create_tween();tween.tween_interval(duration*.88);tween.tween_property(node,"modulate:a",0.0,duration*.12);tween.tween_callback(node.queue_free)

func _title_card()->void:
	var group:=Control.new();_over.add_child(group);C.at(group,0,height_u*.16,width_u,17)
	var color:Color=_colors()[1]
	var band:Control=_frame(group,-4,2.38,width_u+8,12.92,color,0);band.rotation=deg_to_rad(-3.5);band.scale.x=0;band.create_tween().tween_property(band,"scale:x",1.0,.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	C.icon(group,"boss_title_a",width_u*.08,-6.8,16,16).modulate=color;var second:TextureRect=C.icon(group,"boss_title_b",width_u*.93-16,8.82,16,16);second.modulate=color;second.rotation=deg_to_rad(70)
	var emblem:TextureRect=C.icon(group,"boss_emblem",width_u*.5-36,1,15,15);emblem.pivot_offset=emblem.size*.5;_pop(emblem,.66,.2)
	var words:=Control.new();group.add_child(words);C.at(words,width_u*.5-19,1.2,70,15);words.rotation=deg_to_rad(-3.5)
	var tag:Control=C.panel(words,0,0,14,2.2,SplatUiTheme.INK,.35);C.icon(tag,"glyph_swords",.5,.4,1.4,1.4).modulate=SplatUiTheme.GOLD;C.label(tag,"BOSS BATTLE",2.2,.1,11.2,2,1.05)
	C.label(words,"PUBLIC BETA",15,.35,11.3,1.5,.8)
	_letters(words,"HULLBREAKER",0,2.3,68,8,6.6,.16,.032)
	var ep:Control=C.panel(words,1.4,10.7,28.8,2.2,Color.WHITE,0);ep.rotation=deg_to_rad(-2.5);C.label(ep,"THE RUST-SHELLED TERROR",.8,.1,27.2,2,1.2,false,SplatUiTheme.INK)
	_remove_later(group,2.75)

func _phase_banner(next:int)->void:
	var group:=Control.new();_over.add_child(group);C.at(group,width_u*.5-37,height_u*.35-6,74,12);group.pivot_offset=group.size*.5
	C.icon(group,"boss_phase%d"%next,29,-2.4,15,15).modulate=_colors()[1]
	var tape:Control=C.panel(group,4,0,66,6.8,Color("c8173a") if next>=3 else SplatUiTheme.INK,0);tape.rotation=deg_to_rad(-3)
	C.label(tape,"SHELL CRACKED!" if next>=3 else "PHASE 2!",0,-.1,66,6.8,4.6,true,SplatUiTheme.GOLD if next>=3 else Color.WHITE).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var sub:Control=C.panel(group,15,7.0,44,2.5,Color.WHITE,1.25);sub.rotation=deg_to_rad(-1.5);C.label(sub,"Final phase · hit the glowing belly!" if next>=3 else "Crablets incoming — pop them fast!",.9,.15,42.2,2.2,1.15,false,SplatUiTheme.INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_pop(group,.61,2.2);_remove_later(group,2.9)

func _ending(win:bool)->void:
	if ended:return
	ended=true;_call.hide()
	for node:Node in _over.get_children():node.queue_free()
	var group:=Control.new();_over.add_child(group);C.at(group,width_u*.5-42,height_u*.43-9,84,18);group.pivot_offset=group.size*.5
	var colors:Array[Color]=_colors()
	var second:TextureRect=C.icon(group,"boss_end_win_b" if win else "boss_end_lose_b",19,-6.8,36,36);second.modulate=colors[1] if win else colors[0];second.rotation=deg_to_rad(25);_pop(second,1,.1)
	var splat:TextureRect=C.icon(group,"boss_end_win_a" if win else "boss_end_lose_a",24,-9,36,36);splat.modulate=colors[0] if win else colors[1];_pop(splat,1,.1)
	for index:int in 14:
		var angle:float=index*TAU/14+randf_range(0,.24);var diameter:float=2.6*randf_range(.5,1.4)
		var drop:Control=C.panel(group,42,9,diameter,diameter,colors[0] if win else colors[1],diameter*.45);drop.rotation=angle;drop.modulate.a=0
		var tween:Tween=drop.create_tween().set_parallel(true);tween.tween_property(drop,"modulate:a",1.0,.2).set_delay(.1);tween.tween_property(drop,"position",drop.position+Vector2(cos(angle),sin(angle))*30*12.8,randf_range(1.08,2.04)).set_delay(.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT);tween.chain().tween_property(drop,"modulate:a",0.0,.3)
	var who:Control=C.panel(group,26.0,0,32,2.7,SplatUiTheme.INK,.4);who.rotation=deg_to_rad(-3);C.label(who,"HULLBREAKER" if win else "HULLBREAKER GOT AWAY…",.8,.1,30.4,2.5,1.25).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var words:=Control.new();group.add_child(words);C.at(words,0,3,84,14);words.rotation=deg_to_rad(-5);_letters(words,"SUNK!" if win else "TIME'S UP!",0,0,84,14,11 if win else 8.5,.08,.045)
	var emblem:TextureRect=C.icon(group,"boss_emblem_cracked" if win else "boss_emblem",68,13,10,10);emblem.pivot_offset=emblem.size*.5;_pop(emblem,.8,.2)
	var motion:Tween=emblem.create_tween();motion.tween_interval(1.2)
	if win:
		motion.tween_property(emblem,"rotation",deg_to_rad(185),2.8);motion.parallel().tween_property(emblem,"position:y",emblem.position.y+6*12.8,2.8);motion.parallel().tween_property(emblem,"modulate:a",0.0,2.8)
	else:motion.tween_property(emblem,"position:x",emblem.position.x+width_u*.6*12.8,3.3).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	_remove_later(group,5.0)
