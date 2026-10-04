class_name SplatHudEvents
extends Control
const C=preload("res://scripts/ui/lab_canvas.gd")
var view:SplatLabCanvas
var game:Node
var frame:Dictionary={}
var clock:float=0
var cards:Array[Control]=[]
var callout:Control
var respawn_card:Control
var respawn_num:Label
var respawn_ring:ColorRect
var respawn_start:float=5
var kill_times:Array[float]=[]
var streak:int=0
var first:bool=false
var last_killer:Node
var dealt:Dictionary={}
var actor_streak:Dictionary={}
var direction_arcs:Array[Dictionary]=[]
var banner_node:Control
var countdown_node:Control
var lineup_node:Control
var prompt_node:Control
var prompt_text:String=""

func banner(text:String)->void:
	if text.is_valid_int():countdown(int(text));return
	if is_instance_valid(banner_node):banner_node.queue_free()
	var kind:String="ready" if text=="READY?" else "go" if text=="GO!" else "timesup" if text.contains("UP!") else "one_minute" if text.to_lower().contains("minute") else "special" if text.contains("SPECIAL") else "custom"
	var fs:float=7.0 if kind=="ready" else 13.0 if kind=="go" else 9.0 if kind=="timesup" else 2.6 if kind=="one_minute" else 3.1 if kind=="special" else 4.0
	var duration:float=1.5 if kind=="ready" else 1.25 if kind=="go" else 2.3 if kind=="timesup" else 2.8 if kind=="one_minute" else 1.15 if kind=="special" else 2.0
	var point:Vector2=Vector2(view.width_u*.5,view.height_u*(.22 if kind=="one_minute" else .25 if kind=="special" else .3 if kind=="custom" else .4))
	var group:=Control.new();view.canvas.add_child(group);banner_node=group;C.at(group,point.x-40,point.y-fs*.75,80,fs*1.5);group.pivot_offset=group.size*.5
	var color:Color=frame.get("team_color",SplatUiTheme.ORANGE)
	if kind in ["go","timesup"]:
		var dimension:float=34 if kind=="go" else 30
		if kind=="timesup":C.icon(group,"banner_timesup_b",40-dimension*.36,fs*.75-dimension*.46,dimension,dimension).modulate=frame.get("enemy_color",SplatUiTheme.BLUE)
		var splat:TextureRect=C.icon(group,"banner_go" if kind=="go" else "banner_timesup_a",40-dimension*(.5 if kind=="go" else .62),fs*.75-dimension*.5,dimension,dimension);splat.modulate=color;splat.pivot_offset=splat.size*.5;splat.scale=Vector2.ONE*.2;splat.rotation=deg_to_rad(-40)
		var splat_tween:Tween=splat.create_tween().set_parallel(true);splat_tween.tween_property(splat,"scale",Vector2.ONE, duration*.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);splat_tween.tween_property(splat,"rotation",0.0,duration*.18)
		if kind=="go":
			for index:int in 10:
				var drop:Control=C.panel(group,39.4,fs*.75-.6,1.2,2.4,color,.6);drop.pivot_offset=drop.size*.5
				var angle:float=index*TAU/10+.13;drop.rotation=angle;drop.modulate.a=0
				var tween:Tween=drop.create_tween().set_parallel(true);tween.tween_property(drop,"modulate:a",1.0,.10).set_delay(.08);tween.tween_property(drop,"position",drop.position+Vector2(sin(angle),-cos(angle))*26*12.8,1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT);tween.chain().tween_property(drop,"modulate:a",0.0,.2)
	if kind=="ready":
		var widths:Array[float]=[];var total:float=0
		for character_index:int in text.length():
			var width:float=SplatUiTheme.DISPLAY.get_string_size(text[character_index],HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(fs*12.8)).x/12.8;widths.append(width);total+=width
		var left:float=(80-total)*.5
		for index:int in text.length():
			var letter:Label=C.label(group,text[index],left,0,widths[index]+.2,fs*1.5,fs,true);letter.position.y-=fs*.6*12.8;letter.modulate.a=0;letter.pivot_offset=letter.size*.5;letter.scale=Vector2.ONE*.5
			var tween:Tween=letter.create_tween().set_parallel(true);tween.tween_property(letter,"position:y",0.0,.55).set_delay(index*.045).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);tween.tween_property(letter,"scale",Vector2.ONE,.55).set_delay(index*.045).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);tween.tween_property(letter,"modulate:a",1.0,.15).set_delay(index*.045);left+=widths[index]
	else:
		if kind=="one_minute":C.panel(group,24,0,32,fs*1.5,SplatUiTheme.INK,fs*.75);C.icon(group,"glyph_clock",24.5,.5,2.8,2.8).modulate=SplatUiTheme.GOLD
		var words:Label=C.label(group,text,0,0,80,fs*1.5,fs,true,color.lightened(.4) if kind=="special" else Color.WHITE);words.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;words.pivot_offset=words.size*.5;words.rotation=deg_to_rad(-6 if kind=="go" else -4 if kind=="timesup" else -3 if kind=="special" else 0)
		group.scale=Vector2.ONE*(2.4 if kind in ["go","timesup"] else .3);group.modulate.a=0
		var incoming:Tween=group.create_tween().set_parallel(true);incoming.tween_property(group,"scale",Vector2.ONE,duration*.28).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);incoming.tween_property(group,"modulate:a",1.0,duration*.12)
	var out:Tween=group.create_tween();out.tween_interval(duration*.78);out.tween_property(group,"modulate:a",0.0,duration*.22);out.tween_callback(group.queue_free)

func countdown(number:int)->void:
	if is_instance_valid(countdown_node):countdown_node.queue_free()
	var fs:float=12 if number<=3 else 9
	var color:Color=Color(frame.get("team_color",SplatUiTheme.ORANGE)).lightened(.4)
	var group:=Control.new();view.canvas.add_child(group);countdown_node=group;C.at(group,view.width_u*.5-fs*.8,view.height_u*.3-fs*.8,fs*1.6,fs*1.6);group.pivot_offset=group.size*.5
	var ring:Control=C.panel(group,0,0,fs*1.6,fs*1.6,Color.TRANSPARENT,fs*.8)
	var mat:ShaderMaterial=ring.material as ShaderMaterial;mat.set_shader_parameter("top_color",Color.TRANSPARENT);mat.set_shader_parameter("bottom_color",Color.TRANSPARENT);mat.set_shader_parameter("border_color",Color("ff5a6e") if number<=3 else color);mat.set_shader_parameter("border",fs*.08*12.8);ring.pivot_offset=ring.size*.5;ring.scale=Vector2.ONE*.4
	var ring_tween:Tween=ring.create_tween().set_parallel(true);ring_tween.tween_property(ring,"scale",Vector2.ONE*1.5,.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT);ring_tween.tween_property(ring,"modulate:a",0.0,.7)
	C.label(group,str(number),0,0,fs*1.6,fs*1.6,fs,true,color if number<=3 else Color.WHITE).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	group.scale=Vector2.ONE*2.2;group.modulate.a=0
	var tween:Tween=group.create_tween();tween.tween_property(group,"scale",Vector2.ONE*.88,.14);tween.parallel().tween_property(group,"modulate:a",1.0,.14);tween.tween_property(group,"scale",Vector2.ONE*1.06,.1);tween.tween_property(group,"scale",Vector2.ONE,.1);tween.tween_interval(.44);tween.tween_property(group,"modulate:a",0.0,.22);tween.parallel().tween_property(group,"scale",Vector2.ONE*.8,.22);tween.tween_callback(group.queue_free)

func configure(canvas_view:SplatLabCanvas,controller:Node)->void:
	view=canvas_view;game=controller
	mouse_filter=Control.MOUSE_FILTER_IGNORE

func name_of(actor:Variant)->String:
	if actor is Node and is_instance_valid(actor):
		var value:Variant=actor.get("display_name")
		return str(value) if value!=null else "Hullbreaker" if actor.has_method("damage_crablet") else str(actor.name)
	return str(actor.get("name","Squidkid")) if actor is Dictionary else "Squidkid"

func weapon_of(actor:Variant)->String:
	if actor is Node and is_instance_valid(actor):
		var value:Variant=actor.get("weapon_id")
		return str(value) if value!=null else "shooter"
	return str(actor.get("weapon","shooter")) if actor is Dictionary else "shooter"

func is_local(actor:Variant)->bool:
	if actor is Node:
		if not is_instance_valid(actor):return false
		var flag:Variant=actor.get("is_local")
		return flag!=null and bool(flag)
	return bool(actor.get("isSelf",false)) if actor is Dictionary else false

func team_of(actor:Variant)->int:
	if actor is Node and is_instance_valid(actor):
		var value:Variant=actor.get("team_id")
		return int(value) if value!=null else 1
	return int(actor.get("team",0)) if actor is Dictionary else 0

func team_color(team:int)->Color:
	return game.team_colors[team] if is_instance_valid(game) and game.get("team_colors") is Array else SplatUiTheme.ORANGE if team==0 else SplatUiTheme.BLUE

func on_event(kind:String,data:Dictionary)->void:
	var attacker:Variant=data.get("attacker");var victim:Variant=data.get("victim")
	if kind=="hit" and is_local(attacker) and victim is Node:dealt[victim.get_instance_id()]=clock
	if kind=="damage" and is_local(victim) and attacker is Node:
		direction_arcs.append({"actor":attacker,"until":clock+1.25})
	if kind=="respawn" and is_local(data.get("actor",victim)):hide_respawn()
	if kind!="splatted":return
	var old_streak:int=0
	if victim is Node:old_streak=int(actor_streak.get(victim.get_instance_id(),0));actor_streak[victim.get_instance_id()]=0
	if attacker is Node:actor_streak[attacker.get_instance_id()]=int(actor_streak.get(attacker.get_instance_id(),0))+1
	if is_local(victim):
		last_killer=attacker if attacker is Node else null;streak=0;direction_arcs.clear();show_respawn(attacker,float(data.get("respawn",5)));return
	if is_local(attacker):
		kill_times=kill_times.filter(func(time:float)->bool:return clock-time<4.2)
		kill_times.append(clock);streak+=1;kill_card(victim,false)
		var text:String="";var sub:String="";var enemies:Array=[]
		if is_instance_valid(game) and game.get("actors") is Array:enemies=game.actors.filter(func(actor:Node)->bool:return team_of(actor)!=team_of(attacker))
		if enemies.size()>=4 and enemies.all(func(actor:Node)->bool:return not bool(actor.get("alive"))):text="WIPEOUT!";sub="The whole team is splatted"
		elif kill_times.size()>=2:text=["DOUBLE SPLAT!","TRIPLE SPLAT!","QUAD SPLAT!"][mini(4,kill_times.size())-2]
		elif not first:text="FIRST SPLAT!"
		elif victim==last_killer:text="REVENGE!";last_killer=null
		elif old_streak>=3:text="SHUTDOWN!";sub="Ended %s’s streak"%name_of(victim)
		elif streak>=3 and streak%2==1:text="SPLAT STREAK ×%d"%streak
		first=true
		if not text.is_empty():show_callout(text,sub,kill_times.size()>=3 or text=="WIPEOUT!")
	elif victim is Node and attacker is Node and is_instance_valid(game) and game.get("local_player")!=null and team_of(attacker)==team_of(game.local_player) and clock-float(dealt.get(victim.get_instance_id(),-99))<4:
		kill_card(victim,true);dealt.erase(victim.get_instance_id())

func kill_card(victim:Variant,assist:bool)->void:
	var card:Control=C.panel(view.canvas,view.width_u*.5-12,view.height_u-6.7,24,4.5,SplatUiTheme.INK,2.25)
	(card.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(card.material as ShaderMaterial).set_shader_parameter("border",2.5)
	C.icon(card,"splat",-1.6,-1.25,7,7).modulate=frame.get("team_color",SplatUiTheme.ORANGE)
	C.panel(card,.5,.45,3.6,3.6,team_color(team_of(victim)),1.8)
	C.icon(card,"weaponw_"+weapon_of(victim),.93,.88,2.74,2.74)
	C.label(card,"ASSIST" if assist else "SPLATTED",4.9,.45,17.7,1.2,.78,false,Color("cfc8e2") if assist else SplatUiTheme.ORANGE.lightened(.3))
	C.label(card,name_of(victim),4.9,1.8,17.7,2.1,1.7,true)
	card.set_meta("end",clock+(1.7 if assist else 2.2));card.scale=Vector2.ONE*.3;card.pivot_offset=card.size*.5
	card.create_tween().tween_property(card,"scale",Vector2.ONE*(.82 if assist else 1.0),.5).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	for earlier:Control in cards:earlier.position.y-=3.7*12.8;earlier.scale=Vector2.ONE*.8;earlier.modulate.a=.8
	cards.push_front(card)
	while cards.size()>2:(cards.pop_back() as Control).queue_free()

func show_callout(text:String,sub:String="",big:bool=false)->void:
	if is_instance_valid(callout):callout.queue_free()
	callout=Control.new();view.canvas.add_child(callout);C.at(callout,view.width_u*.5-27,view.height_u*.27-3,54,7)
	var ribbon:Control=C.panel(callout,0,.4,54,4.8 if big else 3.6,frame.get("team_color",SplatUiTheme.ORANGE),0);ribbon.rotation=deg_to_rad(-3)
	C.label(callout,text,0,-.2,54,5.4,4.4 if big else 3.3,true).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	C.label(callout,sub,0,5.4,54,1.4,.95).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	callout.pivot_offset=callout.size*.5;callout.scale=Vector2.ONE*2.2
	var tween:Tween=callout.create_tween();tween.tween_property(callout,"scale",Vector2.ONE,.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);tween.tween_interval(1.4);tween.tween_property(callout,"modulate:a",0.0,.45);tween.tween_callback(callout.queue_free)

func show_respawn(killer:Variant,seconds:float)->void:
	hide_respawn();respawn_start=maxf(.1,seconds)
	respawn_card=Control.new();view.canvas.add_child(respawn_card);C.at(respawn_card,view.width_u*.5-25,view.height_u*.83-8,50,12)
	C.icon(respawn_card,"splat",2,-7,38,26).modulate=team_color(team_of(killer))
	C.panel(respawn_card,0,1,6.4,6.4,team_color(team_of(killer)),3.2)
	C.icon(respawn_card,"weaponw_"+weapon_of(killer),.77,1.77,4.86,4.86)
	C.panel(respawn_card,8.8,.7,17,2.0,SplatUiTheme.INK,.4)
	C.label(respawn_card,"SPLATTED BY" if killer!=null else "SPLATTED!",9.5,.8,16,1.8,1.1)
	C.label(respawn_card,name_of(killer) if killer!=null else "",8.8,3,31,5.0,4.4,true)
	C.label(respawn_card,str(SplatUiTheme.catalog().weapons.get(weapon_of(killer),{}).get("name","")),8.8,8.1,30,1.4,.95)
	respawn_ring=ColorRect.new();respawn_ring.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var mat:=ShaderMaterial.new();mat.shader=preload("res://assets/ui/lab_respawn.gdshader");respawn_ring.material=mat
	respawn_card.add_child(respawn_ring);C.at(respawn_ring,42,1,7.6,7.6)
	respawn_num=C.label(respawn_ring,str(ceili(seconds)),0,0,7.6,7.6,3.0,true);respawn_num.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	C.label(respawn_ring,"RESPAWN",-.4,8.0,8.4,1.2,.8).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	C.label(respawn_card,"Hold TAB to plan a Super Jump",3,13,44,2,.95).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	SplatUiTheme.enter(respawn_card)

func hide_respawn()->void:
	if is_instance_valid(respawn_card):respawn_card.queue_free()
	respawn_card=null

func show_intro(options:Dictionary,actors:Array)->void:
	if is_instance_valid(lineup_node):lineup_node.queue_free()
	var group:=Control.new();view.canvas.add_child(group);lineup_node=group;C.at(group,0,0,view.width_u,view.height_u)
	var boss:bool=str(options.get("mode","turf"))=="boss"
	var colors:Array=game.get("team_colors") if is_instance_valid(game) and game.get("team_colors") is Array else options.get("colors",[SplatUiTheme.ORANGE,SplatUiTheme.BLUE]) as Array
	var names:Array=options.get("teamNames",options.get("team_names",["Tangerine","Cobalt"])) as Array
	var left:float=view.width_u*.5-31.1
	var top:float=view.height_u*.91-20.3
	for team:int in 2:
		var list:Array=actors.filter(func(actor:Variant)->bool:return team_of(actor)==team)
		var x:float=left+team*38.2
		C.label(group,"YOUR SQUAD" if boss and team==0 else "HULLBREAKER" if boss else str(names[team]).to_upper(),x,top,24,2.5,2.1,true,colors[team] if colors[team] is Color else Color(str(colors[team])))
		if boss and team==1:C.icon(group,"boss_emblem",x+2.5,top+4,19,14);continue
		for index:int in mini(8 if boss else 4,list.size()):
			var actor:Variant=list[index]
			var card:Control=C.panel(group,x+(.7*index*(1 if team==1 else -1))+(floori(index/4.0)*-20 if boss else 0),top+3+(index%4)*4.65,21,4.1,Color(team_color(team),.35) if is_local(actor) else Color(.055,.043,.086,.86),1.1)
			(card.material as ShaderMaterial).set_shader_parameter("border_color",team_color(team));(card.material as ShaderMaterial).set_shader_parameter("border",2.5 if is_local(actor) else 2.0)
			C.panel(card,.45,.4,3.3,3.3,team_color(team),1.65);C.icon(card,"weaponw_"+weapon_of(actor),.8,.75,2.6,2.6)
			C.label(card,name_of(actor),4.55,.3,15.3,1.9,1.35,true)
			C.label(card,str(SplatUiTheme.catalog().weapons.get(weapon_of(actor),{}).get("name","")),4.55,2.3,15.3,1.1,.8)
			if is_local(actor):C.label(card,"YOU",17.6,.3,3.1,1.9,.7,false,SplatUiTheme.GOLD)
			SplatUiTheme.enter(card,.15+index*.08)
	C.icon(group,"splat",left+25.8,top+7,9,9).modulate=Color.WHITE
	C.label(group,"VS",left+25.8,top+8,9,6,3.6,false,SplatUiTheme.INK).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var tween:Tween=group.create_tween();tween.tween_interval(1.65 if boss else 2.9);tween.tween_property(group,"modulate:a",0.0,.45);tween.tween_callback(group.queue_free)

func update_frame(value:Dictionary)->void:
	frame=value
	_update_prompt(str(frame.get("prompt","")))
	var seconds:float=float(frame.get("respawn",0))
	if seconds>0 and respawn_card==null:show_respawn(last_killer,seconds)
	elif seconds<=0 and respawn_card!=null:hide_respawn()
	if is_instance_valid(respawn_card):
		respawn_num.text=str(ceili(seconds));(respawn_ring.material as ShaderMaterial).set_shader_parameter("progress",1-seconds/respawn_start)
		respawn_card.visible=not bool(view.get_parent().get("_map_open"))

func _update_prompt(text:String)->void:
	if prompt_text!=text:
		prompt_text=text
		if is_instance_valid(prompt_node):prompt_node.queue_free()
		prompt_node=null
		if not text.is_empty():
			prompt_node=C.panel(view.canvas,0,view.height_u-6.0,1,3.4,Color(.055,.043,.086,.8),1.7)
			var cursor:float=1.1;var offset:int=0
			var expression:=RegEx.new();expression.compile("\\[([^\\]]+)\\]")
			var tokens:Array[RegExMatch]=expression.search_all(text)
			for token:RegExMatch in tokens:
				cursor=_prompt_words(text.substr(offset,token.get_start()-offset),cursor)
				cursor+=C.keycap(prompt_node,token.get_string(1),cursor,.75,.94)
				offset=token.get_end()
			cursor=_prompt_words(text.substr(offset),cursor)+1.1
			C.at(prompt_node,(view.width_u-cursor)*.5,view.height_u-2.6-3.4,cursor,3.4)
			(prompt_node.material as ShaderMaterial).set_shader_parameter("panel_size",prompt_node.size)
			prompt_node.pivot_offset=prompt_node.size*.5;prompt_node.scale=Vector2.ONE*.85;prompt_node.modulate.a=0
			var incoming:Tween=prompt_node.create_tween().set_parallel(true);incoming.tween_property(prompt_node,"scale",Vector2.ONE,.38).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);incoming.tween_property(prompt_node,"modulate:a",1.,.2)
	if is_instance_valid(prompt_node):prompt_node.visible=not bool(view.get_parent().get("_map_open")) and cards.is_empty() and is_instance_valid(view.get_parent()) and bool(view.get_parent().get("_chrome").visible)

func _prompt_words(text:String,cursor:float)->float:
	if text.is_empty():return cursor
	var font:Font=preload("res://assets/fonts/ink_body_700_font.tres")
	var width:float=font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,14).x/12.8
	var word:Label=C.label(prompt_node,text,cursor,.6,width+.05,2.1,1.1);word.add_theme_font_override("font",font)
	return cursor+width+.10

func _process(delta:float)->void:
	clock+=delta
	_update_prompt(prompt_text)
	for index:int in range(cards.size()-1,-1,-1):
		var card:Control=cards[index]
		if clock>=float(card.get_meta("end",0)):
			cards.remove_at(index);card.create_tween().tween_property(card,"modulate:a",0.0,.4).finished.connect(card.queue_free)
	queue_redraw()

func _draw()->void:
	if not is_instance_valid(game) or game.get("local_player")==null:return
	var local:Node3D=game.local_player as Node3D
	for index:int in range(direction_arcs.size()-1,-1,-1):
		var item:Dictionary=direction_arcs[index]
		if clock>float(item.until) or not is_instance_valid(item.actor):direction_arcs.remove_at(index);continue
		var delta:Vector3=(item.actor as Node3D).global_position-local.global_position
		var a:float=atan2(delta.x,delta.z)-float(local.get("aim_yaw"))-PI*.5
		var center:Vector2=get_viewport().get_visible_rect().size*.5
		draw_arc(center,84,a-.45,a+.45,18,Color(frame.get("enemy_color",SplatUiTheme.BLUE),clampf(float(item.until)-clock,0,1)),9,true)
