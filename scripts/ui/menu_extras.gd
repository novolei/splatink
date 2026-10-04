class_name SplatUiExtras
extends RefCounted

static func locker(host: InkUI) -> void:
	SplatLabExtraPages.locker(host)

static func settings_page(host: InkUI) -> void:
	SplatLabExtraPages.settings(host)

static func _setting_row(host: InkUI, parent: VBoxContainer, spec: Array) -> void:
	var key: String = str(spec[0])
	var panel: PanelContainer = SplatUiTheme.panel(SplatUiTheme.PANEL, 18)
	parent.add_child(panel)
	var row: HBoxContainer = SplatUiTheme.hbox(30)
	panel.add_child(row)
	var label: Label = SplatUiTheme.text(str(spec[1]), 23)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	if spec.size() == 5:
		var slider := HSlider.new()
		slider.min_value = float(spec[2])
		slider.max_value = float(spec[3])
		slider.step = float(spec[4])
		slider.value = float(host.settings.get(key, 1.0))
		slider.custom_minimum_size = Vector2(220, 48)
		row.add_child(slider)
		var value: Label = SplatUiTheme.text("%.2f" % slider.value, 22, true, SplatUiTheme.GOLD)
		value.custom_minimum_size.x = 80
		row.add_child(value)
		slider.value_changed.connect(func(amount: float) -> void:
			host.set_setting(key, amount)
			value.text = "%.2f" % amount)
	elif spec.size() == 3:
		var values: Array = spec[2]
		var picker := OptionButton.new()
		picker.custom_minimum_size = Vector2(230, 48)
		for value: String in values:
			picker.add_item(value.to_upper())
		picker.select(maxi(0, values.find(host.settings.get(key, "high"))))
		picker.item_selected.connect(func(index: int) -> void: host.set_setting(key, values[index]))
		row.add_child(picker)
	else:
		var toggle := CheckButton.new()
		toggle.text = "ON"
		toggle.button_pressed = bool(host.settings.get(key, true))
		toggle.custom_minimum_size = Vector2(130, 48)
		toggle.toggled.connect(func(value: bool) -> void: host.set_setting(key, value))
		row.add_child(toggle)

static func help_page(host: InkUI) -> void:
	SplatLabExtraPages.howto(host)

static func online_page(host: InkUI) -> void:
	SplatLabOnlinePages.portal(host)

static func pause_page(host: InkUI) -> void:
	SplatLabExtraPages.pause(host)

static func results_page(host: InkUI, stats: Dictionary) -> void:
	SplatLabFinishPages.results(host, stats)

static func credits_page(host: InkUI) -> void:
	SplatLabFinishPages.credits(host)
