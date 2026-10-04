class_name SplatMatchHud
extends Control
signal pause_requested
signal jump_requested(index: int)
const C = preload("res://scripts/ui/lab_canvas.gd")
var touch: SplatTouchControls
var minimap: SplatMiniMap
var _timer: Label
var _points: Label
var _hp: ProgressBar
var _ink: ProgressBar
var _special: ProgressBar
var _alert: Label
var _feed: Label
var _respawn: Label
var _boss: ProgressBar
var _badges: Array[SplatHudBadge] = []
var _map_panel: Control
var _map_legend: Control
var _view: SplatLabCanvas
var _orb: ColorRect
var _orb_icon: TextureRect
var _special_pct: Label
var _ready_chip: Control
var _alert_seconds: float = 0.0
var _hit_time: float = 0.0
var _kill_time: float = 0.0
var _damage_time: float = 0.0
var _last_hp: float = 100.0
var _frame: Dictionary = {}
var _map_open: bool = false
var _weapon: String = "shooter"
var _clock: float = 0.0
var _ink_level: float = 1.0
var _special_level: float = 0.0
var _intro: Control
var _intro_time: float = 0.0
var _events:SplatHudEvents
var _map_t:float=0
var _map_velocity:float=0
var _tank_style:StyleBoxFlat
var _tank_fill:StyleBoxFlat
var _settings:Dictionary={}
var _fps:Label
var _chrome:Control
var _intro_clock:float=-1.0
var _intro_boss:bool=false
var _ready_fired:bool=false
var _markers:SplatHudMarkers
var _map_dim:ColorRect
var _legend_key:String=""
var _diorama:SplatHudDiorama
var _reticle:Control

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_view = SplatLabCanvas.new()
	_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_view)
	_diorama=preload("res://scripts/ui/hud_diorama.gd").new();_diorama.configure(self,null,_view);_view.canvas.add_child(_diorama)
	_chrome=Control.new();_chrome.mouse_filter=Control.MOUSE_FILTER_IGNORE;_view.canvas.add_child(_chrome)
	var root: Control = _chrome
	for index: int in 8:
		var badge := SplatHudBadge.new()
		C.at(badge, _view.width_u * .5 - 21.85 + (index % 4) * 4.05 + (28.85 if index >= 4 else 0), 1.65, 3.6, 3.6)
		root.add_child(badge)
		_badges.append(badge)
	var timer: Control = C.panel(root, _view.width_u * .5 - 4.8, 1.1, 9.6, 4.7, Color("15121c"), 2.35)
	(timer.material as ShaderMaterial).set_shader_parameter("border_color", Color.WHITE)
	(timer.material as ShaderMaterial).set_shader_parameter("border", 2.6)
	_timer = C.label(timer, "3:00", .2, .1, 9.2, 4.5, 2.75, true)
	_timer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_orb = ColorRect.new()
	var material := ShaderMaterial.new(); material.shader = preload("res://assets/ui/lab_orb.gdshader")
	_orb.material = material; _orb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	C.at(_orb, _view.width_u - 10, 1.3, 7.8, 7.8)
	root.add_child(_orb)
	_orb_icon = C.icon(_orb, "special_slam", 1.87, 1.87, 4.06, 4.06)
	_special_pct = C.label(_orb, "0%", 1.5, 6.0, 4.8, 1, .78)
	_special_pct.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_ready_chip = C.panel(root, _view.width_u - 10.5, 9.5, 9.4, 2.9, SplatUiTheme.ORANGE, 1.4)
	C.label(_ready_chip, "READY!  F", .8, .25, 8, 2.3, 1.35, false, SplatUiTheme.INK)
	_ready_chip.hide()
	var turf: Control = C.panel(root, _view.width_u - 10, 10.3, 7.9, 2.0, Color("211d30"), 1.0)
	C.icon(turf, "glyph_drop", .4, .3, 1.3, 1.3)
	_points = C.label(turf, "0p", 1.8, .1, 5.5, 1.8, 1.25, true)
	_points.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_feed = C.label(root, "", _view.width_u - 24.2, 15.2, 22, 12, .95)
	_feed.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps=C.label(root,"",_view.width_u-8.2,_view.height_u-2.6,6.5,1.4,.8);_fps.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	_map_dim=ColorRect.new();root.add_child(_map_dim);_map_dim.mouse_filter=Control.MOUSE_FILTER_IGNORE;var dim_material:=ShaderMaterial.new();dim_material.shader=preload("res://assets/ui/lab_map_dim.gdshader");_map_dim.material=dim_material;_map_dim.hide()
	_map_panel = C.panel(root, 2.2, _view.height_u - 13.07, 14.5, 10.875, Color("266fac"), 1.5)
	(_map_panel.material as ShaderMaterial).set_shader_parameter("border_color", Color.WHITE)
	(_map_panel.material as ShaderMaterial).set_shader_parameter("border", 2.4)
	minimap = SplatMiniMap.new(); minimap.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_map_panel.add_child(minimap); minimap.custom_minimum_size = Vector2.ZERO
	minimap.jump_requested.connect(func(index: int) -> void: jump_requested.emit(index); toggle_map())
	var map_label: Control = C.panel(_map_panel, 9.8, -1.3, 5.2, 1.85, Color("15121c"), .9)
	C.label(map_label, "TAB MAP", .35, .1, 4.5, 1.5, .75)
	_map_legend = C.panel(root, _view.width_u * .5 + 24, 12, 23, 30)
	C.label(_map_legend, "SUPER JUMP", 1.2, 1.25, 17.1, 2.7, 2.3, true)
	C.label(_map_legend,"Pick a landing spot",1.2,3.45,17.1,1.4,1.0,false,SplatUiTheme.MUTED)
	_map_legend.hide()
	_alert = C.label(root, "", 5, _view.height_u * .5 - 7, _view.width_u - 10, 8, 5.0, true, SplatUiTheme.GOLD)
	_alert.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_respawn = C.label(root, "", 5, _view.height_u * .5 + 1.5, _view.width_u - 10, 4.5, 2.1, true)
	_respawn.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hp = ProgressBar.new(); _ink = ProgressBar.new(); _special = ProgressBar.new()
	for bar: ProgressBar in [_hp, _ink, _special]: add_child(bar); bar.hide(); bar.step = 0
	_boss = ProgressBar.new(); _boss.show_percentage = false
	C.at(_boss, _view.width_u * .5 - 20, 7.6, 40, 1.2)
	root.add_child(_boss); _boss.hide()
	var bg := StyleBoxFlat.new(); bg.bg_color = SplatUiTheme.INK; bg.border_color = Color.WHITE; bg.set_border_width_all(2); bg.set_corner_radius_all(8)
	var fill: StyleBoxFlat = bg.duplicate() as StyleBoxFlat; fill.bg_color = SplatUiTheme.BLUE
	_boss.add_theme_stylebox_override("background", bg); _boss.add_theme_stylebox_override("fill", fill)
	C.label(_boss, "HULLBREAKER", 0, -1.6, 40, 1.4, 1.1, true)
	touch = SplatTouchControls.new(); touch.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT); add_child(touch); touch.visible = SplatUiTheme.touch()
	_view.layout_changed.connect(_layout)
	_events=SplatHudEvents.new();add_child(_events);_events.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);_events.configure(_view,null)
	_markers=preload("res://scripts/ui/hud_markers.gd").new();_chrome.add_child(_markers);_chrome.move_child(_markers,_map_dim.get_index());_markers.configure(self,null)
	_reticle=preload("res://scripts/ui/hud_reticle.gd").new();add_child(_reticle);move_child(_reticle,_events.get_index());_reticle.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_tank_style=StyleBoxFlat.new();_tank_style.bg_color=Color(.055,.043,.086,.78);_tank_style.border_color=Color.WHITE;_tank_style.set_border_width_all(1);_tank_style.set_corner_radius_all(6)
	_tank_fill=StyleBoxFlat.new();_tank_fill.set_corner_radius_all(4)
	_layout()

func configure(game:Node)->void:
	_events.configure(_view,game)
	_markers.configure(self,game)
	_diorama.game=game
	_reticle.configure(game)

func apply_settings(value:Dictionary)->void:
	_settings=value.duplicate()
	if _fps:_fps.visible=bool(_settings.get("showFps",false))

func on_event(kind:String,data:Dictionary)->void:
	_events.on_event(kind,data)
	_reticle.on_event(kind,data)

func show_intro(options:Dictionary,actors:Array)->void:
	_intro_clock=0;_intro_boss=str(options.get("mode","turf"))=="boss";_ready_fired=false;_chrome.hide()
	_events.show_intro(options,actors)

func is_chrome_visible()->bool:
	return _chrome!=null and _chrome.visible

func _layout() -> void:
	if _timer == null: return
	C.at(_chrome,0,0,_view.width_u,_view.height_u)
	C.at(_map_dim,0,0,_view.width_u,_view.height_u)
	C.at(_timer.get_parent() as Control, _view.width_u * .5 - 4.8, 1.1, 9.6, 4.7)
	for index: int in _badges.size(): C.at(_badges[index], _view.width_u * .5 - 21.85 + (index % 4) * 4.05 + (28.85 if index >= 4 else 0), 1.65, 3.6, 3.6)
	C.at(_orb, _view.width_u - 10, 1.3, 7.8, 7.8)
	C.at(_ready_chip, _view.width_u - 10.5, 9.5, 9.4, 2.9)
	C.at(_points.get_parent() as Control, _view.width_u - 10, 13.2 if _special_level >= .999 else 10.3, 7.9, 2.0)
	C.at(_feed, _view.width_u - 24.2, 15.2, 22, 12)
	C.at(_fps,_view.width_u-8.2,_view.height_u-2.6,6.5,1.4)
	_layout_map()
	C.at(_alert, 5, _view.height_u * .5 - 7, _view.width_u - 10, 8)
	C.at(_respawn, 5, _view.height_u * .5 + 1.5, _view.width_u - 10, 4.5)

func _layout_map()->void:
	# Never query a ViewportTexture after its stage/viewport has been disposed.
	var texture_size:Vector2=minimap.data.get("texture_size",minimap.data.get("size",Vector2(350,616)))
	var aspect:float=texture_size.x/maxf(1,texture_size.y)
	var small:Vector2=Vector2(14.5,14.5/aspect) if aspect>=1 else Vector2(14.5*aspect,14.5)
	var start:Vector2=Vector2(2.2,_view.height_u-2.2-small.y)
	C.at(_map_panel,start.x,start.y,small.x,small.y)
	_map_panel.visible=not _map_open and not _diorama.on and bool(_settings.get("minimap",true))
	(_map_panel.material as ShaderMaterial).set_shader_parameter("panel_size",small*12.8)
	_map_legend.hide();_map_dim.hide()
	if _map_panel.get_child_count()>1:
		var chip:Control=_map_panel.get_child(1) as Control
		C.at(chip,small.x-4.4,-1.3,5.2,1.85);chip.visible=true

func update_frame(frame: Dictionary) -> void:
	_frame = frame
	var time_left: float = float(frame.get("time_left", frame.get("time", 180)))
	var displayed_seconds:int=maxi(0,ceili(time_left-.000001))
	_timer.text = "%d:%02d" % [displayed_seconds/60, displayed_seconds%60]
	_timer.add_theme_color_override("font_color", Color("ffe27a") if time_left < 60 else Color.WHITE)
	((_timer.get_parent() as ColorRect).material as ShaderMaterial).set_shader_parameter("top_color", Color("c8173a") if time_left <= 10 else Color("3a1a4f") if time_left <= 60 else Color("15121c"))
	_points.text = "%dp" % int(frame.get("points", frame.get("score", 0)))
	_hp.max_value = float(frame.get("max_hp", 100)); _hp.value = float(frame.get("hp", frame.get("health", 100)))
	if _hp.value < _last_hp: _damage_time = .25
	_last_hp = _hp.value
	_ink.max_value = float(frame.get("max_ink", 100)); _ink.value = float(frame.get("ink", 100))
	_special_level = float(frame.get("special", 0)); _special_level = _special_level / 100 if _special_level > 1 else _special_level
	_special.value = _special_level * 100
	_ink_level = lerpf(_ink_level, _ink.value / maxf(_ink.max_value, 1), .2)
	(_orb.material as ShaderMaterial).set_shader_parameter("level", _special_level)
	(_orb.material as ShaderMaterial).set_shader_parameter("ink", frame.get("team_color", SplatUiTheme.ORANGE))
	_ready_chip.visible = _special_level >= .999
	_special_pct.text = "" if _ready_chip.visible else "%d%%" % roundi(_special_level * 100)
	var weapon: String = str(frame.get("weapon", "shooter"))
	if weapon != _weapon:
		_weapon = weapon
		var special: String = str(SplatUiTheme.catalog().weapons.get(weapon, {}).get("special", "slam"))
		_orb_icon.texture = load("res://assets/ui/source/special_%s.svg" % special) as Texture2D
	var respawn: float = float(frame.get("respawn", 0))
	_respawn.text = ""
	var roster: Array = frame.get("roster", []) as Array
	var local_team: int = 0
	if frame.get("map") is Dictionary:
		for player: Dictionary in frame.map.get("players", []):
			if bool(player.get("local", false)): local_team = int(player.get("team", 0))
	var ordered: Array = []
	for team: int in [local_team, 1 - local_team]:
		var own: Array = roster.filter(func(player: Dictionary) -> bool: return int(player.get("team", 0)) == team)
		if team!=local_team:own.reverse()
		if frame.has("boss_hp"): ordered = roster.duplicate(); break
		for index: int in 4: ordered.append(own[index] if index < own.size() else {})
	for index: int in _badges.size():
		_badges[index].visible = index < ordered.size() and not (ordered[index] as Dictionary).is_empty()
		if _badges[index].visible: _badges[index].update_badge(ordered[index], frame.get("team_color", SplatUiTheme.ORANGE) if index < 4 or frame.has("boss_hp") else frame.get("enemy_color", SplatUiTheme.BLUE))
	if frame.get("map") is Dictionary:
		var map: Dictionary = (frame.map as Dictionary).duplicate(); map.local_team = local_team; map.local_color = frame.get("team_color", SplatUiTheme.ORANGE); map.enemy_color = frame.get("enemy_color", SplatUiTheme.BLUE)
		for index:int in mini(roster.size(),map.get("players",[]).size()):
			var pin:Dictionary=map.players[index];pin.name=roster[index].get("name","Squidkid");pin.weapon=roster[index].get("weapon","shooter");pin.respawn=roster[index].get("respawn",0)
		minimap.update_map(map)
	if bool(frame.get("hit", false)): _hit_time = .18
	if bool(frame.get("kill", false)): _kill_time = .55
	if frame.has("feed"):
		var lines: PackedStringArray = []
		if frame.feed is Array:
			for item: Variant in frame.feed: lines.append(str(item.get("text", "")) if item is Dictionary else str(item))
			_feed.text = "\n".join(lines)
		else: _feed.text = str(frame.feed)
	if frame.has("alert") and str(frame.alert) != _alert.text: banner(str(frame.alert))
	_boss.hide() # Source BossHud owns the emblem / chip HP / phases and callouts above this layer.
	_events.update_frame(frame)
	_markers.update_frame(frame)
	_reticle.update_frame(frame)
	_layout()
	queue_redraw()

func update_combat_reticle(fragment:Dictionary)->void:
	# Root calls after render-frame aim computation. Roster/map retain their cheaper cadence.
	_frame.merge(fragment,true)
	_reticle.update_frame(_frame)

func combat_profile_metrics()->Dictionary:
	return _reticle.profile_metrics() if is_instance_valid(_reticle) else {}

func banner(value: String, seconds: float = 2) -> void:
	_alert.text="";_alert_seconds=0
	value=str({"ready":"READY?","go":"GO!","one_minute":"1 minute left!","timesup":"TIME'S UP!","special":"SPECIAL!"}.get(value,value))
	var ui:Node=get_parent().get_parent()
	if value.contains("UP!") and ui.get("boss_hud") is SplatBossHud and (ui.get("boss_hud") as SplatBossHud).times_up():return
	_events.banner(value)

func toggle_map() -> void:
	set_map_open(not _map_open)

func map_cursor_vector()->Vector2:
	return _diorama.cursor_vector() if is_instance_valid(_diorama) else Vector2.ZERO

func clear_world_map()->void:
	_map_open=false;_map_t=0;_map_velocity=0
	if minimap:minimap.clear_map()
	_frame.erase("map")
	if _diorama:_diorama.hide();_diorama.on=false
	_layout()

func _refresh_map_legend(map:Dictionary)->void:
	var beacons:Array=map.get("beacons",[]) as Array
	if beacons.is_empty():
		for player:Dictionary in map.get("players",[]):
			if int(player.get("team",0))==int(map.get("local_team",0)) and not bool(player.get("local",player.get("isSelf",false))):beacons.append({"name":player.get("name","Squidkid"),"weapon":player.get("weapon","shooter"),"ok":bool(player.get("alive",true)) and not bool(player.get("superjump_state",false)),"respawn":player.get("respawn",0)})
		beacons=beacons.slice(0,3)
		if map.has("base_uv"):beacons.append({"name":"Base","home":true,"ok":true})
	var signature:String=JSON.stringify(beacons)
	if signature==_legend_key:return
	_legend_key=signature
	for node:Node in _map_legend.get_children():
		if node.has_meta("beacon"):_map_legend.remove_child(node);node.queue_free()
	for index:int in mini(4,beacons.size()):
		var beacon:Dictionary=beacons[index];var own:int=index+1;var home:bool=bool(beacon.get("home",false));var ready:bool=bool(beacon.get("ok",true))
		var button:Button=C.tile(_map_legend,func()->void:jump_requested.emit(own);toggle_map(),1.2,5.85+index*4.1,17.1,3.65,false,"setting");button.set_meta("beacon",true);button.disabled=not ready;button.modulate.a=1.0 if ready else .45
		C.panel(button,0,0,17.1,3.65,Color(1,1,1,.05),.8);C.keycap(button,str(own),.4,.75,.95)
		var icon:Control=C.panel(button,3.1,.47,2.7,2.7,SplatUiTheme.INK if home else _frame.get("team_color",SplatUiTheme.ORANGE),1.35)
		C.icon(icon,"special_slam" if home else "weaponw_"+str(beacon.get("weapon","shooter")),.3,.3,2.1,2.1).modulate=_frame.get("team_color",SplatUiTheme.ORANGE) if home else Color.WHITE
		var name:Label=C.label(button,str(beacon.get("name","Squidkid")),6.4,.35,7.0,2.9,1.2);name.add_theme_font_override("font",SplatUiTheme.DISPLAY)
		var state_word:Label=C.label(button,"READY" if ready else "%ds"%ceili(float(beacon.get("respawn",0))),13.35,1.0,3.2,1.4,.72,false,Color("ffc48a") if ready else Color.WHITE);state_word.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"))
	var foot:Control=Control.new();_map_legend.add_child(foot);foot.set_meta("beacon",true);C.at(foot,1.2,22.3,17.1,3.5)
	C.label(foot,"Press",0,0,2.5,1.6,.78);C.keycap(foot,"1",2.8,.1,.70);C.label(foot,"–",4.3,0,1,1.6,.78);C.keycap(foot,"4",5.4,.1,.70);C.label(foot,"or click · release",7.3,0,9.8,1.6,.78);C.keycap(foot,"TAB",0,1.95,.70);C.label(foot,"to cancel",3.5,1.8,10,1.6,.78)

func set_map_open(value:bool) -> void:
	if value and is_instance_valid(_events.game):
		if str(_events.game.get("state"))!="playing" or bool(_events.game.get("paused")):return
	_map_open=value
	minimap.expanded=false
	_map_dim.hide();_map_legend.hide();_layout()

func _process(delta: float) -> void:
	_clock += delta
	if _intro_clock>=0:
		if is_instance_valid(_events.game) and str(_events.game.get("state"))=="intro":_intro_clock=float(_events.game.get("match_clock"))
		elif not is_instance_valid(_events.game) or str(_events.game.get("state"))!="waiting":_intro_clock+=delta
		if not _ready_fired and _intro_clock>=(5.3 if _intro_boss else 1.7):_ready_fired=true;banner("READY?")
		if _intro_clock>=(5.6 if _intro_boss else 3.0):_chrome.show();_intro_clock=-1
	if _fps and _fps.visible:_fps.text="%d FPS"%roundi(Engine.get_frames_per_second())
	var safe_delta:float=minf(delta,.05)
	_map_velocity+=(190.0*((1.0 if _map_open else 0.0)-_map_t)-21.0*_map_velocity)*safe_delta
	_map_t+=_map_velocity*safe_delta
	if absf((1.0 if _map_open else 0.0)-_map_t)<.001 and absf(_map_velocity)<.001:_map_t=1.0 if _map_open else 0.0;_map_velocity=0
	if minimap and is_visible_in_tree():_layout_map()
	if is_instance_valid(_events.callout):_events.callout.visible=not _map_open and not _diorama.on
	if _reticle:_reticle.visible=is_chrome_visible() and not _map_open and not _diorama.on and float(_frame.get("respawn",0))<=0 and bool(_frame.get("alive",true))
	_alert_seconds = maxf(0, _alert_seconds - delta)
	if _alert_seconds <= 0: _alert.text = ""
	_hit_time = maxf(0, _hit_time - delta); _kill_time = maxf(0, _kill_time - delta); _damage_time = maxf(0, _damage_time - delta)
	if is_visible_in_tree(): queue_redraw()

