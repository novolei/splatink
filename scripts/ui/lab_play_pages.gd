class_name SplatLabPlayPages
extends RefCounted
const C = preload("res://scripts/ui/lab_canvas.gd")
const L = preload("res://scripts/ui/lab_screens.gd")
const O := Color("ff8a14")
const B := Color("2f5bff")
const K := Color("15121c")
const M := Color("c3bdd6")

static func stage(parent: Node, id: String, time: String, x: float, y: float, w: float, h: float, opacity: float = 1) -> TextureRect:
	var image: TextureRect = C.image(parent, "res://assets/ui/stages/%s-%s.webp" % [id, time], x, y, w, h)
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.modulate = Color(opacity, opacity, opacity)
	return image

static func mode(host: InkUI) -> void:
	var view: SplatLabCanvas = L.canvas(host)
	var root: Control = view.canvas
	stage(root, "tidewater", "day", 0, 0, view.width_u, view.height_u, .35)
	L.header(host, view, "PLAY", "Choose a mode · you and the bots")
	var left: float = view.width_u * .5 - 39.1
	for index: int in 2:
		var id: String = "turf" if index == 0 else "boss"
		var picked: String = id
		var tile: Button = C.tile(root, func() -> void:
			host.options.mode = picked
			host.options.duration = 180 if picked == "turf" else 240
			host.open_page("setup"), left + index * 41.2, 12.2, 37, 34.5)
		tile.rotation = deg_to_rad(-1.4 if index == 0 else 1.4)
		var outer:Control=C.panel(tile,-.3,-.3,37.6,35.1,Color.TRANSPARENT,2.4);outer.z_index=9
		(outer.material as ShaderMaterial).set_shader_parameter("top_color",Color.TRANSPARENT);(outer.material as ShaderMaterial).set_shader_parameter("bottom_color",Color.TRANSPARENT);(outer.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(outer.material as ShaderMaterial).set_shader_parameter("border",3.8)
		stage(tile, "tidewater" if index == 0 else "kelpline", "day" if index == 0 else "dusk", 0, 0, 37, 21.05, .80 if index == 0 else .60)
		var splat:TextureRect=C.icon(tile,"mode_splat_%d"%index,5,1.65,27,27);splat.modulate=O if index==0 else B;splat.modulate.a=.95
		(tile.get_child(2).material as ShaderMaterial).set_shader_parameter("border_color",O if index==0 else B)
		if index == 0:
			C.icon(tile, "squid", 4, 8, 11, 11)
			C.label(tile, "VS", 15.5, 11, 6, 5, 4, true)
			C.icon(tile, "squid_blue", 23, 8, 11, 11)
		else: C.icon(tile, "boss_silhouette", 1.8, 5.0, 33.5, 16)
		var kicker:Control=C.panel(tile, 1.4, 1.4, 5.6, 1.55, K, .4);kicker.rotation=deg_to_rad(-3)
		(kicker.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(kicker.material as ShaderMaterial).set_shader_parameter("border",2.0)
		C.label(tile, "CLASSIC" if index == 0 else "CO-OP", 1.8, 1.55, 5, 1.2, .8)
		var tape: Control = C.panel(tile, 1.1, 18.15, 34.8, 4.8, O if index == 0 else B, .1)
		tape.rotation = deg_to_rad(-3)
		C.label(tape, "TURF WAR" if index == 0 else "BOSS BATTLE", 1.2, .1, 32, 4.4, 3.5, true)
		var blurb: Label = C.label(tile, "Two teams of four, one harbour. Ink the most ground before the whistle." if index == 0 else "Everyone’s one squad against HULLBREAKER, a giant crab in a rusted container. Sink it before time runs out!", 1.8, 24, 33.4, 4.5, 1.0)
		blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var chip_x:float=1.6
		for chip:Array in ([["4 V 4","glyph_squidlet",5.4],["3 MIN","glyph_clock",6.1],["VS BOTS","glyph_bots",7.2]] if index==0 else [["SQUAD OF 8","glyph_squad",9.2],["4 MIN","glyph_clock",6.1],["1 BOSS","boss_emblem",6.5]]):
			var p:Control=C.panel(tile,chip_x,31.0,float(chip[2]),1.9,Color(1,1,1,.1),.95);C.icon(p,str(chip[1]),.35,.4,1.1,1.1).modulate=Color("ffc48a") if index==0 else Color("9fb5ff");C.label(p,str(chip[0]),1.7,.15,float(chip[2])-2,1.6,.75);chip_x+=float(chip[2])+.5
		var go:Control=C.panel(tile,27.4,30.85,8.1,2.2,O if index==0 else B,1.1);C.icon(go,"glyph_play",.55,.5,1.2,1.2).modulate=K;var go_word:Label=C.label(go,"SELECT",2.0,.2,5.6,1.8,.85,false,K);go_word.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"));go.visible=id==str(host.options.mode)
		tile.focus_entered.connect(func()->void:go.show();tile.position.y=(12.2-1)*12.8)
		tile.focus_exited.connect(func()->void:go.hide();tile.position.y=12.2*12.8)
		if index == 1:
			C.panel(tile, 29.4, -.5, 6.4, 2, SplatUiTheme.GOLD, 1)
			C.label(tile, "NEW!", 30, -.4, 5.4, 1.8, 1.5, false, K)
			var beta:Control=C.panel(tile,8.2,1.4,9,1.5,Color.WHITE,.3);beta.rotation=deg_to_rad(2);C.label(beta,"PUBLIC BETA",.4,.15,8.2,1.2,.7,false,K)
		if id == str(host.options.mode): C.defer_focus(tile)
	L.prompts(view, "← →  Mode     Enter  Select     Esc  Back", 26)

static func setup(host: InkUI) -> void:
	var view: SplatLabCanvas = L.canvas(host)
	var root: Control = view.canvas
	var selected: Dictionary = {}
	var maps: Array = []
	for map: Dictionary in SplatUiTheme.catalog().maps:
		if not bool(map.get("onlineOnly", false)): maps.append(map)
		if map.id == host.options.stage: selected = map
	if selected.is_empty(): selected = maps[0]
	var boss: bool = host.options.mode == "boss"
	stage(root, str(selected.id), str(host.options.time_of_day), 0, 0, view.width_u, view.height_u, .24)
	L.header(host, view, "BOSS BATTLE" if boss else "TURF WAR", "Pick a stage and the time of day · your squad of 8 vs HULLBREAKER" if boss else "Pick a stage and the time of day · 4 v 4 against bots")
	C.label(root, "▥  STAGES", 3.6, 10.4, 25.5, 1.3, 1.0)
	for index: int in maps.size():
		var map: Dictionary = maps[index]
		var id: String = str(map.id)
		var tile: Button = C.tile(root, func() -> void:
			host.options.stage = id; host.options.map = id; host.options.mapId = id
			host.open_page("setup"), 3.6, 12.8 + index * 8.25, 25.5, 7.1, id == host.options.stage)
		stage(tile, id, str(host.options.time_of_day), .18, .18, 25.14, 6.74, .6)
		C.panel(tile, .95, 2.15, 2.8, 2.8, O if id == host.options.stage else Color.WHITE, 1.4)
		C.label(tile, "%02d" % (index + 1), 1.3, 2.3, 2.1, 2.2, 1.15, false, K)
		C.label(tile, str(map.name), 4.5, 2.3, 19.4, 2.2, 1.55, true)
		C.icon(tile, "glyph_sun" if host.options.time_of_day == "day" else "glyph_moon", 22.25, .9, 1.7, 1.7)
		if id == host.options.stage: C.defer_focus(tile)
	var match_card: Control = C.panel(root, 3.6, 38.75, 24.6, 15.95)
	C.label(match_card, "DIFFICULTY" if boss else "♟  BOT SKILL", 1.4, 1.25, 22, 1.0, .9)
	segments(match_card, ["CHILL", "FRESH", "FIERCE"], ["easy", "normal", "hard"].find(host.options.difficulty), 1.4, 3.45, 21.6, 2.3, func(index: int) -> void: host.options.difficulty = ["easy", "normal", "hard"][index]; host.open_page("setup"))
	var descriptions: Dictionary = {"easy": "Laid-back bots — a good place to get your sea legs.", "normal": "Balanced bots that push turf and fight back.", "hard": "Fierce bots that fight hard and use their specials."}
	if boss:descriptions={"easy":"A sleepier crab: less HP, softer hits and longer breathers between attacks.","normal":"The full HULLBREAKER. Dodge the tells, punish the openings.","hard":"Tougher shell, harder hits, relentless pace. Bring the whole squad."}
	var tip: Label = C.label(match_card, str(descriptions[host.options.difficulty]), 1.4, 6.65, 21.6, 2.6, .8, false, M)
	tip.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	C.label(match_card, "◷  MATCH LENGTH", 1.4, 10.2, 22, 1.2, .9)
	var durations: Array = [180, 240, 300] if boss else [90, 180]
	segments(match_card, ["3 MIN", "4 MIN", "5 MIN"] if boss else ["90 SEC", "3 MIN"], maxi(0, durations.find(int(host.options.duration))), 1.4, 12.5, 21.6, 2.3, func(index: int) -> void: host.options.duration = durations[index]; host.open_page("setup"))
	var hw: float = view.width_u - 35.4
	var frame: Control = C.panel(root, 32, 10.6, hw, 30.4, Color.WHITE, 1.9)
	frame.rotation = deg_to_rad(-.7)
	frame.clip_contents = true
	stage(frame, str(selected.id), str(host.options.time_of_day), .34, .34, hw - .68, 29.72)
	var layout:Control=C.panel(frame,hw-15.15,22.48,13.5,6.7,Color.WHITE,.9);layout.rotation=deg_to_rad(2.2)
	(layout.material as ShaderMaterial).set_shader_parameter("border_color",K);(layout.material as ShaderMaterial).set_shader_parameter("border",2.3)
	C.icon(layout,"layout_"+str(selected.id),.35,.35,12.8,5.95)
	var layout_caption:Control=C.panel(layout,.9,-.85,5.8,1.25,K,.625);C.icon(layout_caption,"glyph_map",.4,.25,.85,.85).modulate=O;C.label(layout_caption,"LAYOUT",1.55,0,3.9,1.25,.62)
	C.panel(frame, 1.1, 1.4, 9.2, 2, K, .5)
	C.label(frame, "STAGE  %02d / 03" % (maps.find(selected) + 1), 1.6, 1.6, 8.5, 1.6, .8)
	if boss:
		var badge:Control=C.panel(frame,1.3,4.4,16.9,4.0,Color(K,.92),2.0);badge.rotation=deg_to_rad(-2.5)
		(badge.material as ShaderMaterial).set_shader_parameter("border_color",B);(badge.material as ShaderMaterial).set_shader_parameter("border",2.5)
		var emblem:Control=C.panel(badge,.3,.3,3.4,3.4,K,1.7);(emblem.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(emblem.material as ShaderMaterial).set_shader_parameter("border",2.0)
		C.icon(emblem,"boss_emblem",-.1,.0,3.6,3.6)
		C.label(badge,"BOSS",4.2,.45,10.6,1.0,.75,false,Color("8da5ff")).add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"))
		C.label(badge,"HULLBREAKER",4.2,1.5,11.6,1.65,1.35,true)
	var tape: Control = C.panel(frame, 2.0, 22.7, minf(hw - 4, 42), 4.9, K, .1)
	tape.rotation = deg_to_rad(-3)
	C.label(tape, str(selected.name), 1.0, .05, 40, 4.7, 3.4, true)
	C.label(frame, str(selected.blurb), 2, 27.55, hw - 4, 1.6, 1.1)
	var time_card: Control = C.panel(frame, hw - 20.2, 1.0, 19.1, 9.3)
	C.label(time_card, "TIME OF DAY     Q E", .9, .8, 17.3, 1.2, .8)
	segments(time_card, ["☀ DAY", "DUSK ☾"], 0 if host.options.time_of_day == "day" else 1, .9, 2.6, 17.3, 4, func(index: int) -> void:
		host.options.time_of_day = "day" if index == 0 else "dusk"; host.options.timeOfDay = host.options.time_of_day; host.open_page("setup"),Color.WHITE,Color("54bbff"))
	C.label(time_card, "Bright sun, crisp shadows." if host.options.time_of_day == "day" else "Warm skies, cool ink.", .9, 7.0, 17.3, 1.2, .8)
	var ww: float = (hw - 27.4) * .5
	var weapon: Dictionary = SplatUiTheme.catalog().weapons[str(host.options.weapon)]
	var weapon_card: Button = C.tile(root, func() -> void: host.open_page("loadout"), 32, 44, ww, 5.8)
	C.icon(weapon_card, "weapon_" + str(host.options.weapon), 1.1, .7, 4.5, 4.2)
	C.label(weapon_card, "WEAPON", 7.1, .8, ww - 8, 1.0, .75, false, M)
	C.label(weapon_card, str(weapon.name), 7.1, 2.15, ww - 8, 2.0, 1.6, true)
	var kid: Button = C.tile(root, func() -> void: host.open_page("locker"), 32 + ww + 1.2, 44, ww, 5.8)
	C.icon(kid, "squid", 1.0, .5, 4.5, 4.5)
	C.label(kid, "SQUIDKID", 7.1, .8, ww - 8, 1.0, .75, false, M)
	C.label(kid, str(host.profile.name), 7.1, 2.15, ww - 8, 2.0, 1.6, true)
	C.button(root, "START!", host.start_match, view.width_u - 28.4, 44, 25, 5.8, 2.7, "glyph_play", "%s · %s · Fresh · %d MIN" % [selected.name, str(host.options.time_of_day).to_upper(), int(host.options.duration) / 60], false)
	L.prompts(view, "↑ ↓  Stage    ← →  Day · Dusk    Enter  Select    Esc  Back", 36)

static func segments(parent: Node, names: Array, selected: int, x: float, y: float, w: float, h: float, changed: Callable,selected_color:Color=O,base_color:Color=Color("11101b")) -> void:
	C.panel(parent, x, y, w, h, base_color, h * .5)
	var each: float = w / names.size()
	for index: int in names.size():
		var own: int = index
		var node := Button.new()
		node.text = str(names[index])
		node.add_theme_font_override("font", preload("res://assets/fonts/ink_body_900_font.tres"))
		node.add_theme_font_size_override("font_size", roundi(.95 * 12.8))
		node.add_theme_color_override("font_color", K if selected == index else Color.WHITE)
		for state: String in ["normal", "hover", "pressed", "focus"]:
			var box := StyleBoxFlat.new(); box.bg_color = selected_color if index == selected else Color.TRANSPARENT
			box.set_corner_radius_all(roundi(h * 6.4))
			if state == "focus": box.border_color = Color.WHITE; box.set_border_width_all(2)
			node.add_theme_stylebox_override(state, box)
		C.at(node, x + index * each + .2, y + .2, each - .4, h - .4)
		parent.add_child(node)
		node.pressed.connect(func() -> void: changed.call(own))
		SplatSourceFeedback.attach(node,"ui_toggle")

static func loadout(host: InkUI) -> void:
	host.content.hide()
	var page:=SplatLabLoadout.new();host._margin.add_child(page);page.size=host.get_viewport().get_visible_rect().size;page._layout();page.build(host)
