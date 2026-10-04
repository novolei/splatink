class_name SplatLabResults
extends SplatLabCanvas
const C=preload("res://scripts/ui/lab_canvas.gd")
const L=preload("res://scripts/ui/lab_screens.gd")
const O:=Color("ff8a14")
const B:=Color("2f5bff")
const K:=Color("15121c")
var host:InkUI
var stats:Dictionary
var body:Control
var clock:float=-2.3
var done:bool=false
var won:bool=false
var boss:bool=false
var percent_a:Label
var percent_b:Label
var cover_a:Control
var cover_b:Control
var cover_material:ShaderMaterial
var rows:Array[Dictionary]=[]
var medals:Array[Control]=[]
var xp_label:Label
var xp_next:Label
var xp_level:Label
var xp_fill:Control
var xp:Dictionary
var xp_up:Label
var _xp_steps:Array[Dictionary]=[]
var _xp_step:int=0
var _xp_current:float=0
var _xp_added:float=0
var _xp_pause:float=0
var _xp_total:float=0
var pa:float=50
var pb:float=50
var palette:Array[Color]=[O,B]
var room_count:Label
var room_ring:ColorRect
var _room_age:float=0

func build(controller:InkUI,result:Dictionary)->void:
	host=controller;stats=result;won=bool(result.get("won",result.get("win",false)));boss=str(result.get("mode","turf"))=="boss"
	if bool(host.settings.reduce_motion):clock=0
	var percents:Array=result.get("percents",[result.get("percent_a",50),result.get("percent_b",50)]) as Array
	pa=float(percents[0]);pb=float(percents[1])
	if pa<=1 and pb<=1:pa*=100;pb*=100
	var colors:Array=result.get("colors",[O,B]) as Array
	for index:int in 2:palette[index]=colors[index] if colors[index] is Color else Color(str(colors[index]))
	var players:Array=(result.get("players",result.get("roster",[])) as Array).duplicate(true)
	for index:int in players.size():
		var player:Dictionary=players[index]
		if not player.has("team"):player.team=0 if boss or index<4 else 1
		if not player.has("isSelf"):player.isSelf=str(player.get("name",""))==str(host.profile.name)
		if not player.has("turf"):player.turf=player.get("points",0)
	var awards:Dictionary=SplatResultsAwards.compute(players,won,[pa,pb],boss)
	var my_awards:Array=[]
	for index:int in players.size():
		players[index].awards=awards.byPlayer[index]
		if bool(players[index].get("isSelf",false)):my_awards=awards.byPlayer[index]
	players.sort_custom(func(a:Dictionary,b:Dictionary)->bool:
		if boss:return float(a.get("damage",0))>float(b.get("damage",0))
		return int(a.team)<int(b.team) if int(a.team)!=int(b.team) else float(a.get("turf",0))>float(b.get("turf",0)))
	var scrim:=ColorRect.new();scrim.mouse_filter=Control.MOUSE_FILTER_IGNORE;canvas.add_child(scrim);C.at(scrim,0,0,width_u,height_u)
	var scrim_material:=ShaderMaterial.new();scrim_material.shader=preload("res://assets/ui/lab_result_scrim.gdshader");scrim.material=scrim_material
	C.icon(canvas,"splat",.4,-4,27,27)
	C.label(canvas,"VICTORY!" if won else "DEFEAT",3.8,1.6,75,8,6.6,true,Color.WHITE if won else Color("ece8f6"))
	var map_name:String=str(result.get("mapName",""))
	if map_name.is_empty():
		for map:Dictionary in SplatUiTheme.catalog().maps:
			if str(map.id)==str(host.options.get("map","tidewater")):map_name=str(map.name)
	var meta:Control=C.panel(canvas,3.8,10,28,2.1,K,1.05)
	C.icon(meta,"glyph_map",.6,.25,1.5,1.5)
	C.label(meta,map_name+" · "+("Boss Battle" if boss else "Turf War"),2.4,.1,25.2,1.9,.95)
	for index:int in awards.match.size():
		var tag:Dictionary=awards.match[index]
		var chip:Control=C.panel(canvas,32.8+index*18,10,17.5,2.1,O if str(tag.id)=="landslide" else SplatUiTheme.GOLD,1)
		C.label(chip,str(tag.label)+" "+str(tag.value),.65,.1,16.2,1.9,.85,false,K)
	var aw_count:int=mini(4,my_awards.size())
	if aw_count>0:C.label(canvas,"YOUR MEDALS",width_u-20.8,2.6,17,1.6,.8).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	for index:int in aw_count:
		var medal:Control=medal(my_awards[index],width_u-20.8+(index%2)*8.8,5.0+floori(index/2.0)*9.9)
		medals.append(medal)
	body=Control.new();canvas.add_child(body);C.at(body,3.8,height_u*.46,width_u-7.6,height_u*.54-5.6)
	var names:Array=result.get("teamNames",["Tangerine","Cobalt"]) as Array
	var cw:float=width_u-7.6
	if boss:
		var boss_stats:Dictionary=result.get("boss",{}) as Dictionary
		C.icon(body,"boss_emblem",.3,-.3,5.6,5.6)
		C.label(body,"HULLBREAKER",7,.0,cw-27,2,2.0,true)
		C.label(body,"PHASE %d   HP %d%%"%[int(boss_stats.get("phase",1)),roundi(float(boss_stats.get("hpLeft",0 if won else 1))*100)],7,2.2,cw-27,1.1,.8)
		C.bar(body,7,3.8,cw-32,1.1,float(boss_stats.get("hpLeft",0 if won else 1)),palette[1])
		C.label(body,"SUNK!" if won else "ESCAPED",cw-23,0,23,3.0,2.4,true)
		C.label(body,"CLEAR TIME" if won else "TIME UP",cw-23,3.2,23,1.0,.65)
		C.label(body,time_text(float(boss_stats.get("time",0))),cw-10,3.0,10,2,1.4,true)
	else:
		C.label(body,str(names[0]),2.9,0,cw*.5-4,2,1.7,true,palette[0])
		percent_a=C.label(body,"0.0%",13.3,0,10,2,1.7,true)
		C.label(body,str(names[1]),cw-20,0,20,2,1.7,true,palette[1]).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		percent_b=C.label(body,"0.0%",cw-12.3,0,6.2,2,1.7,true)
		var cover:=ColorRect.new();cover.mouse_filter=Control.MOUSE_FILTER_IGNORE;body.add_child(cover);C.at(cover,-7.0/12.8,2.6-7.0/12.8,cw+14.0/12.8,2.2+18.0/12.8)
		cover_material=ShaderMaterial.new();cover_material.shader=preload("res://assets/ui/lab_result_cover.gdshader");cover.material=cover_material
		cover_material.set_shader_parameter("panel_size",cover.size);cover_material.set_shader_parameter("team_a",palette[0]);cover_material.set_shader_parameter("team_b",palette[1]);cover_material.set_shader_parameter("percent_a",pa*.01);cover_material.set_shader_parameter("percent_b",pb*.01)
	var table_w:float=(cw-2.6)*.5
	for team:int in 2:
		var table:Control=Control.new();body.add_child(table);C.at(table,team*(table_w+2.6),6.5,table_w,13)
		C.label(table,"SQUAD · TOP 4" if boss and team==0 else "SQUAD · 5–8" if boss else str(names[team]).to_upper(),.5,0,table_w-22,1.2,.8,false,palette[0] if boss else palette[team])
		C.label(table,"DAMAGE" if boss else "TURF",table_w-21.5 if boss else table_w-17.5,0,6.4 if boss else 8,1.2,.7)
		if boss:
			C.icon(table,"glyph_target",table_w-14.6,-.1,1.6,1.6)
			C.icon(table,"splat_icon",table_w-11.5,-.1,1.6,1.6)
			C.icon(table,"death_icon",table_w-8.4,-.1,1.6,1.6)
			C.label(table,"TURF",table_w-5.3,0,4.3,1.2,.7)
		else:
			C.icon(table,"splat_icon",table_w-7.4,-.1,1.6,1.6)
			C.icon(table,"death_icon",table_w-3.5,-.1,1.6,1.6)
		var selected:Array=players.slice(team*4,team*4+4) if boss else players.filter(func(player:Dictionary)->bool:return int(player.team)==team)
		var best:float=maxf(1,SplatResultsAwards.maximum(selected,"damage" if boss else "turf"))
		for rank:int in mini(4,selected.size()):row(table,selected[rank],rank,table_w,best,palette[0] if boss else palette[team])
	var foot_y:float=height_u*.54-10.7
	var online:bool=is_instance_valid(host.main) and host.main.get("network")!=null and bool(host.main.network.get("active"))
	var room_host:bool=online and bool(host.main.network.get("is_authority"))
	var xp_width:float=minf(50,width_u*.48)
	if online:xp_width=minf(xp_width,cw-56.2 if room_host else cw-36.8)
	var xp_panel:Control=C.panel(body,0,foot_y,xp_width,4.8)
	xp={"gained":0,"levelBefore":1,"levelAfter":1,"xpBefore":0,"xpAfter":0,"xpToNextBefore":1000,"xpToNextAfter":1000}
	if result.get("xpObj") is Dictionary:xp.merge(result.xpObj,true)
	elif result.get("xp") is Dictionary:xp.merge(result.xp,true)
	else:xp.gained=int(result.get("xp",0));xp.levelBefore=int(result.get("level",1));xp.levelAfter=xp.levelBefore;xp.xpAfter=xp.gained
	C.panel(xp_panel,1.0,.9,7.8,2.6,Color.WHITE,.5)
	xp_level=C.label(xp_panel,"LV %d"%int(xp.levelBefore),1.5,1.0,8,2.5,2.1,false,K)
	xp_label=C.label(xp_panel,"+0 XP",10,.8,18,1.8,1.75,true)
	xp_next=C.label(xp_panel,"",28,.9,xp_width-29,1.4,.7)
	xp_up=C.label(xp_panel,"LEVEL UP!",25.5,.3,10.5,1.5,1.1,true,O);xp_up.hide()
	var track:Control=C.bar(xp_panel,10,2.8,xp_width-11.5,1.4,0,palette[0]);xp_fill=track.get_child(0) as Control
	build_xp_steps()
	if online:
		var pill:Control=C.panel(body,xp_width+1.2,foot_y,15.6,4.8,palette[0],1.3)
		room_ring=ColorRect.new();pill.add_child(room_ring);C.at(room_ring,.8,.75,3.3,3.3)
		var mat:=ShaderMaterial.new();mat.shader=preload("res://assets/ui/lab_respawn.gdshader");mat.set_shader_parameter("color",K);room_ring.material=mat
		C.label(pill,"BACK TO THE ROOM IN",5,.7,10.0,1,.66,false,K)
		room_count=C.label(pill,"12",5,1.8,10,2.2,2.1,true,K)
	var rematch:Callable=func()->void:
		if not done:finish_counts();return
		if online:host.online_requested.emit({"action":"return_lobby"})
		else:host.start_match()
	var home:Callable=func()->void:
		if not done:finish_counts();return
		host.exit_requested.emit();host.show_menu()
	if not online or room_host:
		var first_button:SplatInkButton=C.button(body,"TO THE ROOM" if online else "REMATCH",rematch,cw-35.8,foot_y+.1,17.4,4.6,1.7,"glyph_users" if online else "glyph_reset","Everyone comes with you" if online else "",true,Color("d9ff00") if online else palette[0])
		C.defer_focus(first_button)
	var leave:SplatInkButton=C.button(body,"LEAVE ROOM" if online else "MAIN MENU",func()->void:confirm_leave() if online else home.call(),cw-17.2,foot_y+.1,17.2,4.6,1.7,"glyph_exit" if online else "glyph_back")
	if online and not room_host:C.defer_focus(leave)
	L.prompts(self,"Enter  Skip · Select     ← → Move",25)
	if clock<0:body.position.y+=34*12.8;body.modulate.a=0
	if bool(host.settings.reduce_motion):finish_counts()

func confirm_leave()->void:
	if not done:finish_counts();return
	host.confirm("LEAVE ROOM?","You’ll head back to the main menu. Your friends stay in the room.",func()->void:host.exit_requested.emit();host.show_menu())

func row(parent:Control,p:Dictionary,rank:int,w:float,best:float,color:Color)->void:
	var panel:Control=C.panel(parent,0,1.7+rank*2.68,w,2.42,Color(color,.3) if bool(p.get("isSelf",false)) else Color(1,1,1,.06),.9)
	if bool(p.get("isSelf",false)):(panel.material as ShaderMaterial).set_shader_parameter("border_color",color);(panel.material as ShaderMaterial).set_shader_parameter("border",2.0)
	C.icon(panel,"weaponw_"+str(p.get("weapon","shooter")),.5,.05,2.7,2.3).modulate=color
	var player_name:Label=C.label(panel,str(p.get("name","Fresh Kid")),3.8,.1,w-26 if boss else w-23,2.2,1.1);player_name.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"))
	if boss:
		var rank_chip:Control=C.panel(panel,3.5,.45,1.45,1.45,SplatUiTheme.GOLD if rank==0 and float(p.get("damage",0))==best else Color(1,1,1,.12),.725)
		C.label(rank_chip,str(rank+1+(4 if parent.position.x>0 else 0)),0,0,1.45,1.45,.8,false,K if rank==0 else Color.WHITE).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		C.at(player_name,5.5,.1,w-28,2.2)
	if bool(p.get("isSelf",false)):
		var badge_x:float=minf(w-(24 if boss else 23),3.8+SplatUiTheme.BODY.get_string_size(str(p.get("name","")),HORIZONTAL_ALIGNMENT_LEFT,-1,14).x/12.8+.6)
		C.panel(panel,badge_x,.55,2.8,1.3,Color.WHITE,.4);C.label(panel,"YOU",badge_x+.2,.55,2.4,1.3,.65,false,K)
	var target:float=float(p.get("damage",0)) if boss else float(p.get("turf",0))
	var number:Label=C.label(panel,"0",w-21.5 if boss else w-17.5,.1,6.4 if boss else 8,2.2,1.35,true)
	number.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	C.label(panel,"p" if not boss else "",w-9.4,.75,1.2,1.2,.7)
	var splats:Label=C.label(panel,str(p.get("splats",0)),w-11.5 if boss else w-7.9,.1,2.6 if boss else 3.3,2.2,1.35,true)
	var deaths:Label=C.label(panel,str(p.get("deaths",0)),w-8.4 if boss else w-4.0,.1,2.6 if boss else 3.3,2.2,1.35,true)
	if boss:
		C.label(panel,str(p.get("weakHits",0)),w-14.6,.1,2.6,2.2,1.35,true)
		C.label(panel,"%dp"%int(p.get("turf",0)),w-5.3,.1,4.3,2.2,1.1,true).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var fill:Control=C.panel(panel,w-21.5 if boss else w-17.5,2.0,(6.4 if boss else 8)*target/best,.28,color,.14)
	fill.scale.x=0;splats.modulate.a=0;deaths.modulate.a=0
	rows.append({"target":target,"number":number,"fill":fill,"counts":[splats,deaths],"start":.8+rank*.13})
	var awards:Array=p.get("awards",[]) as Array
	if awards.any(func(award:Dictionary)->bool:return str(award.get("id",""))=="mvp"):
		(panel.material as ShaderMaterial).set_shader_parameter("border_color",SplatUiTheme.GOLD);(panel.material as ShaderMaterial).set_shader_parameter("border",2.0)
	for index:int in mini(3,awards.size()):
		var chip:Control=mini_medal(panel,awards[index],w-23.5-index*1.85,.35)
		chip.modulate.a=0;chip.set_meta("at",2.05+(rank*3+index)*.07);medals.append(chip)

func mini_medal(parent:Node,award:Dictionary,x:float,y:float)->Control:
	var disc:=ColorRect.new();disc.mouse_filter=Control.MOUSE_FILTER_IGNORE
	disc.material=metal_material(str(award.metal));parent.add_child(disc);C.at(disc,x,y,1.7,1.7)
	C.icon(disc,"award_"+str(award.icon),.27,.27,1.16,1.16).modulate=metal_color(str(award.metal))
	return disc

func medal(award:Dictionary,x:float,y:float)->Control:
	var group:=Control.new();canvas.add_child(group);C.at(group,x,y,8.2,9.6)
	C.icon(group,"splat",-.1,-.7,8.4,8.4)
	for side:int in [-1,1]:
		var ribbon:Control=C.panel(group,3.2+side*.8,0,1.6,3.1,palette[0],0);ribbon.rotation=deg_to_rad(side*-16)
	var disc:=ColorRect.new();disc.mouse_filter=Control.MOUSE_FILTER_IGNORE;disc.material=metal_material(str(award.metal));group.add_child(disc);C.at(disc,1.5,.9,5.2,5.2)
	C.icon(disc,"award_"+str(award.icon),1.09,1.09,3.02,3.02).modulate=metal_color(str(award.metal))
	C.panel(group,.0,6.65,8.2,1.4,K,.4)
	C.label(group,str(award.label),0,6.65,8.2,1.4,.9).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	C.label(group,str(award.value),-1,8.1,10.2,1.1,.68).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	group.tooltip_text=str(award.desc);group.modulate.a=0;group.set_meta("at",2.5+medals.size()*.5)
	return group

func metal_material(kind:String)->ShaderMaterial:
	var mat:=ShaderMaterial.new();mat.shader=preload("res://assets/ui/lab_medal.gdshader")
	if kind=="silver":mat.set_shader_parameter("light",Color.WHITE);mat.set_shader_parameter("metal",Color("b9c3d8"));mat.set_shader_parameter("dark",Color("5d6780"))
	elif kind=="bronze":mat.set_shader_parameter("light",Color("ffd3b0"));mat.set_shader_parameter("metal",Color("d9824a"));mat.set_shader_parameter("dark",Color("7a3e18"))
	return mat

func metal_color(kind:String)->Color:
	return Color("5d6780") if kind=="silver" else Color("7a3e18") if kind=="bronze" else Color("9a5c08")

func build_xp_steps()->void:
	var lb:int=int(xp.levelBefore);var la:int=maxi(lb,int(xp.levelAfter))
	if la>lb:
		_xp_steps.append({"lv":lb,"from":float(xp.xpBefore),"to":float(xp.xpToNextBefore),"max":float(xp.xpToNextBefore),"up":true})
		for level:int in range(lb+1,la):
			var max_xp:float=800+level*350
			_xp_steps.append({"lv":level,"from":0.0,"to":max_xp,"max":max_xp,"up":true})
		_xp_steps.append({"lv":la,"from":0.0,"to":float(xp.xpAfter),"max":float(xp.xpToNextAfter),"up":false})
	else:_xp_steps.append({"lv":lb,"from":float(xp.xpBefore),"to":float(xp.xpAfter),"max":float(xp.xpToNextBefore),"up":false})
	_xp_current=float(_xp_steps[0].from)
	for step:Dictionary in _xp_steps:_xp_total+=maxf(0,float(step.to)-float(step.from))
	set_xp(_xp_current,float(_xp_steps[0].max))

func set_xp(value:float,maximum:float)->void:
	xp_fill.scale.x=clampf(value/maxf(1,maximum),0,1)
	# The fill was created at zero width; native geometry must remain the full track width before scaling.
	xp_fill.size.x=(xp_fill.get_parent() as Control).size.x
	(xp_fill.material as ShaderMaterial).set_shader_parameter("panel_size",xp_fill.size)
	xp_next.text="%d XP to next level"%maxi(0,roundi(maximum-value))

func finish_counts()->void:
	done=true;clock=100
	body.position.y=height_u*.46*12.8;body.modulate.a=1
	set_coverage(1)
	for item:Dictionary in rows:set_row(item,1)
	for medal_node:Control in medals:medal_node.modulate.a=1;medal_node.scale=Vector2.ONE
	var last:Dictionary=_xp_steps.back()
	xp_level.text="LV %d"%int(last.lv);set_xp(float(last.to),float(last.max));xp_label.text="+%d XP"%int(xp.gained)
	xp_up.visible=int(xp.levelAfter)>int(xp.levelBefore)

func set_coverage(k:float)->void:
	if boss:return
	percent_a.text="%.1f%%"%(pa*k);percent_b.text="%.1f%%"%(pb*k)
	if cover_material:cover_material.set_shader_parameter("progress",k)

func set_row(item:Dictionary,k:float)->void:
	(item.number as Label).text=str(roundi(float(item.target)*k));(item.fill as Control).scale.x=k
	for node:Label in item.counts:node.modulate.a=k

func _process(delta:float)->void:
	if room_count:
		_room_age+=delta
		room_count.text=str(ceili(maxf(0,12-_room_age))) if _room_age<12 else "…"
		(room_ring.material as ShaderMaterial).set_shader_parameter("progress",clampf(1-_room_age/12,0,1))
	if done:return
	clock+=delta
	if clock<0:return
	if body.modulate.a==0:
		var tween:Tween=create_tween().set_parallel(true)
		tween.tween_property(body,"position:y",height_u*.46*12.8,.75).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(body,"modulate:a",1.0,.35)
	set_coverage(1-pow(1-clampf((clock-.45)/.9,0,1),3))
	for item:Dictionary in rows:set_row(item,1-pow(1-clampf((clock-float(item.start))/.75,0,1),3))
	for medal_node:Control in medals:
		if clock>=float(medal_node.get_meta("at",2.4)) and medal_node.modulate.a==0:
			medal_node.modulate.a=1;medal_node.scale=Vector2.ONE*2.3;medal_node.pivot_offset=medal_node.size*.5
			create_tween().tween_property(medal_node,"scale",Vector2.ONE,.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if clock<4.2:return
	if _xp_pause>0:_xp_pause-=delta;return
	var seg:Dictionary=_xp_steps[_xp_step]
	var step:float=minf(maxf(_xp_total/1.7,300)*delta,float(seg.to)-_xp_current)
	_xp_current+=step;_xp_added+=step;set_xp(_xp_current,float(seg.max));xp_label.text="+%d XP"%roundi(float(xp.gained)*clampf(_xp_added/maxf(1,_xp_total),0,1))
	if _xp_current>=float(seg.to)-1e-6:
		if bool(seg.up):
			_xp_step+=1;var next:Dictionary=_xp_steps[_xp_step];_xp_current=float(next.from);xp_level.text="LV %d"%int(next.lv);xp_up.show();_xp_pause=.75
		else:finish_counts()

static func time_text(value:float)->String:
	return "%d:%02d"%[floori(maxf(0,value)/60),floori(maxf(0,value))%60]
