class_name SplatLabLobby
extends SplatLabCanvas
## Original menus.js _scr_lobby: private-room ticket, host settings, lineup tags and readiness.
const C=preload("res://scripts/ui/lab_canvas.gd")
const O=preload("res://scripts/ui/lab_online_pages.gd")
const P=preload("res://scripts/ui/lab_play_pages.gd")
const L=preload("res://scripts/ui/lab_screens.gd")
const K=Color("15121c")
const HV=Color("e3ff2e")
var host:InkUI
var data:Dictionary
var players:Array=[]
var mine:Dictionary={}
var room_owner:bool=false
var boss_mode:bool=false
var colors:Array[Color]=[]
var waiting:Array=[]
var popup:Control
var emote_timer:float=0

func build(ui:InkUI,room:Dictionary)->void:
	host=ui;data=room;players=data.get("players",[]);room_owner=str(data.get("you",""))==str(data.get("host",""));boss_mode=str(data.get("mode","turf"))=="boss"
	for player:Dictionary in players:
		if str(player.get("id",""))==str(data.get("you","")):mine=player
		if not bool(player.get("ready",false)) and not bool(player.get("host",false)):waiting.append(player)
	var palette:Dictionary=SplatUiTheme.catalog().palettes[posmod(int(data.get("palette",0)),SplatUiTheme.catalog().palettes.size())]
	colors.assign([Color(str(palette.a)),Color(str(palette.b))])
	_ticket();_status();_settings();_lineup();_bar()

func _frame(parent:Node,x:float,y:float,w:float,h:float,color:Color=K,stripes:bool=false,notches:bool=false)->Control:
	var wrap:=Control.new();parent.add_child(wrap);C.at(wrap,x,y,w,h);wrap.mouse_filter=Control.MOUSE_FILTER_IGNORE
	C.panel(wrap,-.4+.45,-.4+.55,w+.8,h+.8,K,1.65)
	C.panel(wrap,-.4,-.4,w+.8,h+.8,K,1.65)
	C.panel(wrap,-.14,-.14,w+.28,h+.28,Color.WHITE,1.4)
	O.sticker(wrap,0,0,w,h,color,stripes,notches)
	return wrap

func _ticket()->void:
	var leave:Button=O.tap(canvas,host._back,3.2,4.4,11,3.9);var face:Control=_frame(leave,0,0,11,3.9)
	C.panel(face,.6,.65,2.55,2.55,HV,1.275);C.icon(face,"glyph_back",1.3,1.4,1.1,1.1).modulate=K
	C.label(face,"LEAVE",3.75,.7,4.5,2.0,.95,true);C.keycap(face,"Esc",8.3,1.0,.78)
	var code:String=str(data.get("code","•••••"))
	if code.is_empty():code="•••••"
	var ticket:Control=_frame(canvas,15.8,2.2,36.8,7.6,SplatUiTheme.ORANGE,true,true);ticket.rotation=deg_to_rad(-1.5)
	var label:Control=C.panel(ticket,1.2,-1.1,9.3,1.8,K,.2);C.icon(label,"glyph_key",.55,.4,.9,.9);C.label(label,"ROOM CODE",1.8,.05,7.1,1.7,.88,true)
	for index:int in mini(5,code.length()):
		var x:float=1.6+index*4.6
		var tile:=Control.new();ticket.add_child(tile);C.at(tile,x,1.7,4,4.8);tile.rotation=deg_to_rad([-4,3,-2,4,-3][index])
		C.panel(tile,-.28,.27,4.56,5.1,K,1.0);C.panel(tile,-.28,-.28,4.56,5.36,K,1.0)
		C.panel(tile,0,0,4,4.8,Color.WHITE,.8);C.label(tile,code[index],0,0,4,4.8,3.3,true,K).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var copy:Button=O.white_button(ticket,"",func()->void:
		DisplayServer.clipboard_set(code);host.toast("COPIED!",{"icon":"glyph_copy"});SplatSourceFeedback.play(self,"ui_confirm");SplatSourceFeedback.play(self,"splat_small",.06),25.4,2.0,10.4,3.8)
	C.icon(copy,"glyph_copy",1.0,1.1,1.25,1.25).modulate=K;C.label(copy,"COPY",3,.6,4.9,2.3,1.15,true,K);C.keycap(copy,"C",8.25,1.05,.72)
	var share:Control=C.panel(canvas,17.2,10.6,19.6,1.7,K,.1);share.rotation=deg_to_rad(-.3)
	C.label(share,"Friends join from",.65,.1,8.8,1.45,.8);C.label(share,"ONLINE › JOIN A ROOM",9.45,.1,9.8,1.45,.8,false,HV)

func _status()->void:
	var status:Control=_frame(canvas,width_u-30.8,2.4,27.4,12.5);status.rotation=deg_to_rad(1.4)
	var mat:ShaderMaterial=status.get_child(status.get_child_count()-1).material as ShaderMaterial
	mat.set_shader_parameter("top_color",K);mat.set_shader_parameter("bottom_color",K)
	C.label(status,"SQUIDKIDS",1.2,1.0,17,1.2,.78);C.label(status,str(players.size()),22.0,.3,3,3.1,3,true,HV);C.label(status,"/8",24.7,1.4,2.0,1.5,1.2,true,Color(1,1,1,.75))
	for team:int in (1 if boss_mode else 2):
		var x:float=1.2+team*14.1;var label:Control=C.panel(status,x,4.55,3.9,1.05,colors[team],.3);label.rotation=deg_to_rad(-3 if team==0 else 3)
		C.label(label,"SQUAD" if boss_mode else "ALPHA" if team==0 else "BRAVO",.25,0,3.4,1.05,.66,false,K if team==0 else Color.WHITE)
		var people:Array=players if boss_mode else players.filter(func(p:Dictionary)->bool:return int(p.get("team",0))==team)
		for index:int in (8 if boss_mode else 4):
			var child_x:float=x+index*2.57 if not boss_mode else x+(index%4)*2.57
			var child_y:float=5.9+(2.45 if boss_mode and index>=4 else 0)
			var pip:TextureRect=C.icon(status,"glyph_squidlet",child_x,child_y,2.45,2.45);pip.rotation=deg_to_rad(-8 if index%2==0 else 7)
			pip.modulate=colors[team] if index<people.size() else Color("5d5672" if bool(data.get("bots",true)) else "3a3350")
			if index<people.size() and (bool(people[index].get("ready",false)) or bool(people[index].get("host",false))):
				var dot:Control=C.panel(status,child_x+1.9,child_y+1.8,.72,.72,Color("3ddc84"),.36);(dot.material as ShaderMaterial).set_shader_parameter("border_color",K);(dot.material as ShaderMaterial).set_shader_parameter("border",1.5)
			elif index>=people.size() and bool(data.get("bots",true)):C.label(status,"BOT",child_x+.25,child_y+1.95,1.8,.75,.42,false,Color("cfc8e0")).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	C.icon(status,"lobby_vs",11.7,5.35,3.6,3.6);var vs:Label=C.label(status,"VS",12.1,6.15,2.8,1.8,1.15,true,HV);vs.rotation=deg_to_rad(-8)
	if boss_mode:C.icon(status,"boss_emblem",17.5,4.8,5.7,5.7);C.label(status,"HULLBREAKER",17,9,9,1.4,.73,true,colors[1])
	var all_ready:bool=players.size()>1 and waiting.is_empty()
	var message:String="Share the code to fill the room"
	if players.size()>=8:message="Room full · %d not ready"%waiting.size() if not waiting.is_empty() else "Room full · everyone’s ready!"
	elif players.size()>1:message="Everyone’s ready — start when you like!" if all_ready and room_owner else "Everyone’s ready — waiting for the host" if all_ready else "%d of %d ready"%[players.size()-waiting.size(),players.size()]
	var info:Control=C.panel(status,1.2,9.7,24.2,1.95,HV if all_ready else Color("2a2144"),.45)
	C.label(info,message,.25,.05,23.7,1.85,.78,false,K if all_ready else Color.WHITE).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER

func _row_label(parent:Node,label:String,icon:String,x:float,y:float,w:float)->void:
	var circle:Control=C.panel(parent,x,y,1.55,1.55,SplatUiTheme.ORANGE,.775);(circle.material as ShaderMaterial).set_shader_parameter("border_color",K);(circle.material as ShaderMaterial).set_shader_parameter("border",2)
	C.icon(circle,icon,.32,.32,.91,.91).modulate=K;C.label(parent,label,x+1.98,y+.08,w-1.98,1.35,.98,true)

func _settings()->void:
	var side:Control=_frame(canvas,3.4,15.9,25.2,28.55);side.rotation=deg_to_rad(-.8)
	var mode:Button=O.tap(canvas,func()->void:O.update_options(host,data,"mode","turf" if boss_mode else "boss"),3.5,12.9,19.4,3.1)
	C.panel(mode,1.4,.3,18,2.5,K,.1);C.icon(mode,"lobby_mode_blob",-.5,-.8,4.2,4.2).modulate=colors[1] if boss_mode else colors[0]
	C.icon(mode,"boss_emblem" if boss_mode else "glyph_flag",.8,.6,1.5,1.5)
	C.label(mode,"BOSS BATTLE" if boss_mode else "TURF WAR",3.3,.15,16.2,2.7,1.62 if boss_mode else 2.05,true);mode.rotation=deg_to_rad(-3)
	var mode_label:Control=C.panel(mode,3.3,-.95,2.6,1.0,HV if room_owner else Color.WHITE,.25);C.label(mode_label,"MODE",.15,.02,2.3,.95,.55,false,K).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	if room_owner:
		for index:int in 2:
			var arrow:Button=O.tap(mode,func()->void:O.update_options(host,data,"mode","turf" if boss_mode else "boss"),15.0+index*1.67,.75,1.45,1.45);C.panel(arrow,0,0,1.45,1.45,HV,.725);C.icon(arrow,"glyph_back" if index==0 else "glyph_next",.25,.25,.95,.95).modulate=K
	var badge:Control=C.panel(canvas,24.0,13.9,4.5,1.7,SplatUiTheme.GOLD,.4);badge.rotation=deg_to_rad(4)
	C.icon(badge,"glyph_crown" if room_owner else "glyph_lock",.25,.42,.8,.8).modulate=K;C.label(badge,"HOST" if boss_mode else "YOU’RE" if room_owner else "HOST",1.3,.1,2.95,1.4,.6,false,K)
	var map_id:String=str(data.get("map","tidewater"));var maps:Array=SplatUiTheme.catalog().maps;var index:int=0
	for candidate:int in maps.size():if str(maps[candidate].id)==map_id:index=candidate
	var row:Button=O.tap(side,func()->void:O.stage_cycle(host,data,1),.75,1.75,23.7,7.2);row.disabled=not room_owner
	var highlight:Control=C.panel(row,-.25,-.25,24.2,7.7,Color(0,0,0,0),1.1);var mat:ShaderMaterial=highlight.material as ShaderMaterial;mat.set_shader_parameter("border_color",HV);mat.set_shader_parameter("border",2.5);highlight.hide()
	row.focus_entered.connect(highlight.show);row.focus_exited.connect(highlight.hide)
	_row_label(row,"STAGE","glyph_map",.45,.2,22.8)
	var stage:Control=C.panel(row,.45,2.1,22.8,5.0,K,.8);stage.clip_contents=true
	P.stage(stage,map_id,str(data.get("time","day")),0,0,22.8,5.0)
	var number:Control=C.panel(stage,.6,.55,5.5,1.2,K,.35);C.label(number,"STAGE",.3,.15,2.4,.8,.58);C.label(number,"%02d"%(index+1),2.65,.1,1.1,1.0,.95,true,HV);C.label(number,"/ %02d"%maps.size(),3.9,.15,1.4,.8,.58,false,Color(1,1,1,.6))
	var name:Control=C.panel(stage,.6,2.7,14.4,1.9,K,.15);name.rotation=deg_to_rad(-2);C.panel(name,.25,.2,14.4,1.9,SplatUiTheme.ORANGE,.15);C.panel(name,0,0,14.4,1.9,K,.15);C.label(name,str(maps[index].name),.6,.05,13.2,1.8,1.23,true)
	var time:Control=C.panel(stage,19.75,2.5,2.5,2.5,K,1.25);C.icon(time,"glyph_moon" if str(data.get("time","day"))=="dusk" else "glyph_sun",.35,.35,1.8,1.8).modulate=SplatUiTheme.GOLD
	if room_owner:
		for own:int in 2:
			var direction:int=-1 if own==0 else 1
			var arrow:Button=O.tap(stage,func()->void:O.stage_cycle(host,data,direction),17.65+own*2.6,.5,2.2,2.2);C.panel(arrow,0,0,2.2,2.2,HV,1.1);C.icon(arrow,"glyph_back" if own==0 else "glyph_next",.55,.55,1.1,1.1).modulate=K
	row.gui_input.connect(func(event:InputEvent)->void:
		if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):O.stage_cycle(host,data,-1 if event.is_action_pressed("ui_left") else 1);row.accept_event())
	_row_label(side,"TIME","glyph_sun",1.2,9.6,10.7);_row_label(side,"LENGTH","glyph_clock",13.2,9.6,10.7)
	_segment(side,["DAY","DUSK"],1 if str(data.get("time","day"))=="dusk" else 0,1.2,11.6,10.7,2.5,func(n:int)->void:O.update_options(host,data,"time","day" if n==0 else "dusk"),["glyph_sun","glyph_moon"])
	var lengths:Array=[180,240,300] if boss_mode else [90,180]
	_segment(side,["3 MIN","4 MIN","5 MIN"] if boss_mode else ["90 SEC","3 MIN"],maxi(0,lengths.find(int(data.get("duration",180)))),13.2,11.6,10.7,2.5,func(n:int)->void:O.update_options(host,data,"duration",lengths[n]))
	_row_label(side,"INK","glyph_drop",1.2,14.5,10)
	var palette:Dictionary=SplatUiTheme.catalog().palettes[posmod(int(data.get("palette",0)),SplatUiTheme.catalog().palettes.size())]
	var names:Array=palette.get("names",["Tangerine","Cobalt"]);C.label(side,str(names[0])+" vs "+str(names[1]),12.5,14.7,11.2,.8,.6).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_palette(side,1.2,16.3,22.8,2.5)
	_row_label(side,"FILL WITH BOTS","glyph_bot",1.2,20.6,17)
	var bots:bool=bool(data.get("bots",true)) and map_id!="cargo"
	var toggle:Button=O.tap(side,func()->void:
		if map_id=="cargo":host.toast("No bots on this stage — it’s humans only",{"icon":"glyph_bot"});return
		O.update_options(host,data,"bots",not bots),17.1,19.75,6.8,2.7)
	C.panel(toggle,-.16,-.16,7.12,3.02,Color.WHITE,1.51);C.panel(toggle,0,0,6.8,2.7,SplatUiTheme.ORANGE if bots else K,1.35)
	var knob:Control=C.panel(toggle,4.35 if bots else .35,.3,2.1,2.1,Color.WHITE,1.05);(knob.material as ShaderMaterial).set_shader_parameter("border_color",K);(knob.material as ShaderMaterial).set_shader_parameter("border",2.5)
	C.label(toggle,"ON" if bots else "OFF",.85 if bots else 3.5,.4,2.8,1.9,.95,true,K if bots else Color.WHITE)
	C.label(side,"HUMANS ONLY" if map_id=="cargo" else "Room is full" if players.size()>=8 else "%d bots join in"%maxi(0,8-players.size()) if bots else "Empty spots stay empty",11.9,20.7,4.8,1.1,.55).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_row_label(side,"DIFFICULTY" if boss_mode else "BOT SKILL","glyph_swords",1.2,23.9,22.8)
	_segment(side,["••• CHILL","••• FRESH","••• FIERCE"],maxi(0,["easy","normal","hard"].find(str(data.get("difficulty","normal")))),1.2,25.85,22.8,2.0,func(n:int)->void:O.update_options(host,data,"difficulty",["easy","normal","hard"][n]))
	if room_owner:C.defer_focus(row)

func _segment(parent:Node,names:Array,selected:int,x:float,y:float,w:float,h:float,callback:Callable,icons:Array=[],selected_color:Color=SplatUiTheme.ORANGE)->void:
	var wrap:Control=C.panel(parent,x,y,w,h,K,h*.5);(wrap.material as ShaderMaterial).set_shader_parameter("border_color",Color(1,1,1,.22));(wrap.material as ShaderMaterial).set_shader_parameter("border",1.8)
	for index:int in names.size():
		var own:int=index;var each:float=w/names.size();var button:Button=O.tap(wrap,func()->void:callback.call(own),index*each+.22,.2,each-.44,h-.4)
		if index==selected:C.panel(button,0,0,each-.44,h-.4,selected_color,h*.5)
		var left:float=.2
		if not icons.is_empty():C.icon(button,str(icons[index]),.55,(h-1.5)*.5,1.05,1.05).modulate=K if index==selected else Color.WHITE;left=1.6
		C.label(button,str(names[index]),left,0,each-.44-left,h-.4,.82,false,K if index==selected else Color.WHITE).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		button.set_meta("source_click_sound","ui_toggle")
		if not room_owner and parent!=canvas:button.disabled=true

func _palette(parent:Node,x:float,y:float,w:float,h:float)->void:
	var wrap:Control=C.panel(parent,x,y,w,h,K,h*.5);(wrap.material as ShaderMaterial).set_shader_parameter("border_color",Color(1,1,1,.25));(wrap.material as ShaderMaterial).set_shader_parameter("border",1.8)
	var palettes:Array=SplatUiTheme.catalog().palettes
	for index:int in palettes.size():
		var own:int=index;var pair:Dictionary=palettes[index];var each:float=w/palettes.size()
		var button:Button=O.tap(wrap,func()->void:O.update_options(host,data,"palette",own),index*each+.15,.22,each-.3,h-.44);button.disabled=not room_owner
		if index==int(data.get("palette",0)):C.panel(button,0,0,each-.3,h-.44,Color.WHITE,h*.5)
		for team:int in 2:
			var ink:TextureRect=C.icon(button,"glyph_drop",.72+team*.92,.2,1.4,1.7);ink.modulate=Color(str(pair.a if team==0 else pair.b));ink.rotation=deg_to_rad(-25 if team==0 else 20)

func _lineup()->void:
	for index:int in players.size():
		var player:Dictionary=players[index];var self_player:bool=str(player.get("id",""))==str(data.get("you",""))
		var name:String=str(player.get("name","Fresh Kid"));var fs:float=(1.42 if self_player else 1.3) if name.length()<=7 else (1.1 if self_player else .98) if name.length()<=11 else (.9 if self_player else .84)
		var w:float=clampf(SplatUiTheme.DISPLAY.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(fs*12.8)).x/12.8+3.05,8.0 if self_player else 7.2,10.6);var h:float=3.3 if self_player else 3.0
		var plate:=SplatLobbyPlate.new();canvas.add_child(plate);C.at(plate,34+index*3,23,w,h);plate.canvas=self;plate.slot=index
		if is_instance_valid(host.main):plate.lobby=host.main.get("lobby") as Node
		var color:Color=colors[0] if boss_mode else colors[clampi(int(player.get("team",0)),0,1)]
		var tag:Control=C.panel(plate,-.32,-.32,w+.64,h+.64,K,.9);tag.rotation=deg_to_rad(2 if index%2 else -2.5)
		C.panel(tag,.19,.19,w+.26,h+.26,HV if self_player else Color.WHITE,.7)
		var art:TextureRect=C.icon(tag,"tag_%d"%(O.hash_name(name.to_lower())%7),.32,.32,w,h);art.stretch_mode=TextureRect.STRETCH_SCALE
		var material:=ShaderMaterial.new();material.shader=preload("res://assets/ui/lab_tag.gdshader");material.set_shader_parameter("ink",color);material.set_shader_parameter("panel_size",art.size);art.material=material
		C.label(tag,name,2.35,.32,w-2.7,h,fs,true).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var weapon:Control=C.panel(tag,-.75,(h-2.9)*.5,2.9,2.9,K,1.45);(weapon.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(weapon.material as ShaderMaterial).set_shader_parameter("border",1.7);C.icon(weapon,"weaponw_"+str(player.get("weapon","shooter")),.3,.3,2.3,2.3).modulate=color
		if bool(player.get("host",false)):C.icon(tag,"glyph_crown",-1,-1.9,2.1,2.1).modulate=SplatUiTheme.GOLD
		elif bool(player.get("ready",false)):
			var ready:Control=C.panel(tag,w-3.6,h-.35,4.4,1.5,Color("3ddc84"),.45);ready.rotation=deg_to_rad(-9);C.icon(ready,"glyph_check",.3,.35,.8,.8).modulate=K;C.label(ready,"READY!",1.2,.1,3.0,1.2,.68,true,K)
		if self_player:
			var you:Control=C.panel(tag,w-1.95,-1.1,2.6,1.4,HV,.35);you.rotation=deg_to_rad(10);C.label(you,"YOU",0,0,2.6,1.4,.8,true,K).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			C.icon(plate,"source_pointer",w*.5-.75,h+.4,1.5,.9).modulate=HV

func _bar()->void:
	var band:TextureRect=C.icon(canvas,"lobby_band",0,height_u-13,width_u,13);band.stretch_mode=TextureRect.STRETCH_SCALE;canvas.move_child(band,0)
	var y:float=height_u-11.1
	var weapon:Button=O.tap(canvas,_weapon_drawer,3.4,y,17.5,5);_frame(weapon,0,0,17.5,5)
	C.icon(weapon,"weapon_"+str(host.options.weapon),1,.5,4.1,3.4);C.label(weapon,"WEAPON",6,.8,9,1.0,.65);C.label(weapon,str(SplatUiTheme.catalog().weapons[str(host.options.weapon)].name),6,1.9,9.4,2.0,1.35,true)
	C.panel(weapon,14.2,1.5,2.1,2.1,Color.WHITE,1.05);C.icon(weapon,"glyph_pencil",14.75,2.05,1.0,1.0).modulate=K
	var look:Button=O.tap(canvas,func()->void:host.open_page("locker"),22.1,y,5.6,5);_frame(look,0,0,5.6,5)
	C.icon(look,"profile_blob",.35,-.35,4.8,4.8);var portrait:SplatAvatarPreview=SplatAvatarPreview.make(host.profile,str(host.options.weapon),host.main);portrait.thumbnail=true;portrait.portrait_kind="head";look.add_child(portrait);C.at(portrait,.5,.15,4.4,4.2);portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	C.label(look,"LOOK",.4,4.0,4.8,.9,.6,true).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;C.panel(look,4.1,-.3,1.8,1.8,Color.WHITE,.9);C.icon(look,"glyph_hanger",4.5,.1,1.0,1.0).modulate=K
	C.label(canvas,"TEAM",29.4,y+.2,17,1.3,1,true);C.keycap(canvas,"Q",48.55,y-.15,.7);C.keycap(canvas,"E",50.15,y-.15,.7)
	if boss_mode:
		var lock:Control=C.panel(canvas,29.4,y+1.65,22.5,2.75,K,1.375);C.icon(lock,"glyph_lock",.6,.65,1.35,1.35).modulate=colors[0];C.label(lock,"SQUAD",2.5,.5,7,1.7,1.15,true,colors[0]);C.label(lock,"everyone vs the boss",10,.8,11.5,1.2,.62)
	else:_segment(canvas,["ALPHA","AUTO","BRAVO"],1,29.4,y+1.65,22.5,2.75,func(index:int)->void:
		var team:int=index/2
		if index==1:
			var a:int=players.filter(func(p:Dictionary)->bool:return int(p.get("team",0))==0).size();team=0 if a<=players.size()-a else 1
		host.online_requested.emit({"action":"team","team":team}),["glyph_drop","glyph_reset","glyph_drop"],Color.WHITE)
	var emote:Button=O.tap(canvas,_emotes,54.2,y+.15,14.8,5);_frame(emote,0,0,14.8,5)
	C.icon(emote,"glyph_smile",.7,1.0,3,3).modulate=SplatUiTheme.GOLD;C.label(emote,"EMOTE",4.25,1.4,6.1,2.0,1.45,true);C.keycap(emote,"1",10.4,1.4,.78);C.label(emote,"–",12.0,1.5,.6,1.8,.78);C.keycap(emote,"4",12.7,1.4,.78)
	var blocked:bool=room_owner and (not waiting.is_empty() or str(data.get("map",""))=="cargo" and (players.size()<2 or not players.any(func(p:Dictionary)->bool:return int(p.get("team",0))==0) or not players.any(func(p:Dictionary)->bool:return int(p.get("team",0))==1)))
	var sub:String="Press again to cancel" if bool(mine.get("ready",false)) else "Let the host know you’re set"
	if room_owner:
		var names:Array=[]
		for player:Dictionary in waiting.slice(0,2):names.append(str(player.get("name","Squidkid")))
		sub="Waiting for "+(" & ".join(names) if waiting.size()<=2 else ", ".join(names)+" +%d"%(waiting.size()-2)) if not waiting.is_empty() else "Everyone’s ready — let’s ink!" if players.size()>1 else "Just you and the bots"
	var action:=SplatInkButton.make("",_action,HV,true);action.source_layout=true;action.source_font=2.55*12.8;action.source_label="START!" if room_owner else "READY!" if bool(mine.get("ready",false)) else "READY?";action.source_icon="glyph_play" if room_owner else "glyph_check";action.source_subtitle=sub;action.source_blocked=blocked;action.custom_minimum_size=Vector2.ZERO;C.at(action,width_u-26.4,y,23,5.2);canvas.add_child(action)
	C.keycap(action,"R",20.2,.55,.72)
	L.prompts(self,"R Ready   1–4 Emote   Q E Team   C Copy code   Esc Leave",42.7)

func _action()->void:
	if room_owner:
		if not waiting.is_empty():host.toast("Waiting for everyone to ready up",{"icon":"glyph_clock"});SplatSourceFeedback.play(self,"ui_error");return
		host.online_requested.emit({"action":"start"})
	else:host.online_requested.emit({"action":"ready","ready":not bool(mine.get("ready",false))})

func _emotes()->void:
	if is_instance_valid(popup):return
	popup=Control.new();canvas.add_child(popup);C.at(popup,54.2-5.1,height_u-32.6,25,19.5);popup.z_index=40
	_frame(popup,7,4.25,11,11);C.icon(popup,"glyph_smile",10.6,7.85,3.8,3.8).modulate=SplatUiTheme.GOLD
	var positions:Array=[Vector2(12.5,2.145),Vector2(22,9.75),Vector2(12.5,17.355),Vector2(3,9.75)]
	for index:int in 4:
		var own:int=index;var button:Button=O.white_button(popup,"",func()->void:
			if emote_timer<=0:host.online_requested.emit({"action":"emote","emote":own});emote_timer=1.3
			popup.queue_free();popup=null,positions[index].x-5.65,positions[index].y-2.15,11.3,4.3)
		C.icon(button,["glyph_hand","glyph_flex","glyph_booyah","glyph_rotate"][index],.7,.85,2.4,2.4).modulate=SplatUiTheme.ORANGE.darkened(.35);C.label(button,["WAVE","FLEX","BOOYAH","DANCE"][index],3.75,.65,5.35,2.8,1.05,true,K);C.keycap(button,str(index+1),9.2,1.0,.78)
		if index==0:C.defer_focus(button)

func _weapon_drawer()->void:
	# Source modal retains the room, unlike the full offline Loadout page.
	if is_instance_valid(popup):return
	popup=Control.new();canvas.add_child(popup);C.at(popup,0,0,width_u,height_u);popup.z_index=40
	var shade:Control=C.panel(popup,0,0,width_u,height_u,Color(.03,.02,.055,.55),0);shade.mouse_filter=Control.MOUSE_FILTER_STOP
	var card:Control=_frame(popup,3.4,height_u-46.4,54,33);card.rotation=deg_to_rad(-.6)
	C.icon(card,"weapon_shooter",1.4,1.5,1.6,1.5);C.label(card,"CHOOSE YOUR WEAPON",3.6,1.1,31,2,1.5,true);C.label(card,"Enter Equip · Esc Close",35,1.4,17,1.3,.8)
	var detail:Control=C.panel(card,1.4,22.25,51.2,9.35,K,1.1)
	var rendered:Callable=func(id:String)->void:
		for child:Node in detail.get_children():child.queue_free()
		var weapon:Dictionary=SplatUiTheme.catalog().weapons[id]
		C.label(detail,str(weapon.get("class",id)).to_upper(),1,.7,23,1.1,.72,false,SplatUiTheme.ORANGE);C.label(detail,str(weapon.name),1,1.85,23,2.1,2.1,true)
		var blurb:Label=C.label(detail,str(weapon.blurb),1,4.2,22.5,2.2,.8);blurb.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		for index:int in 5:
			var key:String=["range","damage","rate","mobility","paint"][index];C.label(detail,["RANGE","DAMAGE","FIRE RATE","MOBILITY","INK COVERAGE"][index],25.0,.8+index*1.55,8.4,1.1,.72)
			var bar:=ColorRect.new();detail.add_child(bar);C.at(bar,34.0,1.0+index*1.55,16.2,.75);var material:=ShaderMaterial.new();material.shader=preload("res://assets/ui/lab_stat.gdshader");material.set_shader_parameter("quad_size",bar.size);material.set_shader_parameter("value",float(weapon.stats[key]));bar.material=material
		C.label(detail,"Splat Bomb   ·   "+str(SplatUiTheme.catalog().specials[str(weapon.special)].name),1,7.15,23,1.1,.8)
	for index:int in SplatUiTheme.catalog().weapon_order.size():
		var id:String=str(SplatUiTheme.catalog().weapon_order[index]);var x:float=1.4+(index%4)*13.0;var y:float=4.6+floori(index/4.0)*8.8
		var tile:Button=C.tile(card,func()->void:
			host.options.weapon=id;host.weapon_changed.emit(id);host.save_profile();host.online_requested.emit({"action":"weapon","weapon":id});popup.queue_free();popup=null;host.show_lobby(data),x,y,12.2,8.0)
		if id==str(host.options.weapon):C.icon(tile,"weapon_blob_%d"%index,1.6,-1,9,9);C.panel(tile,9.65,.45,2.1,2.1,Color.WHITE,1.05);C.icon(tile,"glyph_check",10.0,.8,1.4,1.4).modulate=K;C.defer_focus(tile)
		C.icon(tile,"weaponw_"+id,1.1,.5,10,4.2);C.label(tile,str(SplatUiTheme.catalog().weapons[id].name),.3,5.15,11.6,1.3,1.05,true).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;C.label(tile,str(SplatUiTheme.catalog().weapons[id].get("class",id)),.3,6.5,11.6,.9,.72).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		tile.focus_entered.connect(func()->void:rendered.call(id))
	rendered.call(str(host.options.weapon))

func _unhandled_input(event:InputEvent)->void:
	if event.is_action_pressed("ui_cancel") and is_instance_valid(popup):popup.queue_free();popup=null;get_viewport().set_input_as_handled()

func _process(dt:float)->void:emote_timer=maxf(0,emote_timer-dt)
