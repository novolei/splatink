class_name SplatLabPause
extends SplatLabCanvas
## Source menus.js _scr_pause + _matchSnapshot; reads the actual match while online.
const C=preload("res://scripts/ui/lab_canvas.gd")
const L=preload("res://scripts/ui/lab_screens.gd")
const K=Color("15121c")
var host:InkUI
var clock_label:Label
var clock_ring:ShaderMaterial
var values:Array[Label]=[]
var rows:Array[Dictionary]=[]
var special_bar:Control
var _refresh:float=0
var online:bool=false

func build(ui:InkUI)->void:
	host=ui
	online=is_instance_valid(host.main) and is_instance_valid(host.main.get("network")) and bool(host.main.network.active)
	var copy:=BackBufferCopy.new();copy.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT;canvas.add_child(copy)
	var shade:=ColorRect.new();canvas.add_child(shade);C.at(shade,0,0,width_u,height_u);shade.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var dim:=ShaderMaterial.new();dim.shader=preload("res://assets/ui/lab_pause_dim.gdshader");shade.material=dim
	var left_y:float=height_u*.5-13.835
	var splat:TextureRect=C.icon(canvas,"pause_blob",2,left_y-2.5,10,10);splat.rotation=deg_to_rad(-10)
	C.label(canvas,"MENU" if online else "PAUSED",4.3,left_y,30,5,5,true)
	if online:
		var live:Control=C.panel(canvas,19,left_y+1,15.6,2.1,K,.45);live.rotation=deg_to_rad(-4)
		C.panel(live,.55,.7,.75,.75,Color("ff4d6a"),.375);C.label(live,"MATCH STILL ON",1.7,.2,13.6,1.7,.75)
	for index:int in 4:
		var own:int=index
		var action:Callable=func()->void:
			match own:
				0:host.resume()
				1:host.open_page("settings")
				2:host.open_page("howto")
				3:_quit()
		var button:SplatInkButton=C.button(canvas,["BACK TO THE MATCH" if online else "RESUME","SETTINGS","HOW TO PLAY","LEAVE ROOM" if online else "QUIT MATCH"][index],action,3.8,left_y+7.2+index*5.6,30,4.5,2.05,["glyph_play","glyph_gear","glyph_question","glyph_exit" if online else "glyph_close"][index],"",index==0,Color("e03b55") if index==3 else SplatUiTheme.ORANGE,[-1.8,1.2,-1.0,1.4][index])
		if index==0:C.defer_focus(button)
	var snap:Dictionary=_snapshot()
	var self_player:Dictionary=(snap.players as Array).filter(func(p:Dictionary)->bool:return bool(p.get("isSelf",false)))[0] if (snap.players as Array).any(func(p:Dictionary)->bool:return bool(p.get("isSelf",false))) else (snap.players[0] if not snap.players.is_empty() else {})
	var own_team:int=int(self_player.get("team",0));var colors:Array=snap.colors;var own_color:Color=colors[own_team]
	var panel:Control=C.panel(canvas,width_u-50.8,(height_u-38.292)*.5,47,38.292)
	C.panel(canvas,width_u-50.8,(height_u-38.292)*.5+.45,47,38.292,Color(0,0,0,.38),1.5);canvas.move_child(panel,canvas.get_child_count()-1)
	var mode_tag:Control=C.panel(panel,1.5,2.4,7.4,1.8,own_color,.45);mode_tag.rotation=deg_to_rad(-2)
	C.label(mode_tag,"TURF WAR",.6,.05,6.3,1.7,1.05,true,K)
	C.icon(panel,"glyph_bot",9.65,2.6,1.05,1.05).modulate=own_color
	C.label(panel,str(snap.difficulty).to_upper()+" BOTS",11.05,2.4,22,1.8,.75)
	C.icon(panel,"glyph_map",1.5,4.9,1.7,1.7).modulate=own_color
	C.label(panel,str(snap.map),3.85,4.6,30.6,2.3,1.55,true)
	var ring:ColorRect=ColorRect.new();panel.add_child(ring);C.at(ring,39.3,1.3,6.2,6.2);ring.mouse_filter=Control.MOUSE_FILTER_IGNORE
	clock_ring=ShaderMaterial.new();clock_ring.shader=preload("res://assets/ui/lab_clock_ring.gdshader");clock_ring.set_shader_parameter("ink",own_color);ring.material=clock_ring
	clock_label=C.label(ring,"1:35",0,1.8,6.2,2.0,1.6,true);clock_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	C.label(ring,"LEFT",0,3.9,6.2,.75,.56).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var self_panel:Control=C.panel(panel,1.5,8.448,44,5.596,Color(own_color,.16),1.1)
	(self_panel.material as ShaderMaterial).set_shader_parameter("border_color",Color(own_color,.5));(self_panel.material as ShaderMaterial).set_shader_parameter("border",2.0)
	C.icon(self_panel,"squid",.9,1.2,3.2,3.2).modulate=own_color
	C.label(self_panel,"YOUR MATCH",5,1.45,14,.9,.6,false,Color(1,1,1,.75));C.label(self_panel,str(self_player.get("name",host.profile.name)),5,2.5,17,1.8,1.4,true)
	for index:int in 4:
		var stat:Control=C.panel(self_panel,23.4+index*5.05,.7,4.6,4.2,Color(0,0,0,.3),.7)
		C.icon(stat,["glyph_drop","splat_icon","death_icon","special_"+str(SplatUiTheme.catalog().weapons.get(str(self_player.get("weapon","shooter")),{}).get("special","slam"))][index],1.675,.35,1.25,1.25).modulate=own_color
		var text:Label=C.label(stat,"0",0,1.8,4.6,1.35,1.15,true);text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;values.append(text)
		C.label(stat,["TURF","SPLATS","SPLATTED","SPECIAL"][index],0,3.2,4.6,.75,.5,false,Color(1,1,1,.65)).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		if index==3:special_bar=C.panel(stat,0,3.965,4.6,.235,own_color,0)
	for team:int in 2:
		var x:float=1.5+team*22.6;var color:Color=colors[team]
		var pip:Control=C.panel(panel,x,15.03,.9,.9,color,.45);(pip.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(pip.material as ShaderMaterial).set_shader_parameter("border",1.5)
		C.label(panel,str(snap.names[team]).to_upper(),x+1.3,14.96,11,1.1,.8)
		var chip:Control=C.panel(panel,x+15.6,15.02,5.8,1.0,Color(1,1,1,.1),.25);C.label(chip,"YOUR TEAM" if own_team==team else "RIVALS",.25,0,5.3,1,.65).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var players:Array=(snap.players as Array).filter(func(p:Dictionary)->bool:return int(p.team)==team)
		for index:int in players.size():
			var player:Dictionary=players[index]
			var row:Control=C.panel(panel,x,16.35+index*2.629,21.4,2.35,Color(1,1,1,.05),.7)
			var weapon:TextureRect=C.icon(row,"weapon_"+str(player.weapon),.4,.225,2.4,1.9)
			var name:Label=C.label(row,str(player.name),3.3,0,13.3,2.35,.95)
			if bool(player.get("isSelf",false)):
				var label_width:float=SplatUiTheme.BODY.get_string_size(str(player.name),HORIZONTAL_ALIGNMENT_LEFT,-1,12).x/12.8
				var self_tag:Control=C.panel(row,3.65+label_width,.8,1.9,.75,Color.WHITE,.25);C.label(self_tag,"YOU",0,0,1.9,.75,.56,false,K).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			var state_icon:TextureRect=C.icon(row,"squid",18.9,.5,1.35,1.35)
			var state_text:Label=C.label(row,"",17.6,0,3.4,2.35,.66);state_text.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
			rows.append({"name":player.name,"team":team,"node":row,"weapon":weapon,"label":name,"icon":state_icon,"text":state_text,"color":color})
	C.icon(panel,"glyph_gamepad",1.5,27.72,1.2,1.2).modulate=own_color;C.label(panel,"QUICK CONTROLS",3.1,27.58,38,1.45,.8)
	_controls(panel,1.5,29.37,44)
	L.prompts(self,"Enter  Select     Esc  Resume",20)
	_update(snap)

func _snapshot()->Dictionary:
	var value:Dictionary={"time":94.4,"duration":180,"map":"Tidewater Plaza","difficulty":"FRESH","colors":[SplatUiTheme.ORANGE,SplatUiTheme.BLUE],"names":["Tangerine","Cobalt"],"players":SplatLabFixture.roster(host)}
	if not is_instance_valid(host.main) or not host.main.get("state") in ["intro","playing","finish"]:return value
	var game:Node=host.main
	value.time=maxf(0,float(game.time_left));value.duration=maxf(1,float(game.options.get("duration",180)))
	value.difficulty={"easy":"CHILL","normal":"FRESH","hard":"FIERCE"}.get(str(game.options.get("difficulty","normal")),"FRESH")
	value.colors=game.team_colors
	if game.stage!=null:value.map=str(game.stage.layout.get("name","Turf War"))
	var palette:int=int(game.options.get("palette",0));value.names=SplatUiTheme.catalog().palettes[clampi(palette,0,4)].names
	var players:Array=[]
	for actor:Node in game.actors:
		players.append({"name":actor.display_name,"team":actor.team_id,"weapon":actor.weapon_id,"alive":actor.alive,"respawn":actor.respawn_timer,"special":actor.special_fraction()>=.999,"specialFrac":actor.special_fraction(),"isSelf":actor.is_local,"turf":actor.turf_points,"splats":actor.splats,"deaths":actor.deaths})
	value.players=players
	return value

func _update(snap:Dictionary)->void:
	var left:float=float(snap.time);var time:int=ceili(left)
	clock_label.text="%d:%02d"%[time/60,time%60];clock_label.add_theme_color_override("font_color",Color("ff8a9a") if left<=60 else Color.WHITE)
	clock_ring.set_shader_parameter("fraction",clampf(left/float(snap.duration),0,1));clock_ring.set_shader_parameter("ink",Color("ff4d6a") if left<=60 else snap.colors[0])
	for player:Dictionary in snap.players:
		if bool(player.get("isSelf",false)):
			values[0].text="%dp"%int(player.get("turf",0));values[1].text=str(player.get("splats",0));values[2].text=str(player.get("deaths",0));values[3].text="READY" if _special_ready(player) else "%d%%"%roundi(float(player.get("specialFrac",0))*100)
			var fraction:float=clampf(float(player.get("specialFrac",0)),0,1);special_bar.size.x=4.6*12.8*fraction
		for row:Dictionary in rows:
			if row.name!=player.name or int(row.team)!=int(player.team):continue
			var alive:bool=bool(player.get("alive",true));var ready:bool=_special_ready(player)
			(row.node as Control).modulate.a=1.0 if alive else .55
			var face:ShaderMaterial=(row.node as ColorRect).material as ShaderMaterial
			var fill:Color=Color(row.color,.24) if bool(player.get("isSelf",false)) else Color(1,1,1,.05)
			face.set_shader_parameter("top_color",fill);face.set_shader_parameter("bottom_color",fill);face.set_shader_parameter("border_color",row.color if ready or bool(player.get("isSelf",false)) else Color.TRANSPARENT);face.set_shader_parameter("border",2)
			(row.weapon as TextureRect).modulate=Color.WHITE if alive else Color("a9a2b9")
			(row.icon as TextureRect).texture=load("res://assets/ui/source/%s.svg"%("death_icon" if not alive else "special_"+str(SplatUiTheme.catalog().weapons[str(player.weapon)].special) if ready else "squid")) as Texture2D
			(row.icon as TextureRect).modulate=Color("b7b0c9") if not alive else row.color
			(row.text as Label).text="%ds"%maxi(1,ceili(float(player.get("respawn",0)))) if not alive else "READY" if ready else ""
			(row.text as Label).add_theme_color_override("font_color",Color("ff9aa9") if not alive else row.color)
			C.at(row.icon,16.9 if not alive or ready else 18.9,.5,1.35,1.35)

static func _special_ready(player:Dictionary)->bool:
	if player.has("specialReady"):return bool(player.specialReady)
	var value:Variant=player.get("special",false)
	return value if value is bool else float(value)>=.999

func _controls(parent:Control,x:float,y:float,w:float)->void:
	var data:Array=[["Move",["W","A","S","D"],"LS",false],["Fire",["LMB"],"RT",false],["Swim",["SHIFT"],"LT",true],["Jump",["SPACE"],"A",false],["Aim bomb",["RMB","or","E"],"RB",true],["Special",["F","or","Q"],"Y",false]]
	var width:float=(w-1.6)*.5
	for index:int in data.size():
		var row:Array=data[index];var px:float=x+(index%2)*(width+1.6);var py:float=y+floori(index/2.0)*2.65
		C.label(parent,str(row[0]),px,py,width-7,2.35,.95)
		if bool(row[3]):
			var text_w:float=SplatUiTheme.BODY.get_string_size(str(row[0]),HORIZONTAL_ALIGNMENT_LEFT,-1,12).x/12.8
			var hold:Control=C.panel(parent,px+text_w+.55,py+.6,3.2,1.0,Color(1,1,1,.1),.25);C.label(hold,"HOLD",0,0,3.2,1,.7,false,Color(1,1,1,.6)).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var keys:=Control.new();parent.add_child(keys);C.at(keys,px+width-13,py+.3,13,2.0);var pen:float=0
		var tokens:Array=[row[2]] if host.controls_pad else row[1]
		for token:String in tokens:
			if token=="or":C.label(keys,"or",pen,0,1.5,2,.7,false,SplatUiTheme.MUTED);pen+=1.5
			else:pen+=C.keycap(keys,token,pen,0,.75,host.controls_pad)
		keys.position.x+=(13-pen)*12.8

func _quit()->void:
	host.confirm("LEAVE ROOM?" if online else "QUIT MATCH?","You’ll leave the match and the room — a bot takes over your squidkid for the team." if online else "You will leave this Turf War and head back to the lobby. Your turf will not count.",func()->void:host.pause_changed.emit(false);host.exit_requested.emit();host.show_menu(),"KEEP PLAYING","LEAVE" if online else "QUIT")

func _process(delta:float)->void:
	_refresh-=delta
	if _refresh>0 or values.is_empty() or not is_instance_valid(host):return
	_refresh=.1;_update(_snapshot())
