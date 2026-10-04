class_name SplatOnlinePage
extends RefCounted

static func portal(host: InkUI) -> void:
	host.header("ONLINE", "Fresh friends, same turf · eight squidkids, one room")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.content.add_child(scroll)
	var form: VBoxContainer = SplatUiTheme.vbox(16)
	form.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(form)
	var kind: OptionButton = SplatUiPages.choice(form, "CONNECTION", ["ROOM CODE · INTERNET", "LOCAL NETWORK · ADDRESS"])
	var connection: PanelContainer = SplatUiTheme.panel()
	form.add_child(connection)
	var fields: VBoxContainer = SplatUiTheme.vbox(12)
	connection.add_child(fields)
	var code := LineEdit.new()
	code.placeholder_text = "ENTER FIVE-CHARACTER ROOM CODE"
	code.max_length = 5
	code.custom_minimum_size.y = 52
	fields.add_child(code)
	var address := LineEdit.new()
	address.placeholder_text = "HOST ADDRESS · 192.168.1.20"
	address.text = "127.0.0.1"
	address.custom_minimum_size.y = 52
	fields.add_child(address)
	var port := SpinBox.new()
	port.min_value = 1024
	port.max_value = 65535
	port.value = 27840
	port.custom_minimum_size.y = 48
	fields.add_child(port)
	var note: Label = SplatUiTheme.body("Create a room and share its five-character code. Ready up together before the host starts the match.", 20)
	fields.add_child(note)
	address.hide()
	port.hide()
	kind.item_selected.connect(func(index: int) -> void:
		code.visible = index == 0
		address.visible = index == 1
		port.visible = index == 1
		note.text = "Create a room and share its five-character code. Ready up together before the host starts the match." if index == 0 else "Join the host's address on the same local network. The room uses UDP port %d." % int(port.value))
	var maps: Array = SplatUiTheme.catalog().maps
	var names: Array[String] = []
	for stage: Dictionary in maps: names.append(str(stage.name))
	var selected: int = 0
	for index: int in maps.size():
		if str(maps[index].id) == str(host.options.map): selected = index
	var stage_picker: OptionButton = SplatUiPages.choice(form, "HOST'S STAGE", names, selected)
	var period: OptionButton = SplatUiPages.choice(form, "TIME OF DAY", ["DAY", "DUSK"], 1 if str(host.options.time_of_day) == "dusk" else 0)
	var mode: OptionButton = SplatUiPages.choice(form, "RULES", ["TURF WAR · 4 VS 4", "BOSS BATTLE · SQUAD VS HULLBREAKER"])
	var bots := CheckButton.new()
	bots.text = "FILL OPEN SLOTS WITH BOTS"
	bots.button_pressed = true
	form.add_child(bots)
	stage_picker.item_selected.connect(func(index: int) -> void:
		var cargo: bool = str(maps[index].id) == "cargo"
		bots.disabled = cargo
		if cargo: bots.button_pressed = false
		mode.disabled = cargo
		if cargo: mode.select(0))
	var buttons: HBoxContainer = SplatUiTheme.hbox(24)
	form.add_child(buttons)
	var payload: Callable = func(action: String) -> Dictionary:
		var match_options: Dictionary = host.options.duplicate(true)
		match_options.map = str(maps[stage_picker.selected].id)
		match_options.stage = match_options.map
		match_options.time_of_day = "dusk" if period.selected == 1 else "day"
		match_options.time = match_options.time_of_day
		match_options.mode = "boss" if mode.selected == 1 else "turf"
		match_options.bots = bots.button_pressed and match_options.map != "cargo"
		return {"action": action, "transport": "relay" if kind.selected == 0 else "enet", "code": code.text.strip_edges().to_upper(), "address": address.text.strip_edges(), "port": int(port.value), "match": match_options, "name": host.profile.name, "style": host.profile.duplicate(), "weapon": str(host.options.weapon)}
	buttons.add_child(SplatUiTheme.button("CREATE ROOM", func() -> void: host.online_requested.emit(payload.call("host")), SplatUiTheme.ORANGE, true))
	buttons.add_child(SplatUiTheme.button("JOIN ROOM", func() -> void: host.online_requested.emit(payload.call("join")), SplatUiTheme.BLUE, true))
	form.add_child(SplatUiTheme.body("Cargo Terminal needs human players on both teams; it does not use bots or Boss Battle.", 18))

static func lobby(host: InkUI, data: Dictionary) -> void:
	var own_id: String = str(data.get("you", ""))
	var is_host: bool = own_id == str(data.get("host", ""))
	var code: String = str(data.get("code", ""))
	host.header("ROOM " + code, "HOST'S ROOM" if is_host else "READY UP WITH YOUR CREW")
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	host.content.add_child(scroll)
	var body: VBoxContainer = SplatUiTheme.vbox(18)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(body)
	var room: Dictionary = data.duplicate(true)
	var summary: Label = SplatUiTheme.text("%s · %s · %s · %ds" % [str(data.get("map", "tidewater")).to_upper(), str(data.get("time", "day")).to_upper(), "BOSS BATTLE" if str(data.get("mode", "turf")) == "boss" else "TURF WAR", int(data.get("duration", 180))], 23, true, SplatUiTheme.GOLD)
	body.add_child(summary)
	if str(data.get("transport", "relay")) == "enet":
		body.add_child(SplatUiTheme.body("LOCAL NETWORK · host address + UDP 27840", 18))
	else:
		body.add_child(SplatUiTheme.body("Share room code %s with your friends." % code, 18))
	if is_host: _host_settings(host, body, room)
	var columns: HBoxContainer = SplatUiTheme.hbox(24)
	body.add_child(columns)
	var ready: bool = false
	for team: int in 2:
		var panel: PanelContainer = SplatUiTheme.panel(SplatUiTheme.PANEL, 16)
		panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		columns.add_child(panel)
		var roster: VBoxContainer = SplatUiTheme.vbox(12)
		panel.add_child(roster)
		roster.add_child(SplatUiTheme.text("YOUR SQUAD" if str(data.get("mode", "turf")) == "boss" else ("ORANGE CREW" if team == 0 else "BLUE CREW"), 26, true, SplatUiTheme.ORANGE if team == 0 else SplatUiTheme.BLUE))
		var filled: int = 0
		for player: Dictionary in data.get("players", []):
			if int(player.get("team", 0)) != team: continue
			filled += 1
			var row: HBoxContainer = SplatUiTheme.hbox(8)
			roster.add_child(row)
			var mine: bool = str(player.get("id", "")) == own_id
			var name: Label = SplatUiTheme.text(str(player.get("name", "Fresh Kid")) + (" · YOU" if mine else "") + (" ★" if bool(player.get("host", false)) else ""), 21, true)
			name.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			row.add_child(name)
			var mark: bool = bool(player.get("ready", false))
			if mine: ready = mark
			row.add_child(SplatUiTheme.text("READY" if mark else "WAITING", 16, true, SplatUiTheme.MINT if mark else SplatUiTheme.MUTED))
			roster.add_child(SplatUiTheme.text(str(player.get("weapon", "shooter")).to_upper(), 15, false, SplatUiTheme.MUTED))
		for vacant: int in maxi(0, 4 - filled):
			roster.add_child(SplatUiTheme.text("BOT SLOT" if bool(data.get("bots", true)) else "OPEN SLOT", 18, false, SplatUiTheme.MUTED))
	var actions: HBoxContainer = SplatUiTheme.hbox(20)
	host.content.add_child(actions)
	actions.add_child(SplatUiTheme.button("NOT READY" if ready else "READY!", func() -> void: host.online_requested.emit({"action": "ready", "ready": not ready}), SplatUiTheme.MINT, true))
	actions.add_child(SplatUiTheme.button("SWITCH TEAM", func() -> void:
		for player: Dictionary in data.get("players", []):
			if str(player.get("id", "")) == own_id: host.online_requested.emit({"action": "team", "team": 1 - int(player.get("team", 0))}), SplatUiTheme.BLUE))
	if is_host:
		actions.add_child(SplatUiTheme.button("START MATCH", func() -> void: host.online_requested.emit({"action": "start"}), SplatUiTheme.ORANGE, true))
	actions.add_child(SplatUiTheme.button("LEAVE ROOM", func() -> void:
		host.online_requested.emit({"action": "leave"})
		host.open_page("online"), Color("ff3d5e")))

static func _host_settings(host: InkUI, parent: VBoxContainer, data: Dictionary) -> void:
	var row: HBoxContainer = SplatUiTheme.hbox(16)
	parent.add_child(row)
	var maps: Array = SplatUiTheme.catalog().maps
	var picker := OptionButton.new()
	for map: Dictionary in maps:
		picker.add_item(str(map.name))
		if str(map.id) == str(data.get("map", "")): picker.select(picker.item_count - 1)
	row.add_child(picker)
	picker.item_selected.connect(func(index: int) -> void:
		data.map = str(maps[index].id)
		data.stage = data.map
		if data.map == "cargo": data.bots = false; data.mode = "turf"
		host.online_requested.emit({"action": "options", "match": data}))
	var time := OptionButton.new()
	time.add_item("DAY")
	time.add_item("DUSK")
	time.select(1 if str(data.get("time", "day")) == "dusk" else 0)
	row.add_child(time)
	time.item_selected.connect(func(index: int) -> void:
		data.time = "dusk" if index == 1 else "day"
		data.time_of_day = data.time
		host.online_requested.emit({"action": "options", "match": data}))
	var fill := CheckButton.new()
	fill.text = "BOTS"
	fill.button_pressed = bool(data.get("bots", true))
	fill.disabled = str(data.get("map", "")) == "cargo"
	row.add_child(fill)
	fill.toggled.connect(func(value: bool) -> void:
		data.bots = value
		host.online_requested.emit({"action": "options", "match": data}))
