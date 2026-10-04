class_name SplatLabExtraPages
extends RefCounted
const C = preload("res://scripts/ui/lab_canvas.gd")
const L = preload("res://scripts/ui/lab_screens.gd")
const P = preload("res://scripts/ui/lab_play_pages.gd")
const O := Color("ff8a14")
const K := Color("15121c")
const M := Color("c3bdd6")

static func tabs(parent: Node, names: Array, current: int, x: float, y: float, w: float, selected: Callable) -> void:
	C.panel(parent, x, y, w, 4.5, Color(0.07, .055, .12, .72), 1.2)
	C.keycap(parent,"Q",x+.7,y+1.15,.95);C.keycap(parent,"E",x+w-2.65,y+1.15,.95)
	var each:float=(w-7)/names.size()
	var icons:Dictionary={"Controls":"gamepad","Video":"monitor","Audio":"speaker","Gameplay":"swords","SQUIDKIDS":"users","HAIR":"hair","FACE":"eye","OUTFIT":"shirt"}
	for index:int in names.size():
		var own:int=index;var title:String=str(names[index]);var fs:float=.95 if title==title.to_upper() else 1.1
		var button:=Button.new();parent.add_child(button);C.at(button,x+3.5+index*each,y+.4,each-.25,3.7)
		for state:String in ["normal","hover","pressed","focus"]:
			var style:=StyleBoxFlat.new();style.bg_color=O if index==current else Color.TRANSPARENT;style.set_corner_radius_all(12)
			if state=="focus":style.border_color=Color.WHITE;style.set_border_width_all(2)
			button.add_theme_stylebox_override(state,style)
		var text_width:float=preload("res://assets/fonts/ink_body_900_font.tres").get_string_size(title,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(fs*12.8)).x/12.8
		var start:float=(each-text_width-fs*1.85)*.5
		C.icon(button,"glyph_"+str(icons.get(title,"star")),start,(3.7-fs*1.35)*.5,fs*1.35,fs*1.35).modulate=K if index==current else Color("c3bdd6")
		var label:Label=C.label(button,title,start+fs*1.85,.25,text_width+.2,3.2,fs,false,K if index==current else Color("c3bdd6"));label.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"))
		button.pressed.connect(func()->void:selected.call(own))
		SplatSourceFeedback.attach(button)

static func shuffle(host: InkUI) -> void:
	var catalog: Dictionary = SplatUiTheme.catalog()
	for pair: Array in [["hair", "hair_names"], ["hat", "hat_names"], ["eyes", "iris_names"], ["brows", "brow_names"], ["skin", "skin_names"], ["outfit", "outfit_names"]]: host.profile[str(pair[0])] = randi_range(0, catalog[str(pair[1])].size() - 1)
	host.save_profile()
	host.open_page("locker")

static func locker(host: InkUI) -> void:
	var view: SplatLabCanvas = L.canvas(host)
	var root: Control = view.canvas
	L.header(host, view, "LOCKER", "Choose your squidkid, then make it yours")
	tabs(root, ["SQUIDKIDS", "HAIR", "FACE", "OUTFIT"], host.locker_tab, 3.6, 10.4, 57, func(index: int) -> void: host.locker_tab = index;host.locker_focus={"key":["preset","hair","eyes","outfit"][index],"index":0};host.open_page("locker"))
	var card: Control = C.panel(root, 3.6, 15.8, 57, 30.3)
	var catalog: Dictionary = SplatUiTheme.catalog()
	var groups: Array = []
	match host.locker_tab:
		0: groups = [["preset", "CHOOSE YOUR SQUIDKID", "presets", 5, 10.2]]
		1: groups = [["hair", "TENTACLE HAIR", "hair_names", 8, 6.2375], ["hat", "HEADGEAR", "hat_names", 8, 6.2375]]
		2: groups = [["eyes", "EYE COLOR", "iris_names", 10, 4.85], ["brows", "BROWS", "brow_names", 8, 6.2375], ["skin", "SKIN TONE", "skin_names", 10, 4.85]]
		3: groups = [["outfit", "OUTFIT", "outfit_names", 6, 9.94]]
	var y: float = 1.0
	C.panel(card,1.1,24.8,54.8,4.4,Color(1,1,1,.06),.9)
	C.label(card,"SQUIDKID",2,25.6,6.4,1.5,.8,false,O)
	var hover_title: Label = C.label(card, "Rookie", 8.4, 25.4, 35, 1.9, 1.55, false)
	hover_title.add_theme_font_override("font",SplatUiTheme.DISPLAY)
	var hover_text: Label = C.label(card, "Fresh off the ferry, ringer tee and long tentacles.", 2, 27.6, 51, 1.4, .9, false, M)
	var wearing:Control=C.panel(card,45.4,25.55,9.1,1.6,O,.8);C.icon(wearing,"glyph_check",.35,.25,1.1,1.1).modulate=K
	var wearing_text:Label=C.label(wearing,"WEARING",1.85,.1,7,1.4,.8,false,K);wearing_text.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"));wearing.hide()
	var tile_sequence:int=0
	for group: Array in groups:
		var key: String = str(group[0])
		var entries: Array = catalog[str(group[2])]
		var cols: int = int(group[3])
		var height: float = float(group[4])
		var tw: float = (54.8 - (cols - 1) * .7) / cols
		C.label(card, str(group[1]), 1.2, y, 45, 1.0, .8)
		C.label(card, "%d LOOKS" % entries.size(), 49, y, 5.8, 1.0, .6, false, M)
		y += 1.5
		for index: int in entries.size():
			var own: int = index
			var item: Variant = entries[index]
			var name: String = str(item.name) if item is Dictionary else str(item)
			var selected: bool = int(host.profile.get(key, -1)) == index
			if key=="preset" and item is Dictionary:
				selected=true
				for field:String in item.style.keys():
					if host.profile.get(field)!=item.style[field]:selected=false;break
			var style: Dictionary = (item.style as Dictionary).duplicate() if item is Dictionary else host.profile.duplicate()
			if key != "preset": style[key] = index
			var tile: Button = C.tile(card, func() -> void:
				host.locker_focus={"key":key,"index":own}
				if key == "preset": host.profile.merge(catalog.presets[own].style, true)
				else: host.profile[key] = own
				host.save_profile(); host.open_page("locker"), 1.1 + (index % cols) * (tw + .7), y + floori(float(index) / cols) * (height + .7), tw, height, selected)
			if selected:
				var blob:TextureRect=C.icon(tile,"locker_blob_%d"%tile_sequence,.0,height*.5-tw*.5,tw,tw)
				blob.modulate=Color(1,1,1,.75)
			if key in ["preset", "hair", "hat", "outfit", "brows"]:
				var preview: SplatAvatarPreview = SplatAvatarPreview.make(style, str(host.options.weapon),host.main)
				preview.thumbnail = true
				preview.portrait_kind="body" if key=="outfit" else "face" if key=="brows" else "bust" if key=="preset" else "head"
				C.at(preview,0,0,tw,height)
				tile.add_child(preview)
				preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
			else:
				var face:Control=tile.get_child(0) as Control
				(face.material as ShaderMaterial).set_shader_parameter("radius",tw*6.4)
				C.icon(tile,"iris_%d"%index if key=="eyes" else "skin_%d"%index,tw*.08,height*.08,tw*.84,height*.84)
			if key in ["preset","hair","hat","outfit","brows"]:
				var label: Label = C.label(tile,name,.1,height-1.55,tw-.2,1.4,1.15 if key=="preset" else .8 if key in ["hair","hat","brows"] else .92,true)
				label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			if selected:
				var check:Control=C.panel(tile,tw-2.2,.4,1.8,1.8,Color.WHITE,.9);C.icon(check,"glyph_check",.32,.32,1.16,1.16).modulate=K
			if key==str(host.locker_focus.get("key","preset")) and index==int(host.locker_focus.get("index",0)):C.defer_focus(tile)
			var blurb: String = str(item.get("blurb", "")) if item is Dictionary else "%d of %d"%[index+1,entries.size()]
			tile.focus_entered.connect(func() -> void: hover_title.text = name; hover_text.text = blurb;wearing.visible=selected)
			tile.mouse_entered.connect(tile.grab_focus)
			tile_sequence+=1
		y += ceili(float(entries.size()) / cols) * (height + .7) + .6
	var dice:SplatInkButton=C.button(root, "SHUFFLE", func() -> void: shuffle(host), 3.6, 47.1, 15.3, 3.9, 1.4, "glyph_dice");dice.set_source_ghost()
	C.keycap(dice,"R",12.0,1.12,.78)
	C.icon(root,"glyph_check",28.6,48.0,1.04,1.04).modulate=SplatUiTheme.MINT
	C.label(root, "Saves automatically", 30.1, 47.8, 18, 1.5, .8, false, M)
	C.button(root, "DONE", host._back, 50.5, 47.1, 10.1, 3.9, 1.4, "glyph_check", "", true)
	C.icon(root,"boss_bar_splat",view.width_u-35, .8,7.5,7.5).modulate=O
	var tag: Control = C.panel(root, view.width_u - 32.4, 2.4, 29, 4.1,Color(.078,.063,.125,.9),1.2);tag.rotation=deg_to_rad(1.2)
	C.label(tag, "NAME", 1.2, 1.1, 4, 1.1, .8, false, O)
	var name:SplatNameField=preload("res://scripts/ui/lab_name_field.gd").new()
	name.host=host;name.text = str(host.profile.name)
	C.at(name, 5.3, .45, 23.1, 3.1)
	tag.add_child(name)
	C.icon(tag,"glyph_pencil",26.5,1.25,1.5,1.5).modulate=O
	L.hero_drag(host,root,Rect2(view.width_u-36,11.2,33.5,35.8))
	C.icon(root,"glyph_rotate",view.width_u-26.4,47.7,1.5,1.5)
	var spin:Label=C.label(root, "DRAG TO SPIN", view.width_u - 24.1, 47.5, 18, 1.5, .85);spin.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"))
	look_sheet(root,host.profile,catalog,view.width_u-32.4,7.1,29)
	L.prompts(view, "Enter  Wear    Q E  Tabs    R  Shuffle    Esc  Done", 32)

static func look_sheet(parent:Node,profile:Dictionary,catalog:Dictionary,x:float,y:float,w:float)->void:
	var rows:Array[Dictionary]=[];var current:Array[Dictionary]=[];var used:float=0
	var font:Font=preload("res://assets/fonts/ink_body_900_font.tres")
	for pair:Array in [["HAIR","hair","hair_names"],["HAT","hat","hat_names"],["EYES","eyes","iris_names"],["BROWS","brows","brow_names"],["SKIN","skin","skin_names"],["OUTFIT","outfit","outfit_names"]]:
		var entries:Array=catalog[pair[2]];var selected:int=clampi(int(profile.get(pair[1],0)),0,entries.size()-1);var value:String=str(entries[selected])
		var caption:float=font.get_string_size(str(pair[0]),HORIZONTAL_ALIGNMENT_LEFT,-1,7).x/12.8
		var label:float=font.get_string_size(value,HORIZONTAL_ALIGNMENT_LEFT,-1,9).x/12.8
		var swatch:bool=pair[1] in ["eyes","skin","outfit"];var width:float=.8+caption+.3+label+(1.1 if swatch else 0.0)
		if used+width>w and not current.is_empty():rows.append({"chips":current,"width":used-.35});current=[];used=0
		current.append({"name":pair[0],"key":pair[1],"index":selected,"caption":caption,"value":value,"width":width,"swatch":swatch});used+=width+.35
	if not current.is_empty():rows.append({"chips":current,"width":used-.35})
	for row:Dictionary in rows:
		var pen:float=x+w-float(row.width)
		for chip:Dictionary in row.chips:
			var plate:Control=C.panel(parent,pen,y,float(chip.width),1.3,Color(.055,.043,.086,.72),.65)
			var cap:Label=C.label(plate,str(chip.name),.4,0,float(chip.caption),1.3,.56,false,Color(1,1,1,.55));cap.add_theme_font_override("font",font)
			var start:float=.7+float(chip.caption)
			if chip.swatch:
				var top:Color;var bottom:Color
				if chip.key=="skin":top=Color(str(catalog.skins[chip.index]));bottom=top
				elif chip.key=="eyes":top=Color(str(catalog.iris[chip.index][0]));bottom=Color(str(catalog.iris[chip.index][1]))
				else:top=Color(str(catalog.outfits[chip.index].shirt));bottom=Color(str(catalog.outfits[chip.index].shorts))
				var dot:Control=C.panel(plate,start,.2,.8,.8,top,.4);(dot.material as ShaderMaterial).set_shader_parameter("bottom_color",bottom);(dot.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(dot.material as ShaderMaterial).set_shader_parameter("border",1.5)
				start+=1.1
			var word:Label=C.label(plate,str(chip.value),start,0,float(chip.width)-start,1.3,.72);word.add_theme_font_override("font",font)
			pen+=float(chip.width)+.35
		y+=1.65

static func settings(host: InkUI) -> void:
	var view: SplatLabCanvas = L.canvas(host)
	var root: Control = view.canvas
	L.header(host, view, "SETTINGS", "Changes apply instantly")
	var panel: Control = C.panel(root, 3.6, 10.4, 58, 41.25)
	tabs(panel, ["Controls", "Video", "Audio", "Gameplay"], host.settings_tab, 1.2, 1.2, 55.6, func(index: int) -> void: host.settings_tab = index;host.settings_row=0;host.open_page("settings"))
	var specs: Array = [
		[["sensitivity", "Mouse sensitivity", .2, 3.0, .05], ["padSensitivity", "Controller sensitivity", .2, 3.0, .05], ["invertY", "Invert vertical look"], ["aimAssist", "Aim assist (controller)", 0.0, 1.0, .05], ["aimAssistMouse", "Aim assist for mouse"], ["controls", "Controls reference", "link"]],
		[["quality", "Graphics quality", ["low", "medium", "high", "ultra"]], ["fov", "Field of view", 65.0, 100.0, 1.0], ["shadows", "Shadows"], ["bloom", "Bloom glow"], ["showFps", "Show FPS counter"]],
		[["master", "Master volume", 0.0, 1.0, .05], ["music", "Music", 0.0, 1.0, .05], ["sfx", "Sound effects", 0.0, 1.0, .05]],
		[["cameraShake", "Camera shake", 0.0, 1.0, .05], ["rumble", "Vibration", 0.0, 1.0, .05], ["colorblind", "Colorblind-safe inks"], ["minimap", "Minimap"], ["difficulty", "Default bot skill", ["easy", "normal", "hard"]], ["matchLength", "Default match length", [90, 180]]]
	]
	var help: Control = C.panel(root, 63.6, 10.4, 30.5, 24.6)
	var help_title: Label = C.label(help, "Mouse sensitivity", 1.2, 1.1, 25, 2, 1.55, true)
	var help_value:Control=C.panel(help,24.8,1.5,4.6,1.8,O,.9)
	var help_value_label:Label=C.label(help_value,"1.00×",0,0,4.6,1.8,.95,false,K);help_value_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;help_value_label.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"))
	var stage:Control=C.panel(help,1.2,4.6,28.1,15.8,Color(.02,.016,.032,.34),1.1)
	var preview:=SplatSettingsPreview.new();stage.add_child(preview);C.at(preview,0,0,28.1,15.8)
	var help_text: Label = C.label(help, "How far the camera turns for each bit of mouse movement.", 1.2, 20.7, 28.1, 3.0, .9, false, M)
	help_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var rows: Array = specs[host.settings_tab]
	var shrink:float=(6-rows.size())*4.681
	panel.size.y=(41.32-shrink)*12.8;(panel.material as ShaderMaterial).set_shader_parameter("panel_size",panel.size)
	for index: int in rows.size():
		var spec: Array = rows[index]
		var key: String = str(spec[0])
		var row: Button = C.tile(panel, func() -> void: pass, 1.2, 7.2 + index * 4.681, 55.6, 4.3,false,"setting")
		C.label(row, "●", 1.0, 1.6, .8, 1.0, .5, false, M)
		var row_label:Label=C.label(row, str(spec[1]), 2.4, 1.1, 25, 2.0, 1.1);row_label.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"))
		var row_index:int=index
		var focus_preview:Callable=func()->void:
			if not is_instance_valid(help_title) or host.page!="settings":return
			host.settings_row=row_index
			help_title.text=str(spec[1]);help_text.text=settings_help(key);preview.show_setting(key,host.settings.get(key),host.settings)
			help_value.visible=spec.size()==5;help_value_label.text=format_value(key,float(host.settings.get(key,1))) if spec.size()==5 else ""
		row.focus_entered.connect(focus_preview)
		row.mouse_entered.connect(func()->void:row.grab_focus())
		if index==clampi(host.settings_row,0,rows.size()-1):C.defer_focus(row);focus_preview.call_deferred()
		if spec.size() == 5:
			var slider := HSlider.new()
			slider.min_value = float(spec[2]); slider.max_value = float(spec[3]); slider.step = float(spec[4]); slider.value = float(host.settings.get(key, 1.0))
			C.at(slider, 30.0, 1.4, 17.4, 1.6)
			row.add_child(slider)
			var value: Label = C.label(row, format_value(key, slider.value), 49.2, 1.1, 5.6, 2, 1.4, true)
			slider.focus_mode=Control.FOCUS_NONE
			slider.value_changed.connect(func(amount: float) -> void: host.set_setting(key, amount); value.text = format_value(key, amount);help_value_label.text=value.text;preview.show_setting(key,amount,host.settings))
			row.gui_input.connect(func(event:InputEvent)->void:
				if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):slider.value+=slider.step*(-1 if event.is_action_pressed("ui_left") else 1);row.accept_event())
			row.pressed.connect(func()->void:slider.value=slider.min_value if slider.value>=slider.max_value else slider.value+slider.step)
			style_slider(slider)
		elif spec.size() == 3 and spec[2] is Array:
			var values: Array = spec[2]
			var names: Array = []
			for value: Variant in values:
				if key=="difficulty":names.append(["CHILL","FRESH","FIERCE"][maxi(0,["easy","normal","hard"].find(str(value)))])
				elif key=="matchLength":names.append("90 SEC" if int(value)==90 else "3 MIN")
				else:names.append("MED" if str(value)=="medium" else str(value).to_upper())
			P.segments(row, names, maxi(0, values.find(host.settings.get(key))), 28.8, 1.0, 25.5, 2.4, func(own: int) -> void: host.set_setting(key, values[own]); host.open_page("settings"))
		elif key == "controls": C.button(row, "VIEW  ›", func() -> void: host.open_page("howto"), 48.5, 1.0, 6, 2.3, .9)
		else:
			var toggle := SplatSettingToggle.new()
			toggle.on=bool(host.settings.get(key,false));toggle.focus_mode=Control.FOCUS_NONE
			C.at(toggle, 47.3, .9, 7.0, 2.7)
			row.add_child(toggle)
			toggle.changed.connect(func(on: bool) -> void: host.set_setting(key, on);preview.show_setting(key,on,host.settings))
			row.pressed.connect(func()->void:toggle.set_on(not toggle.on,true);toggle.changed.emit(toggle.on))
			row.gui_input.connect(func(event:InputEvent)->void:
				if event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):toggle.set_on(not toggle.on,true);toggle.changed.emit(toggle.on);row.accept_event())
	C.label(panel, "✓ Changes save automatically", 1.6, 38.0-shrink, 30, 1.5, .85)
	var reset:SplatInkButton=C.button(panel,"RESET TO DEFAULTS",func()->void:reset_settings(host,panel),41.1,37.29-shrink,15.5,2.8,.9,"glyph_reset")
	reset.set_meta("settings_reset",true)
	reset.focus_entered.connect(func()->void:help_title.text="Reset";help_text.text="Restore every setting to its original value.";preview.show_setting("_reset",null,host.settings))
	L.prompts(view, "← →  Adjust     Q E  Tabs     Esc  Back", 25)

static func reset_settings(host:InkUI,panel:Control)->void:
	var reset:SplatInkButton
	for node:Node in panel.get_children():
		if node.has_meta("settings_reset"):reset=node as SplatInkButton;break
	if not reset:return
	var now:float=Time.get_ticks_msec()/1000.0
	if now-float(reset.get_meta("armed_time",-100))>2.6:
		reset.set_meta("armed_time",now);reset.set_source_label("PRESS AGAIN TO CONFIRM")
		host.get_tree().create_timer(2.6).timeout.connect(func()->void:
			if is_instance_valid(reset) and now==float(reset.get_meta("armed_time")):reset.set_source_label("RESET TO DEFAULTS")
		)
		return
	host.settings=InkUI.DEFAULT_SETTINGS.duplicate();host._save();host._apply_settings();host.open_page("settings")

static func format_value(key: String, value: float) -> String:
	if key in ["sensitivity", "padSensitivity"]: return "%.2f×" % value
	if key == "fov": return "%d°" % roundi(value)
	return "%d%%" % roundi(value * 100)

static func settings_help(key: String) -> String:
	var descriptions: Dictionary = {"sensitivity":"How far the camera turns for each bit of mouse movement.","padSensitivity":"Camera turn speed with the right stick.","invertY":"Push up to look down, like a flight stick.","aimAssist":"Gently slows and steers your aim onto nearby rivals when you play with a controller.","aimAssistMouse":"Also apply a lighter aim assist when aiming with a mouse. Off by default.","controls":"Every keyboard, mouse and controller binding in one place.","quality":"Resolution scale, shadow detail, anti-aliasing and particle counts.","fov":"Wider shows more of the turf around you.","shadows":"Soft sun shadows. Turn off for extra speed on older machines.","bloom":"A soft glow around bright ink and specials.","showFps":"Displays frames per second in the corner during matches.","master":"Overall loudness of everything.","music":"Menu and battle soundtrack.","sfx":"Weapons, splats, voices and menu sounds.","cameraShake":"Screen shake from explosions, slams and hits.","rumble":"Controller rumble for hits, splats, bombs and specials. Only while you play with a controller.","colorblind":"Always use high-contrast yellow vs. blue team inks.","minimap":"Show the turf minimap in the corner during matches.","difficulty":"Starting difficulty for new matches.","matchLength":"How long each Turf War lasts."}
	return str(descriptions.get(key, "Changes apply instantly and save automatically."))

static func style_slider(slider: HSlider) -> void:
	var track := StyleBoxFlat.new(); track.bg_color = Color("100e1a"); track.set_corner_radius_all(8); track.content_margin_top = 5; track.content_margin_bottom = 5
	slider.add_theme_stylebox_override("slider", track)
	var fill: StyleBoxFlat = track.duplicate() as StyleBoxFlat; fill.bg_color = O
	slider.add_theme_stylebox_override("grabber_area", fill); slider.add_theme_stylebox_override("grabber_area_highlight", fill)
	var circle := Image.new()
	circle.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="34" height="34"><circle cx="17" cy="17" r="15" fill="white" stroke="#15121c" stroke-width="3"/></svg>')
	var texture: ImageTexture = ImageTexture.create_from_image(circle)
	slider.add_theme_icon_override("grabber", texture); slider.add_theme_icon_override("grabber_highlight", texture)

static func controls(parent: Node, x: float, y: float, w: float, pad: bool, compact: bool = false) -> void:
	var rows: Array = [["Move", "W A S D", "LS"], ["Aim", "MOUSE", "RS"], ["Fire", "LMB", "RT"], ["Swim · squid form", "SHIFT", "LT"], ["Jump", "SPACE", "A"], ["Aim bomb · release to throw", "RMB or E", "RB"], ["Special", "F or Q", "Y"], ["Map", "TAB", "View"], ["Pause", "ESC", "Start"]]
	for index: int in rows.size():
		if compact and index in [1, 7, 8]: continue
		C.label(parent, str(rows[index][0]), x, y, w - 8, 2.85, .9)
		var tokens:PackedStringArray=str(rows[index][2] if pad else rows[index][1]).split(" ",false)
		var keys:Control=Control.new();parent.add_child(keys);C.at(keys,x+w-13,y+.45,13,2.0)
		var pen:float=0
		for token:String in tokens:
			if token=="or":C.label(keys,"or",pen,0,1.7,2,.7,false,M);pen+=1.7
			else:pen+=C.keycap(keys,token,pen,0,.75,pad)
		keys.position.x+=(13-pen)*12.8
		y += 2.85

static func howto(host: InkUI) -> void:
	var view: SplatLabCanvas = L.canvas(host)
	var root: Control = view.canvas
	C.panel(root, 0, 0, view.width_u, view.height_u, Color(.047, .035, .086, .55), 0)
	L.header(host, view, "HOW TO PLAY", "Turf War in 30 seconds")
	var left_w: float = (view.width_u - 9.4) * 1.3 / 2.3
	var tile_w: float = (left_w - 1.5) * .5
	var rules: Array = [["turf", "Ink the turf", "Paint the ground in your team’s color. When time runs out, the team with the most turf wins."], ["swim", "Swim to refill", "Dive into your own ink as a squid to move fast, hide and refill your ink tank."], ["enemy", "Avoid enemy ink", "Enemy ink slows you down and hurts. Paint over it to take the ground back."], ["climb", "Climb inked walls", "Ink a wall, then swim straight up it as a squid to reach high ground."]]
	for index: int in rules.size():
		var card: Control = C.panel(root, 3.6 + (index % 2) * (tile_w + 1.5), 10.4 + floori(index / 2.0) * 20.5, tile_w, 19.0)
		C.panel(card, 1, 1, tile_w - 2, 9.8, Color("86dcf7"), 1)
		C.icon(card, "rule_" + str(rules[index][0]), 1, 1, tile_w - 2, 9.8)
		C.panel(card, -.7, -.9, 2.9, 2.9, O, 1.45)
		C.label(card, str(index + 1), .1, -.6, 1.5, 2.3, 1.5, false, K)
		C.label(card, str(rules[index][1]), 1.4, 11.7, tile_w - 2.8, 1.8, 1.6, true)
		var text: Label = C.label(card, str(rules[index][2]), 1.4, 14.0, tile_w - 2.8, 3.8, 1.0, false, M)
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var right_x: float = 3.6 + left_w + 2.2
	var right_w: float = view.width_u - right_x - 3.6
	var ctl: Control = C.panel(root, right_x, 10.4, right_w, 36.5)
	C.label(ctl, "CONTROLS", 1.6, 1.4, right_w - 3.2, 1.3, 1.0)
	P.segments(ctl, ["KEYBOARD & MOUSE", "CONTROLLER"], 1 if host.controls_pad else 0, 1.6, 3.6, right_w - 3.2, 2.5, func(index: int) -> void: host.controls_pad = index == 1; host.open_page("howto"))
	controls(ctl, 1.6, 7.2, right_w - 3.2, host.controls_pad)
	L.prompts(view, "← →  Switch controls     Esc  Back", 24)

static func pause(host: InkUI) -> void:
	host.content.hide()
	var page:=SplatLabPause.new();host._margin.add_child(page);page.size=host.get_viewport().get_visible_rect().size;page._layout();page.build(host)

static func quit_modal(host: InkUI, view: SplatLabCanvas) -> void:
	var overlay: Control = C.panel(view.canvas, 0, 0, view.width_u, view.height_u, Color(0, 0, 0, .7), 0)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	var card: Control = C.panel(overlay, view.width_u * .5 - 22, view.height_u * .5 - 10, 44, 20)
	C.label(card, "QUIT MATCH?", 2, 2, 40, 3, 2.8, true)
	var message: Label = C.label(card, "You will leave this Turf War and head back to the lobby. Your turf will not count.", 2, 6, 40, 4, 1.1)
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	C.button(card, "KEEP PLAYING", func() -> void: overlay.queue_free(), 2, 13, 23, 4, 1.2)
	C.button(card, "QUIT", func() -> void: host.pause_changed.emit(false); host.exit_requested.emit(); host.show_menu(), 27, 13, 15, 4, 1.5, "", "", false, Color("e03b55"))
