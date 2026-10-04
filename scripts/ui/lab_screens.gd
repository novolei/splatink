class_name SplatLabScreens
extends RefCounted
## Native Control translation of tools/ui-lab.html and final styles/ui.css rules.
const C = preload("res://scripts/ui/lab_canvas.gd")
const O := Color("ff8a14")
const B := Color("2f5bff")
const K := Color("15121c")
const M := Color("c3bdd6")

static func canvas(host: InkUI) -> SplatLabCanvas:
	host.content.hide()
	var node := SplatLabCanvas.new()
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host._margin.add_child(node)
	node.size = host.get_viewport().get_visible_rect().size
	node._layout()
	return node

static func logo(parent: Node, x: float, y: float, fs: float = 3.4) -> Control:
	var group:Control=preload("res://scripts/ui/lab_logo_motion.gd").new()
	group.set("font_pixels",fs*12.8)
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(group)
	C.at(group, x, y, fs * 5, fs * 1.6)
	var pen: float = 0
	var word: String = "INKWAVE"
	var tilts: Array = [-7, 4, -3, 6, -5, 3, -6]
	var offsets: Array = [.02, -.04, .03, -.02, .04, -.03, .02]
	for index: int in word.length():
		var width: float = SplatUiTheme.DISPLAY.get_string_size(word[index], HORIZONTAL_ALIGNMENT_LEFT, -1, roundi(fs * 12.8)).x / 12.8
		var letter: Label = C.label(group, word[index], pen, fs * float(offsets[index]) - .1, width, fs * 1.2, fs, true)
		letter.add_theme_constant_override("outline_size",maxi(2,roundi(fs*12.8*.14)))
		letter.rotation = deg_to_rad(float(tilts[index]))
		(group.get("letters") as Array).append({"node":letter,"position":letter.position,"rotation":letter.rotation})
		pen += width+fs*.01
	var art:TextureRect=C.icon(group,"logo_splat_full",pen*.5-fs*3.42,-fs*1.52,fs*6.84,fs*4.50)
	group.move_child(art,0);art.rotation=deg_to_rad(-3);art.pivot_offset=art.size*.5
	var sub_font:float=fs*(.36 if fs<=3.5 else .3)
	var sub_width:float=SplatUiTheme.DISPLAY.get_string_size("TURF RIOT",HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(sub_font*12.8)).x/12.8+sub_font*2.1
	var sub_height:float=sub_font*1.44
	var shadow:Control=C.panel(group,(pen-sub_width)*.5-.09*sub_font,fs*.98+.05*sub_font,sub_width+.18*sub_font,sub_height+.18*sub_font,K,sub_font*.4)
	shadow.rotation=deg_to_rad(-3)
	var sub: Control = C.panel(group, (pen-sub_width)*.5, fs*.98,sub_width,sub_height, B,sub_font*.32)
	(sub.material as ShaderMaterial).set_shader_parameter("dots",0.0)
	sub.rotation = deg_to_rad(-3)
	var subtitle: Label = C.label(sub, "TURF RIOT", 0, -.03, sub_width,sub_height,sub_font, false)
	subtitle.add_theme_font_override("font", SplatUiTheme.DISPLAY)
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return group

static func header(host: InkUI, view: SplatLabCanvas, title: String, subtitle: String = "") -> void:
	var root: Control = view.canvas
	var back:=Button.new();root.add_child(back);C.at(back,3.4,3.5,6.8,3.35)
	for state:String in ["normal","hover","pressed","focus"]:back.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	back.pressed.connect(host._back);back.mouse_default_cursor_shape=Control.CURSOR_POINTING_HAND
	SplatSourceFeedback.attach(back,"ui_back")
	C.panel(back,0,0,6.8,3.35,K if host.page in ["online","lobby"] else Color(.055,.043,.086,.82),1.675)
	var arrow:Control=C.panel(back,.55,.5,2.3,2.3,Color("d9ff00") if host.page in ["online","lobby"] else Color.WHITE,1.15)
	C.icon(arrow,"glyph_back",.43,.43,1.44,1.44).modulate=K
	C.keycap(back,"Esc",3.35,.67,.86)
	C.icon(root, "splat_blue" if title=="BOSS BATTLE" else "splat", 10.3, .35, 8.5, 8.5)
	C.label(root, title, 12.0, 1.65, 70, 4.5, 3.7, true)
	C.label(root, subtitle, 12.0, 6.55, 70, 1.4, 1.1)

static func prompts(view: SplatLabCanvas, value: String, w: float = 28) -> void:
	var groups:Array[Dictionary]=[]
	var expression:=RegEx.new();expression.compile('\\s{2,}')
	var chunks:PackedStringArray=expression.sub(value,"|",true).split("|",false)
	for chunk:String in chunks:
		var parts:PackedStringArray=chunk.strip_edges().split(" ",false)
		if parts.is_empty():continue
		var keys:Array[String]=[parts[0]];var start:int=1
		if parts.size()>1 and parts[1] in ["Q","E","←","→","↑","↓"]:keys.append(parts[1]);start=2
		var words:PackedStringArray=[]
		for index:int in range(start,parts.size()):words.append(parts[index])
		groups.append({"keys":keys,"text":" ".join(words)})
	var chip:Control=C.panel(view.canvas,0,view.height_u-4.8,1,2.9,Color("171320"),1.45)
	var pen:float=.8
	for group:Dictionary in groups:
		for key:String in group.keys:pen+=C.keycap(chip,key,pen,.43,.95)
		pen+=.35
		var text_width:float=SplatUiTheme.BODY.get_string_size(group.text,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(.95*12.8)).x/12.8
		C.label(chip,group.text,pen,.2,text_width+.2,2.5,.95)
		pen+=text_width+1.25
	var actual_width:float=pen-.45
	C.at(chip,view.width_u-actual_width-2.6,view.height_u-4.8,actual_width,2.9)
	(chip.material as ShaderMaterial).set_shader_parameter("panel_size",chip.size)

static func main(host: InkUI) -> void:
	host.sync_profile_stats()
	var view: SplatLabCanvas = canvas(host)
	var root: Control = view.canvas
	hero_drag(host,root,Rect2(view.width_u*.36,10,view.width_u*.33,view.height_u-15))
	logo(root, 3.4, 2.0)
	var heights: Array = [7.6, 4.15, 3.85, 3.85, 3.85, 3.85, 3.85]
	var entries: Array = [["PLAY", "play", "glyph_play", "Turf War · Boss Battle"], ["ONLINE", "online", "glyph_online", "Play with friends · private rooms"], ["LOADOUT", "loadout", "weapon_" + str(host.options.weapon), ""], ["LOCKER", "locker", "glyph_hanger", ""], ["SETTINGS", "settings", "glyph_gear", ""], ["HOW TO PLAY", "howto", "glyph_question", ""], ["CREDITS", "credits", "glyph_star", ""]]
	var descriptions: Array = ["Turf War 4 v 4 — or team up with the bots against HULLBREAKER in a Boss Battle", "Create a private room, share the code and make waves with your friends", "Find your weapon. Every kit comes with a sub and a special", "Choose your squidkid, then make it yours", "Fine-tune controls, video, audio and gameplay", "Ink the turf. Swim to refill. Stay fresh", "Meet the crew behind INKWAVE"]
	var y: float = view.height_u * .535 - 36.52 * .5
	var desc: Label = C.label(root, str(descriptions[0]), 5.6, view.height_u * .535 + 19.4, 28.7, 2.86, 1.1)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	C.panel(root, 4.3, view.height_u * .535 + 20.3, .62, .62, O, .31)
	var tilts: Array = [-2.2, 1.3, 1.4, -1.1, 1.6, -1.3, 1.1]
	for index: int in entries.size():
		var entry: Array = entries[index]
		var dest: String = str(entry[1])
		var button: SplatInkButton = C.button(root, str(entry[0]), func() -> void: host.open_page(dest), 3.8, y, 30, float(heights[index]), 3.6 if index == 0 else (1.95 if index == 1 else 1.85), str(entry[2]), str(entry[3]), index == 0, B if index == 1 else O, float(tilts[index]))
		var description: String = str(descriptions[index])
		button.focus_entered.connect(func() -> void: desc.text = description)
		if index == 0: C.defer_focus(button)
		if index == 1:
			var live: Control = C.panel(button, 24.2, 1.62, 4.0, 1.05, K, .525)
			C.label(live, "● LIVE", .35, 0, 3.4, 1, .8)
		y += float(heights[index]) + .78 + (.5 if index == 0 else .35 if index == 1 else 0.0)
	var x: float = view.width_u - 30.2
	var card: Control = C.panel(root, x, 2.6, 27, 15.72)
	C.icon(card, "profile_blob", .8, .6, 7.45, 7.45)
	var portrait:SplatAvatarPreview=SplatAvatarPreview.make(host.profile,str(host.options.weapon),host.main)
	portrait.thumbnail=true;portrait.portrait_kind="head";C.at(portrait,1.045,.845,6.96,6.96);card.add_child(portrait);portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	C.label(card, str(host.profile.name), 8.7, 2.4, 16.8, 2.1, 2.0, true)
	var rank_names:Array=["FRESH RECRUIT","TURF SCRAPPER","INK SLINGER","SPLAT VETERAN","TIDE LEGEND"]
	var rank_levels:Array=[1,5,10,20,30]
	var rank:int=0
	for index:int in rank_levels.size():
		if int(host.profile.get("level",1))>=int(rank_levels[index]):rank=index
	var rank_color:Color=[Color("9fe8ff"),Color("7dffb0"),Color("ffd54a"),Color("ff8ad0"),Color("ffb14a")][rank]
	C.icon(card,"rank_%d"%rank,8.7,4.6,1.4,1.4)
	var rank_word:Label=C.label(card, str(rank_names[rank]), 10.5, 4.7, 15, 1.4, .8, false, rank_color);rank_word.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"))
	C.panel(card, 1.5, 8.3, 3.6, 1.9, Color.WHITE, .55)
	C.label(card, "LV %d" % int(host.profile.get("level", 1)), 1.95, 8.4, 3.0, 1.6, 1.25, false, K)
	C.bar(card, 6.0, 8.82, 10.45, .95, float(host.profile.get("xp", 0)) / float(host.profile.get("xp_to_next", 5000)), O)
	C.label(card, "%d / %d XP" % [int(host.profile.get("xp", 0)), int(host.profile.get("xp_to_next", 5000))], 17.2, 8.8, 8.3, 1.0, .8, false, M)
	for index:int in 3:
		var sx:float=[1.5,9.0,18.9][index];var sw:float=[6.8,9.2,6.6][index]
		var stat:Control=C.panel(card,sx,11.15,sw,3.2,Color(1,1,1,.06),.8)
		if index<2:
			var number:Label=C.label(stat,str(host.profile.get("wins",0) if index==0 else host.profile.get("played",0)),.7,.4,2.8,2.3,1.6,false);number.add_theme_font_override("font",SplatUiTheme.DISPLAY)
			var word:Label=C.label(stat,"WINS" if index==0 else "MATCHES",3,.5,sw-3.4,2.3,.8,false,M);word.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"))
		else:
			(stat.material as ShaderMaterial).set_shader_parameter("border_color",Color("ff8a14"));(stat.material as ShaderMaterial).set_shader_parameter("border",1.3)
			C.label(stat,"NEXT RANK",.7,.35,sw-1.4,.9,.6,false,M)
			var next:Label=C.label(stat,"LV %d"%int(rank_levels[mini(4,rank+1)]),.7,1.25,sw-1.4,1.6,1.2,false,Color("ffc48a"));next.add_theme_font_override("font",SplatUiTheme.DISPLAY)
	var weapon: Dictionary = SplatUiTheme.catalog().weapons[str(host.options.weapon)]
	var kit: Control = C.panel(root, x, view.height_u - 17.65, 27, 11.05)
	C.label(kit, "CURRENT LOADOUT", 1.5, 1.2, 24, 1, .8, false, M)
	C.icon(kit, "weapon_" + str(host.options.weapon), 1.5, 2.7, 6, 4.4)
	C.label(kit, str(weapon.name), 8.5, 3.1, 17, 2.0, 1.8, true)
	C.label(kit, str(weapon.get("class", "SHOOTER")).to_upper(), 8.5, 5.3, 17, 1.0, .8, false, M)
	C.panel(kit,1.5,8.05,7.8,2.15,Color(1,1,1,.08),1.075)
	C.panel(kit,9.9,8.05,7.2,2.15,Color(1,1,1,.08),1.075)
	C.icon(kit, "sub_bomb", 1.8, 8.45, 1.3, 1.3)
	C.label(kit, "Splat Bomb", 3.3, 8.35, 6, 1.5, .8)
	C.icon(kit, "special_" + str(weapon.special), 10.2, 8.45, 1.3, 1.3)
	C.label(kit, str(SplatUiTheme.catalog().specials[str(weapon.special)].name), 11.7, 8.35, 11, 1.5, .8)
	C.label(root, "v1.0.0", 3.4, view.height_u - 2.7, 15, 1.0, .7, false, M)
	prompts(view, "Enter  Select     Esc  Title", 16.6)

static func hero_drag(host:InkUI,parent:Control,area:Rect2)->Control:
	var control:=Control.new();parent.add_child(control);C.at(control,area.position.x,area.position.y,area.size.x,area.size.y)
	control.mouse_filter=Control.MOUSE_FILTER_PASS
	if is_instance_valid(host.main) and host.main.get("lobby")!=null:
		var lobby:Node=host.main.lobby
		control.call_deferred("set_meta","initialized",true)
		var set_rect:Callable=func()->void:lobby.call("set_ui_rect",control.get_global_rect())
		set_rect.call_deferred()
		control.gui_input.connect(func(event:InputEvent)->void:
			if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
				if event.pressed:lobby.call("begin_drag",event.position.x)
				else:lobby.call("end_drag")
			elif event is InputEventMouseMotion and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):lobby.call("drag_by",event.relative.x,maxf(.008,host.get_process_delta_time()))
			elif event is InputEventScreenTouch:
				if event.pressed:lobby.call("begin_drag",event.position.x)
				else:lobby.call("end_drag")
			elif event is InputEventScreenDrag:lobby.call("drag_by",event.relative.x,maxf(.008,host.get_process_delta_time())))
		control.mouse_exited.connect(func()->void:lobby.call("end_drag"))
	return control
