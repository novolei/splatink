class_name InkUI
extends CanvasLayer
## Public native UI boundary. No gameplay state or world simulation lives in the UI.

signal start_requested(options: Dictionary)
signal pause_changed(paused: bool)
signal exit_requested
signal style_changed(style: Dictionary)
signal weapon_changed(id: String)
signal super_jump_requested(index: int)
signal online_requested(options: Dictionary)
signal judge_finished(winner:int)

const SAVE_PATH := "user://splatink_ui.cfg"
var options: Dictionary = {"stage": "tidewater", "map": "tidewater", "mapId": "tidewater", "time_of_day": "day", "timeOfDay": "day", "difficulty": "normal", "duration": 180, "weapon": "shooter", "mode": "turf", "palette": 0}
var profile: Dictionary = {"name": "Fresh Kid", "hair": 0, "skin": 0, "outfit": 0, "eyes": 0, "hat": 0, "brows": 0}
const DEFAULT_SETTINGS: Dictionary = {"sensitivity": 1.0, "padSensitivity": 1.0, "invertY": false, "fov": 82.0, "master": 0.8, "music": 0.6, "sfx": 0.85, "quality": "high", "shadows": true, "bloom": true, "showFps": false, "colorblind": false, "minimap": true, "reduce_motion": false, "touch": false, "aimAssist": 1.0, "aimAssistMouse": false, "screenShake": true, "cameraShake": 1.0, "rumble": 1.0, "difficulty": "normal", "matchLength": 180}
var settings: Dictionary = DEFAULT_SETTINGS.duplicate()
var main: Node
var root: Control
var content: VBoxContainer
var hud: SplatMatchHud
var boss_hud:SplatBossHud
var page: String = "main"
var in_match: bool = false
var _menu: Control
var _backdrop: SplatUiBackdrop
var _margin: MarginContainer
var _toast: Label
var _toast_timer: float = 0
var _toasts:SplatLabToasts
var _paused: bool = false
var lobby_data: Dictionary = {}
var locker_tab: int = 0
var settings_tab: int = 0
var settings_row:int=0
var locker_focus:Dictionary={"key":"preset","index":0}
var controls_pad: bool = false
var online_transport: String = "relay"
var online_address: String = "127.0.0.1"
var results_view: SplatLabResults
var results_data: Dictionary = {}
var _history: Array[String] = []
var news_seen:String=""
var _news:SplatLabNews
var _loaded_settings:bool=false
var _last_view:Vector2=Vector2.ZERO
var _resize_queued:bool=false
var _modal:SplatLabCanvas
var _modal_focus:Control
var _wipe:SplatInkWipe
var _cursor:SplatLabCursor
var _page_token:int=0
var fixture_mode:bool=false
var nonpersistent:bool=false
const LIGHT_PAGES:Array[String]=["main","play","mode","loadout","setup","locker","settings","howto","credits","pause","online","lobby"]
const FULL_WIPES:Array[String]=["loading>title","title>main","results>main","pause>main","pause>title","online>lobby","lobby>online","lobby>main","results>lobby","pause>online"]

func setup(controller: Node) -> void:
	main = controller
	sync_profile_stats()
	if is_instance_valid(hud): hud.configure(controller)
	if is_instance_valid(boss_hud):boss_hud.configure(controller,hud)
	style_changed.emit(profile.duplicate())
	weapon_changed.emit(str(options.weapon))
	_apply_settings()
	if page == "main" and is_instance_valid(_margin): show_menu()

func sync_profile_stats()->void:
	if not is_instance_valid(main) or not main.get("_profile") is Dictionary:return
	var progress:Dictionary=main.get("_profile") as Dictionary
	for key:String in ["level","xp","wins"]:
		if progress.has(key):profile[key]=progress[key]
	profile.played=progress.get("matches",progress.get("played",0))
	profile.xp_to_next=800+int(profile.get("level",1))*350

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load()
	if SplatUiTheme.touch() and not _loaded_settings:settings.quality="medium"
	root = Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = SplatUiTheme.THEME
	add_child(root)
	_menu = Control.new()
	_menu.z_index=10
	_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(_menu)
	_backdrop = SplatUiBackdrop.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(_backdrop)
	_margin = MarginContainer.new()
	_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_menu.add_child(_margin)
	hud = SplatMatchHud.new()
	hud.pause_requested.connect(toggle_pause)
	hud.jump_requested.connect(func(index: int) -> void: super_jump_requested.emit(index))
	root.add_child(hud)
	hud.hide()
	boss_hud=SplatBossHud.new();boss_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(boss_hud);boss_hud.configure(null,hud)
	_toast = SplatUiTheme.text("", 24, true, SplatUiTheme.GOLD)
	_toast.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_toast.offset_top = -54
	_toast.offset_bottom = -18
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(_toast)
	_toast.hide()
	_toasts=SplatLabToasts.new();_toasts.host=self;_toasts.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(_toasts)
	_cursor=SplatLabCursor.new();_cursor.host=self;_cursor.z_index=49;_cursor.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(_cursor)
	_wipe=preload("res://scripts/ui/ink_wipe.gd").new();_wipe.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(_wipe)
	get_viewport().size_changed.connect(_resize)
	_resize()
	show_menu()

func _resize() -> void:
	var view: Vector2 = get_viewport().get_visible_rect().size
	var safe: Rect2 = SplatUiTheme.safe_rect(view)
	var padding: int = 0
	_margin.add_theme_constant_override("margin_left", roundi(safe.position.x) + padding)
	_margin.add_theme_constant_override("margin_right", roundi(view.x - safe.end.x) + padding)
	_margin.add_theme_constant_override("margin_top", roundi(safe.position.y) + padding)
	_margin.add_theme_constant_override("margin_bottom", roundi(view.y - safe.end.y) + padding)
	if _last_view!=Vector2.ZERO and view!=_last_view and is_instance_valid(content) and not _resize_queued:
		_resize_queued=true
		(func()->void:
			_resize_queued=false
			if not is_inside_tree() or in_match and not _paused:return
			if page=="main":show_menu()
			elif page=="title":show_title()
			elif page!="loading":open_page(page)
		).call_deferred()
	_last_view=view

func show_menu() -> void:
	if is_instance_valid(hud):hud.clear_world_map();hud.hide()
	var previous:String=page
	page="main"
	_page_change(previous,"main",_show_main)

func _show_main()->void:
	sync_profile_stats()
	in_match = false
	_paused = false
	page = "main"
	_history.clear()
	hud.hide()
	if is_instance_valid(boss_hud):boss_hud.clear()
	hud.touch.reset()
	_menu.show()
	_backdrop.show()
	_menu.mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	clear_page()
	SplatUiPages.main_menu(self)
	maybe_show_news()

func maybe_show_news()->void:
	if news_seen=="mp-expansion-1" or is_instance_valid(_news):return
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--page") or argument in ["--autostart","--autopilot","--netmock","--skip-title"]:return
	get_tree().create_timer(.7).timeout.connect(func()->void:
		if not is_inside_tree() or page!="main" or news_seen=="mp-expansion-1" or is_instance_valid(_news):return
		news_seen="mp-expansion-1";_save()
		_news=SplatLabNews.new();_news.z_index=50;_news.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(_news)
		_news._layout();_news.build(self)
		_news.closed.connect(func(action:String)->void:
			_news=null
			if action=="try":options.mode="boss";_history=["main","play"];open_page("setup")
			elif page=="main":show_menu()
		)
	)

func show_title() -> void:
	var previous:String=page;page="title"
	_page_change(previous,"title",func()->void:
		in_match = false;_history.clear()
		hud.hide(); _menu.show(); _backdrop.hide(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		clear_page(); SplatLabFinishPages.title(self))

func show_loading(progress:float=0,message:String="MAKING WAVES…") -> void:
	in_match = false; page = "loading"
	hud.hide(); _menu.show(); _backdrop.hide(); Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	clear_page(); SplatLabFinishPages.loading(self,progress,message)

func show_hud() -> void:
	_page_token+=1
	if is_instance_valid(_wipe) and _wipe.pending_swap():_wipe.abort()
	page="";_history.clear()
	in_match = true
	_paused = false
	hud.set_map_open(false)
	_menu.hide()
	hud.show()
	hud.touch.visible = SplatUiTheme.touch() or bool(settings.touch)
	if not hud.touch.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func open_page(value: String) -> void:
	_show_page(value,false,true)

func _show_page(value:String,back:bool,remember:bool)->void:
	var previous:String=page
	if remember and page != value: _history.append(page)
	page = value
	_page_change(previous,value,func()->void:_build_page(value),back)

func _build_page(value:String)->void:
	clear_page()
	match value:
		"play", "mode": SplatUiPages.mode_select(self)
		"setup": SplatUiPages.setup_match(self)
		"loadout": SplatUiPages.loadout(self)
		"locker": SplatUiExtras.locker(self)
		"settings": SplatUiExtras.settings_page(self)
		"howto": SplatUiExtras.help_page(self)
		"online": SplatUiExtras.online_page(self)
		"lobby": SplatLabOnlinePages.lobby(self, lobby_data)
		"credits": SplatUiExtras.credits_page(self)
		"pause": SplatUiExtras.pause_page(self)
		"title": SplatLabFinishPages.title(self)
		"loading": SplatLabFinishPages.loading(self)
		"results": SplatUiExtras.results_page(self, results_data)
		_: show_menu()

func _transition_enabled()->bool:
	if fixture_mode or not is_instance_valid(_wipe) or bool(settings.reduce_motion):return false
	# Direct-page screenshots expose the steady layout, just as the browser lab's news=0 fixtures.
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--page"):return false
	return true

func _page_change(previous:String,next:String,swap:Callable,back:bool=false)->void:
	_page_token+=1
	var token:int=_page_token
	var guarded:Callable=func()->void:
		if token==_page_token:swap.call()
	if previous!=next and _transition_enabled():
		if FULL_WIPES.has(previous+">"+next):_run_wipe("full",guarded,-1 if back else 1);return
		guarded.call()
		if LIGHT_PAGES.has(previous) and LIGHT_PAGES.has(next):_run_wipe("light",Callable(),-1 if back else 1)
	else:guarded.call()

func _run_wipe(type:String,swap:Callable=Callable(),direction:int=1)->void:
	var colors:Array[Color]=[SplatUiTheme.ORANGE,SplatUiTheme.BLUE]
	if is_instance_valid(main) and main.get("team_colors") is Array:
		colors[0]=main.team_colors[0];colors[1]=main.team_colors[1]
	_wipe.run(type,direction,colors[0],colors[1],swap)

func clear_page() -> void:
	for child: Node in _margin.get_children():
		_margin.remove_child(child)
		child.queue_free()
	content = SplatUiTheme.vbox(20)
	_margin.add_child(content)
	SplatUiTheme.enter(content)

func header(title: String, subtitle: String = "") -> void:
	var row: HBoxContainer = SplatUiTheme.hbox(20)
	content.add_child(row)
	var back: SplatInkButton = SplatUiTheme.button("‹ BACK", _back, SplatUiTheme.GOLD)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.custom_minimum_size.x = 140
	row.add_child(back)
	var words: VBoxContainer = SplatUiTheme.vbox(2)
	row.add_child(words)
	words.add_child(SplatUiTheme.text(title, 40, true))
	if not subtitle.is_empty():
		words.add_child(SplatUiTheme.text(subtitle, 18, false, SplatUiTheme.MUTED))
	SplatLabCanvas.defer_focus(back)

func _back() -> void:
	if is_instance_valid(_news):_news.close("back");return
	if is_instance_valid(_modal):close_modal();return
	if page=="results" or page=="loading":return
	if page=="lobby":
		var others:Array=(lobby_data.get("players",[]) as Array).filter(func(p:Dictionary)->bool:return str(p.get("id",""))!=str(lobby_data.get("you","")))
		var host_room:bool=str(lobby_data.get("host",""))==str(lobby_data.get("you",""))
		var code:String=str(lobby_data.get("code",""))
		var message:String="You’re the last one here — the room closes when you leave." if others.is_empty() else "You’re the host — %s takes over the room. You can come back with the code %s."%[str(others[0].get("name","Squidkid")),code] if host_room else "You can rejoin any time with the code %s while the room is open."%code
		confirm("LEAVE ROOM?",message,func()->void:online_requested.emit({"action":"leave"});open_page("online"));return
	if page == "pause": resume(); return
	if page == "main": show_title(); return
	if not _history.is_empty():
		var dest: String = _history.pop_back()
		_show_page(dest,true,false)
	else: show_menu()

func show_lobby(data: Dictionary) -> void:
	lobby_data = data.duplicate(true)
	# Lobby refreshes can already be queued when start/go arrives. Keep the live HUD.
	if is_instance_valid(main) and is_instance_valid(main.get("network")) and str(main.network.phase)!="lobby":return
	in_match = false
	_paused = false
	hud.hide()
	hud.clear_world_map()
	hud.touch.reset()
	_menu.show()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	open_page("lobby")

func start_match() -> void:
	_save()
	var payload: Dictionary = options.duplicate(true)
	payload["style"] = profile.duplicate()
	payload["profile"] = profile.duplicate()
	payload["settings"] = settings.duplicate()
	var launch:Callable=func()->void:show_hud();start_requested.emit(payload)
	if _transition_enabled():_run_wipe("full",launch)
	else:launch.call()

func toggle_pause() -> void:
	if not in_match:
		return
	if _paused:
		resume()
		return
	_paused = true
	hud.set_map_open(false)
	hud.touch.reset()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_menu.show()
	_backdrop.hide()
	page = "pause"
	clear_page()
	SplatUiExtras.pause_page(self)
	pause_changed.emit(true)

func resume() -> void:
	_paused = false
	page="";_history.clear()
	_menu.hide()
	_backdrop.show()
	if not hud.touch.visible:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	pause_changed.emit(false)

func show_results(stats: Dictionary) -> void:
	in_match = false
	hud.hide()
	_menu.show()
	_backdrop.hide()
	page = "results"
	results_data = stats.duplicate(true)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	clear_page()
	SplatUiExtras.results_page(self, stats)

func update_match(state: Dictionary) -> void:
	if is_instance_valid(hud):
		hud.update_frame(state)

func get_touch_state() -> Dictionary:
	var state:Dictionary=hud.touch.consume() if is_instance_valid(hud) and in_match and not _paused else {"move": Vector2.ZERO, "look": Vector2.ZERO, "fire": false, "swim": false, "jump": false, "sub": false, "special": false, "map": false}
	if is_instance_valid(hud) and hud.touch.visible and in_match and not _paused:hud.set_map_open(bool(state.map))
	return state

func on_event(kind:String,data:Dictionary)->void:
	if is_instance_valid(hud):hud.on_event(kind,data)
	if is_instance_valid(boss_hud):boss_hud.on_event(kind,data)

func update_combat_reticle(fragment:Dictionary)->void:
	if in_match and is_instance_valid(hud):hud.update_combat_reticle(fragment)

func combat_profile_metrics()->Dictionary:
	return hud.combat_profile_metrics() if is_instance_valid(hud) else {}

func show_intro(match_options:Dictionary,actors:Array)->void:
	if is_instance_valid(hud):hud.show_intro(match_options,actors)

func judge(data:Dictionary)->void:
	var view:=SplatHudJudge.new();view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(view)
	view._layout();view.build(data)
	view.finished.connect(func(winner:int)->void:judge_finished.emit(winner))

func toast(value: String,options:Dictionary={}) -> void:
	if is_instance_valid(_toasts):_toasts.add_message(value,options)

func confirm(title:String,message:String,accepted:Callable,stay_label:String="STAY",leave_label:String="LEAVE")->void:
	if is_instance_valid(_modal):return
	_modal_focus=get_viewport().gui_get_focus_owner()
	_modal=SplatLabCanvas.new();_modal.z_index=50;_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);root.add_child(_modal);_modal._layout();_modal.mouse_filter=Control.MOUSE_FILTER_STOP
	var cv:Control=_modal.canvas
	var shade:Control=SplatLabCanvas.panel(cv,0,0,_modal.width_u,_modal.height_u,Color(.031,.023,.055,.62),0);shade.mouse_filter=Control.MOUSE_FILTER_STOP
	var box:Control=SplatLabCanvas.panel(cv,_modal.width_u*.5-23,_modal.height_u*.5-11,46,22,Color("1f1a2c"),2)
	(box.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(box.material as ShaderMaterial).set_shader_parameter("border",3.0)
	SplatLabCanvas.icon(box,"splat",17.5,-5.5,11,11).modulate=Color("ff3d5e")
	SplatLabCanvas.label(box,title,3,3.0,40,4.1,3.3,true).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var desc:Label=SplatLabCanvas.label(box,message,3,8.1,40,4.7,1.1,false,SplatUiTheme.MUTED);desc.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;desc.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var stay:SplatInkButton=SplatLabCanvas.button(box,stay_label,close_modal,4,15.4,17,4.3,1.7)
	var leave:SplatInkButton=SplatLabCanvas.button(box,leave_label,func()->void:close_modal();accepted.call(),23,15.4,18,4.3,1.7,"","",false,Color("ff3d5e"))
	stay.focus_next=leave.get_path();stay.focus_previous=leave.get_path();leave.focus_next=stay.get_path();leave.focus_previous=stay.get_path();SplatLabCanvas.defer_focus(stay)
	SplatUiTheme.enter(box)

func close_modal()->void:
	if is_instance_valid(_modal):_modal.queue_free()
	_modal=null
	if is_instance_valid(_modal_focus):SplatLabCanvas.defer_focus(_modal_focus)

func save_profile() -> void:
	_save()
	style_changed.emit(profile.duplicate())

func set_setting(key: String, value: Variant) -> void:
	settings[key] = value
	if key == "cameraShake": settings.screenShake = float(value) > 0
	if key == "difficulty": options.difficulty = value
	if key == "matchLength": options.duration = value
	_save()
	_apply_settings()

func _apply_settings() -> void:
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(0.0001, float(settings.master))))
	if is_instance_valid(hud):hud.apply_settings(settings)
	if is_instance_valid(main) and main.has_method("apply_settings"):
		main.call("apply_settings", settings.duplicate())

func _save() -> void:
	if fixture_mode or nonpersistent:return
	var save := ConfigFile.new()
	save.set_value("schema", "version", 1)
	save.set_value("schema","news_seen",news_seen)
	save.set_value("player", "style", profile)
	save.set_value("settings", "values", settings)
	save.set_value("match", "options", options)
	var result: Error = save.save(SAVE_PATH)
	if result != OK:
		push_warning("Splatink settings save failed: %s" % error_string(result))

func _load() -> void:
	if nonpersistent:return
	var save := ConfigFile.new()
	if save.load(SAVE_PATH) != OK:
		return
	_loaded_settings=true
	news_seen=str(save.get_value("schema","news_seen",""))
	for entry: Array in [[profile, "player", "style"], [settings, "settings", "values"], [options, "match", "options"]]:
		var stored: Variant = save.get_value(entry[1], entry[2], {})
		if stored is Dictionary:
			(entry[0] as Dictionary).merge(stored as Dictionary, true)
	if settings.aimAssist is bool: settings.aimAssist = 1.0 if bool(settings.aimAssist) else 0.0
	if settings.cameraShake is bool: settings.cameraShake = 1.0 if bool(settings.cameraShake) else 0.0

func _input(event:InputEvent)->void:
	if is_instance_valid(_wipe) and _wipe.running and _wipe.mode!="light":get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(_modal):
		if event.is_action_pressed("ui_cancel"):close_modal()
		get_viewport().set_input_as_handled();return
	if is_instance_valid(_news):return
	if page == "title" and ((event is InputEventKey and event.pressed) or (event is InputEventJoypadButton and event.pressed)):
		show_menu();get_viewport().set_input_as_handled();return
	if page == "results" and event.is_action_pressed("ui_accept") and is_instance_valid(results_view) and not results_view.done:
		results_view.finish_counts();get_viewport().set_input_as_handled();return
	if event.is_action_pressed("ui_cancel") and not in_match:
		_back()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and _menu.visible:
		if event.keycode == KEY_R and page == "locker": SplatLabExtraPages.shuffle(self); get_viewport().set_input_as_handled()
		if page == "lobby":
			if event.keycode == KEY_C: DisplayServer.clipboard_set(str(lobby_data.get("code","")));toast("COPIED!");get_viewport().set_input_as_handled()
			elif event.keycode == KEY_R:
				var own:bool=str(lobby_data.get("you",""))==str(lobby_data.get("host",""))
				var ready:bool=false
				for player:Dictionary in lobby_data.get("players",[]):
					if str(player.get("id",""))==str(lobby_data.get("you","")):ready=bool(player.get("ready",false))
				online_requested.emit({"action":"start"} if own else {"action":"ready","ready":not ready});get_viewport().set_input_as_handled()
			elif event.keycode in [KEY_Q,KEY_E]:
				var team:int=0
				for player:Dictionary in lobby_data.get("players",[]):
					if str(player.get("id",""))==str(lobby_data.get("you","")):team=int(player.get("team",0))
				online_requested.emit({"action":"team","team":1-team});get_viewport().set_input_as_handled()
			elif event.keycode in [KEY_1,KEY_2,KEY_3,KEY_4]:online_requested.emit({"action":"emote","emote":int(event.keycode-KEY_1)});get_viewport().set_input_as_handled()
		if event.keycode in [KEY_Q, KEY_E] and page in ["locker", "settings"]:
			var direction: int = -1 if event.keycode == KEY_Q else 1
			if page == "locker":locker_tab=clampi(locker_tab+direction,0,3);locker_focus={"key":["preset","hair","eyes","outfit"][locker_tab],"index":0}
			else:settings_tab=clampi(settings_tab+direction,0,3);settings_row=0
			open_page(page)
			get_viewport().set_input_as_handled()
		elif event.keycode in [KEY_Q, KEY_E] and page == "setup":
			options.time_of_day = "dusk" if options.time_of_day == "day" else "day"
			options.timeOfDay = options.time_of_day
			open_page("setup")
			get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_cancel") and in_match:
		if _paused and page != "pause": _back()
		else: toggle_pause()
		get_viewport().set_input_as_handled()
	if event is InputEventKey and not event.echo and in_match and not _paused:
		if event.keycode == KEY_TAB:
			hud.set_map_open(event.pressed);get_viewport().set_input_as_handled()
		elif event.keycode == KEY_M and event.pressed:
			hud.toggle_map();get_viewport().set_input_as_handled()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	_toast_timer = maxf(0, _toast_timer - delta)
	if _toast_timer <= 0 and _toast != null:
		_toast.text = ""
