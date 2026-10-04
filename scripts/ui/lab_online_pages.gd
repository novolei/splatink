class_name SplatLabOnlinePages
extends RefCounted
const C = preload("res://scripts/ui/lab_canvas.gd")
const L = preload("res://scripts/ui/lab_screens.gd")
const P = preload("res://scripts/ui/lab_play_pages.gd")
const O := Color("ff8a14")
const B := Color("2f5bff")
const K := Color("15121c")
const HV := Color("e3ff2e")
const CODE_ABC := "BCEFGHJKLMNPQRTUVXYZ23456789"
const TITLE_ADJ := ["Fresh", "Inky", "Turf", "Splashy", "Rad", "Sneaky", "Deep-Sea", "Glossy", "Tidal", "Zesty", "Mighty", "Soggy", "Speedy", "Salty", "Bubbly", "Snazzy", "Drippy", "Sunny"]
const TITLE_NOUN := ["Squidkid", "Inkling", "Turf Boss", "Wave Rider", "Splatter", "Tentacle", "Drip Lord", "Sprayer", "Rookie", "Legend", "Deck Hand", "Sea Pickle", "Kelp Fan", "Ink Slinger", "Plaza Star", "Harbor Kid"]

static func box(color:Color,radius:int,outline:Color,width:int)->StyleBoxFlat:
	var style:=StyleBoxFlat.new()
	style.bg_color=color;style.border_color=outline
	style.set_border_width_all(width);style.set_corner_radius_all(radius)
	style.content_margin_left=7;style.content_margin_right=7
	return style

static func sticker(parent: Node, x: float, y: float, w: float, h: float, color: Color = K, stripes: bool = false, notches: bool = false) -> Control:
	C.panel(parent, x + .45, y + .55, w, h, K, 1.3)
	var node := ColorRect.new()
	node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/ui/lab_sticker.gdshader")
	mat.set_shader_parameter("panel_size", Vector2(w,h)*12.8)
	mat.set_shader_parameter("top_color", color.lightened(.15) if stripes else Color("2e2449"))
	mat.set_shader_parameter("bottom_color", color.darkened(.22) if stripes else Color("1c1530"))
	mat.set_shader_parameter("stripes", stripes)
	mat.set_shader_parameter("notches", notches)
	mat.set_shader_parameter("squids", preload("res://assets/ui/source/tex-squids.svg"))
	node.material = mat
	parent.add_child(node)
	C.at(node,x,y,w,h)
	return node

static func tap(parent: Node, callback: Callable, x: float, y: float, w: float, h: float) -> Button:
	var button := Button.new()
	for state: String in ["normal", "hover", "focus", "pressed", "disabled"]: button.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	parent.add_child(button)
	C.at(button,x,y,w,h)
	button.pressed.connect(callback)
	SplatSourceFeedback.attach(button)
	return button

static func white_button(parent: Node, label: String, callback: Callable, x: float, y: float, w: float, h: float, fs: float=1.3) -> Button:
	var button: Button = tap(parent,callback,x,y,w,h)
	var face: Control = C.panel(button,0,0,w,h,Color.WHITE,h*.45)
	(face.material as ShaderMaterial).set_shader_parameter("border_color",K)
	(face.material as ShaderMaterial).set_shader_parameter("border",3.0)
	var text: Label = C.label(button,label,0,0,w,h,fs,false,K)
	text.add_theme_font_override("font",SplatUiTheme.DISPLAY)
	text.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	button.focus_entered.connect(func() -> void: (face.material as ShaderMaterial).set_shader_parameter("top_color",HV);(face.material as ShaderMaterial).set_shader_parameter("bottom_color",HV))
	button.focus_exited.connect(func() -> void: (face.material as ShaderMaterial).set_shader_parameter("top_color",Color.WHITE);(face.material as ShaderMaterial).set_shader_parameter("bottom_color",Color.WHITE))
	button.mouse_entered.connect(button.grab_focus)
	return button

static func hash_name(value: String) -> int:
	var x: int = 2166136261
	for index: int in value.length(): x = ((x ^ value.unicode_at(index)) * 16777619) & 0xffffffff
	return x

static func splashtag(host: InkUI, parent: Node, x: float, y: float, w: float) -> void:
	var tag: Control = sticker(parent,x,y,w,7.6,O,true)
	tag.rotation=deg_to_rad(-1.5)
	C.panel(tag,w-13.2,-1.2,12.6,1.5,K,.2)
	C.label(tag,"YOUR SPLASHTAG",w-12.7,-1.15,12,1.3,.8)
	C.panel(tag,-1.1,1.0,7.1,7.1,K,3.55)
	C.icon(tag,"weapon_"+str(host.options.weapon),.2,2.3,4.5,3.6)
	var namehash: int=hash_name(str(host.profile.name).to_lower())
	var pattern:TextureRect=C.icon(tag,"tag_%d"%(namehash%7),0,0,w,7.6);pattern.stretch_mode=TextureRect.STRETCH_SCALE;tag.move_child(pattern,0)
	var title: Label=C.label(tag,"%s %s" % [TITLE_ADJ[namehash%TITLE_ADJ.size()],TITLE_NOUN[(namehash>>8)%TITLE_NOUN.size()]],6.2,1.2,w-7.6,1.3,.95,true)
	title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var name := LineEdit.new()
	name.add_theme_constant_override("minimum_character_width",0)
	name.text=str(host.profile.name)
	name.alignment=HORIZONTAL_ALIGNMENT_CENTER
	name.max_length=16
	name.add_theme_font_override("font",SplatUiTheme.DISPLAY)
	name.add_theme_font_size_override("font_size",38)
	name.add_theme_color_override("font_color",Color.WHITE)
	name.add_theme_color_override("caret_color",Color.WHITE)
	name.add_theme_color_override("font_outline_color",K);name.add_theme_constant_override("outline_size",6)
	var field_box:StyleBoxFlat=box(Color.TRANSPARENT,0,Color.TRANSPARENT,0)
	name.add_theme_stylebox_override("normal",field_box)
	name.add_theme_stylebox_override("focus",field_box)
	tag.add_child(name)
	C.at(name,5.8,2.55,w-7.2,3.5)
	var number: Label=C.label(tag,"#%d" % (1000+hash_name("#"+str(host.profile.name))%9000),5.9,6.1,10,1,.7,true)
	name.text_changed.connect(func(value: String) -> void:
		if value.strip_edges().is_empty():return
		host.profile.name=value.strip_edges();host.save_profile()
		var h: int=hash_name(value.to_lower())
		pattern.texture=load("res://assets/ui/source/tag_%d.svg"%(h%7)) as Texture2D
		title.text="%s %s" % [TITLE_ADJ[h%TITLE_ADJ.size()],TITLE_NOUN[(h>>8)%TITLE_NOUN.size()]]
		number.text="#%d" % (1000+hash_name("#"+value)%9000))
	var lv:Control=C.panel(tag,w-3.2,6.5,3.6,2.2,HV,.5)
	lv.rotation=deg_to_rad(5)
	C.label(lv,"LV %d" % int(host.profile.get("level",1)),.3,.1,3,2,1.1,false,K)

static func chip(host: InkUI,parent: Node,kind: String,x: float,y: float,w: float,h: float=5.6) -> void:
	var button: Button=tap(parent,func() -> void:host.open_page("loadout" if kind=="weapon" else "locker"),x,y,w,h)
	sticker(button,0,0,w,h)
	if kind=="weapon":
		C.icon(button,"weapon_"+str(host.options.weapon),.8,.7,4.4,3.7)
		C.label(button,"WEAPON",5.9,.9,w-7,1,.65)
		C.label(button,str(SplatUiTheme.catalog().weapons[str(host.options.weapon)].name),5.9,2.0,w-6.4,2.5,1.6,true)
	else:
		C.icon(button,"splat",.5,.15,5.4,5.4)
		C.icon(button,"squid",1.3,1.1,3.4,3.4)
		C.label(button,"LOOK",6,.9,w-7,1,.65)
		C.label(button,"Locker",6,2,w-7,2.5,1.6,true)
	C.icon(button,"glyph_pencil" if kind=="weapon" else "glyph_hanger",w-2.5,2,1.4,1.4)

static func payload(host: InkUI,action: String,code: String="") -> Dictionary:
	return {"action":action,"transport":host.online_transport,"code":code,"address":host.online_address,"port":27840,"match":host.options.duplicate(true),"name":host.profile.name,"style":host.profile.duplicate(),"weapon":str(host.options.weapon)}

static func portal(host: InkUI) -> void:
	host.online_transport="relay"
	var view:SplatLabCanvas=L.canvas(host)
	var root:Control=view.canvas
	L.header(host,view,"ONLINE","Private rooms · 4 v 4 · up to 8 squidkids")
	var create:Button=tap(root,func()->void:host.online_requested.emit(payload(host,"host")),3.9,11.6,50,12.5)
	var face:Control=sticker(create,0,0,50,12.5,B,true)
	C.icon(create,"splat",-1.6,.1,12.5,12.5)
	C.icon(create,"glyph_flag",3,4.2,4.0,4.0)
	C.panel(create,10.5,1.5,8.5,1.7,K,.2)
	C.label(create,"♛ YOU HOST",11,1.5,8,1.7,.8)
	C.label(create,"CREATE A ROOM",10.5,4.2,30.0,3.3,3.05,true)
	var sub:Label=C.label(create,"Pick the stage, share the code, start when everyone’s ready.",10.5,8.0,30.5,3.1,1.1)
	sub.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var go:Button=tap(create,func()->void:host.online_requested.emit(payload(host,"host")),43,3.7,5.9,6.5)
	var go_face:Control=C.panel(go,0,0,5.9,6.5,HV,1.3);(go_face.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(go_face.material as ShaderMaterial).set_shader_parameter("border",3)
	C.label(go,"GO!",0,.3,5.9,2.8,1.9,false,K).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	C.keycap(go,"Enter",1.05,3.35,.8)
	go.rotation=deg_to_rad(4)
	var base_position:Vector2=create.position;create.pivot_offset=create.size*.5
	var drips:TextureRect=C.icon(create,"create_drips",4,12.3,33,2.6);drips.hide()
	create.focus_entered.connect(func()->void:
		(face.material as ShaderMaterial).set_shader_parameter("border_color",HV);drips.show()
		var tween:Tween=create.create_tween().set_parallel(true);tween.tween_property(create,"scale",Vector2.ONE*1.025,.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);tween.tween_property(create,"position",base_position+Vector2(10.24,0),.45))
	create.focus_exited.connect(func()->void:
		(face.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);drips.hide()
		var tween:Tween=create.create_tween().set_parallel(true);tween.tween_property(create,"scale",Vector2.ONE,.45);tween.tween_property(create,"position",base_position,.45))
	create.mouse_entered.connect(create.grab_focus)
	C.defer_focus(create)
	var join:Control=sticker(root,3.9,26.0,50,21.7)
	C.panel(join,1.7,1.3,10,1.7,K,.2)
	C.label(join,"⚿ GOT A CODE?",2,1.3,9.6,1.7,.8)
	C.label(join,"JOIN A ROOM",1.7,4.4,28,3.3,3.05,true)
	var edits:Array[LineEdit]=[]
	var hint:Label=C.label(join,"Room codes are 5 letters & numbers",2,18.6,44,1.4,.95)
	var get_code:Callable=func()->String:
		var result:String=""
		for edit:LineEdit in edits:result+=edit.text
		return result
	var do_join:Callable=func()->void:
		var code:String=get_code.call()
		if host.online_transport=="relay" and code.length()!=5:hint.text="Enter all 5 letters & numbers";return
		hint.text="Connecting…  Esc to cancel"
		host.online_requested.emit(payload(host,"join",code))
	white_button(join,"PASTE",func()->void:
		var clip:String=DisplayServer.clipboard_get().to_upper()
		var regex:=RegEx.new();regex.compile("["+CODE_ABC+"]{5}")
		var found:RegExMatch=regex.search(clip)
		var code:String=found.get_string() if found else ""
		if code.is_empty():hint.text="Nothing that looks like a room code on the clipboard";return
		for index:int in 5:edits[index].text=code[index]
		do_join.call(),31.4,4.2,8.6,3.6,1.1)
	white_button(join,"JOIN ›",do_join,40.5,4.2,7.4,3.6,1.1)
	for index:int in 5:
		var own:int=index
		var edit:=LineEdit.new()
		edit.add_theme_constant_override("minimum_character_width",0)
		edit.max_length=1;edit.placeholder_text="";edit.alignment=HORIZONTAL_ALIGNMENT_CENTER
		edit.add_theme_font_override("font",SplatUiTheme.DISPLAY);edit.add_theme_font_size_override("font_size",59)
		edit.add_theme_color_override("font_color",K);edit.add_theme_color_override("font_placeholder_color",Color(1,1,1,.45))
		var blank:StyleBoxFlat=box(Color("110d1c"),14,K,4)
		var filled:StyleBoxFlat=box(Color.WHITE,14,K,4)
		var focus_blank:StyleBoxFlat=box(Color("1e1830"),14,HV,4)
		var focus_filled:StyleBoxFlat=box(Color.WHITE,14,HV,4)
		edit.add_theme_stylebox_override("normal",blank);edit.add_theme_stylebox_override("focus",focus_blank)
		join.add_child(edit);C.at(edit,1.7+index*9.45,9.7,8.25,7.6)
		var decoration:=SplatCodeCell.new();decoration.index=index;edit.add_child(decoration)
		edit.pivot_offset=edit.size*.5;var base:Vector2=edit.position
		edit.focus_entered.connect(func()->void:
			edit.add_theme_stylebox_override("focus",focus_filled if not edit.text.is_empty() else focus_blank)
			var tween:Tween=edit.create_tween().set_parallel(true);tween.tween_property(edit,"scale",Vector2.ONE*(1.07 if not edit.text.is_empty() else 1.04),.25).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);tween.tween_property(edit,"position",base-Vector2(0,.4*12.8),.25))
		edit.focus_exited.connect(func()->void:
			var tween:Tween=edit.create_tween().set_parallel(true);tween.tween_property(edit,"scale",Vector2.ONE,.25);tween.tween_property(edit,"position",base,.25))
		edits.append(edit)
		edit.text_changed.connect(func(value:String)->void:
			var clean:String=value.to_upper()
			if not clean.is_empty() and not CODE_ABC.contains(clean):edit.text="";hint.text="No O/0, I/1, W/A/S/D in room codes";return
			edit.text=clean;edit.add_theme_stylebox_override("normal",filled if not clean.is_empty() else blank);edit.add_theme_stylebox_override("focus",focus_filled if not clean.is_empty() else focus_blank);decoration.queue_redraw()
			if not clean.is_empty():
				if bool(edit.get_meta("cycling",false)):return
				if own<4:edits[own+1].grab_focus()
				else:
					hint.text="Connecting…  Esc to cancel"
					var completed:String=get_code.call()
					host.get_tree().create_timer(.32).timeout.connect(func()->void:
						if is_instance_valid(join) and host.page=="online" and get_code.call()==completed:do_join.call())
			else:hint.text="Type or paste the code")
		edit.text_submitted.connect(func(_value:String)->void:do_join.call())
		edit.gui_input.connect(func(event:InputEvent)->void:
			if event is InputEventKey and event.pressed and event.keycode==KEY_BACKSPACE and edit.text.is_empty() and own>0:edits[own-1].grab_focus();edits[own-1].text="";edit.accept_event()
			elif event.is_action_pressed("ui_up") or event.is_action_pressed("ui_down"):
				var current:int=CODE_ABC.find(edit.text) if not edit.text.is_empty() else 0
				edit.set_meta("cycling",true);edit.text=CODE_ABC[posmod(current+(-1 if event.is_action_pressed("ui_up") else 1),CODE_ABC.length())];edit.text_changed.emit(edit.text);edit.set_meta("cycling",false);edit.accept_event())
	for index:int in 3:
		var step:Control=C.panel(root,4.1+index*17.0,49.8,15.7,2.4,Color.WHITE,.6)
		C.icon(step,"splat",-.15,-.2,2.6,2.6)
		C.label(step,str(index+1),.7,.2,1.2,1.8,1.1,false,K)
		C.label(step,["Create or join","Share the code","Ready up & ink!"][index],2.8,.15,12.1,2.0,.8,false,K)
	splashtag(host,root,view.width_u-33.4,3.9,30)
	chip(host,root,"weapon",view.width_u-43.6,view.height_u-12.4,19.3)
	chip(host,root,"look",view.width_u-22.9,view.height_u-12.4,19.3)
	L.prompts(view,"Enter  Select     Esc  Back",16.6)
	# Native LAN is an additional transport, tucked away from the original room-code flow.
	var lan:Button=white_button(root,"LAN",func()->void:lan_dialog(host,root),58,view.height_u-5,5.2,2.8,.9)
	lan.tooltip_text="Connect directly on a local network"

static func lan_dialog(host:InkUI,parent:Control)->void:
	var modal:=Control.new();parent.add_child(modal);C.at(modal,0,0,parent.size.x/12.8,parent.size.y/12.8)
	var shade:=ColorRect.new();shade.color=Color(0,0,0,.65);modal.add_child(shade);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var x:float=parent.size.x/25.6-21
	var card:Control=sticker(modal,x,18,42,20)
	C.label(card,"LOCAL NETWORK",2,1.4,38,3,2.5,true)
	var address:=LineEdit.new();address.text=host.online_address;card.add_child(address);C.at(address,2,6,38,3.8)
	C.label(card,"Host address · UDP 27840",2,10.3,38,1.7,.95)
	white_button(card,"HOST",func()->void:host.online_transport="enet";host.online_address=address.text.strip_edges();host.online_requested.emit(payload(host,"host")),2,13.7,11,3.6)
	white_button(card,"JOIN",func()->void:host.online_transport="enet";host.online_address=address.text.strip_edges();host.online_requested.emit(payload(host,"join")),15,13.7,11,3.6)
	white_button(card,"CLOSE",modal.queue_free,28,13.7,11,3.6)

static func update_options(host:InkUI,data:Dictionary,key:String,value:Variant)->void:
	if str(data.get("you",""))!=str(data.get("host","")):return
	var option:Dictionary=data.duplicate(true);option[key]=value
	if key=="map" and value=="cargo":option.mode="turf";option.bots=false
	if key=="mode" and value=="boss":
		option.duration=240
		if str(option.get("map",""))=="cargo":option.map="tidewater"
	host.online_requested.emit({"action":"options","match":option})

static func lobby(host:InkUI,data:Dictionary)->void:
	host.content.hide()
	var page:Control=load("res://scripts/ui/lab_lobby.gd").new()
	host._margin.add_child(page);page.size=host.get_viewport().get_visible_rect().size;page.call("_layout");page.call("build",host,data)

static func stage_cycle(host:InkUI,data:Dictionary,direction:int)->void:
	if str(data.get("you",""))!=str(data.get("host","")):return
	var maps:Array=SplatUiTheme.catalog().maps
	if str(data.get("mode","turf"))=="boss":maps=maps.filter(func(map):return str(map.id)!="cargo")
	var current:int=0
	for index:int in maps.size():if str(maps[index].id)==str(data.get("map","")):current=index
	update_options(host,data,"map",str(maps[posmod(current+direction,maps.size())].id))

static func emote_menu(host:InkUI,parent:Control)->void:
	var wrap:Control=C.panel(parent,parent.size.x/25.6-15,36,30,7,K,1.2)
	for index:int in 4:
		var own:int=index
		white_button(wrap,["1 WAVE","2 FLEX","3 BOOYAH","4 DANCE"][index],func()->void:host.online_requested.emit({"action":"emote","emote":own});wrap.queue_free(),.5+index*7.3,1.3,7,4.2,.8)
