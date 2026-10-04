class_name SplatUiPages
extends RefCounted

static func main_menu(host: InkUI) -> void:
	SplatLabScreens.main(host)

static func mode_select(host: InkUI) -> void:
	SplatLabPlayPages.mode(host)

static func setup_match(host: InkUI) -> void:
	SplatLabPlayPages.setup(host)

static func loadout(host: InkUI) -> void:
	SplatLabPlayPages.loadout(host)

static func choice(parent: Node, title: String, names: Array[String], selected: int = 0) -> OptionButton:
	var column: VBoxContainer = SplatUiTheme.vbox(5)
	parent.add_child(column)
	column.add_child(SplatUiTheme.text(title, 17, true, SplatUiTheme.MUTED))
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(180, 48)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for value: String in names:
		option.add_item(value)
	option.select(clampi(selected, 0, maxi(names.size() - 1, 0)))
	column.add_child(option)
	return option

static func stage_texture(id: String, time: String) -> Texture2D:
	var path: String = "res://assets/ui/stages/%s-%s.webp" % [id, time]
	return load(path) as Texture2D if ResourceLoader.exists(path) else null

static func stage_image(id: String, time: String) -> TextureRect:
	var image := TextureRect.new()
	image.texture = stage_texture(id, time)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	image.custom_minimum_size = Vector2(220, 180)
	image.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image

static func stage_card(id: String, time: String) -> PanelContainer:
	var panel: PanelContainer = SplatUiTheme.panel(SplatUiTheme.PANEL, 10)
	var column: VBoxContainer = SplatUiTheme.vbox(8)
	panel.add_child(column)
	var image: TextureRect = stage_image(id, time)
	image.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(image)
	for stage: Dictionary in SplatUiTheme.catalog().maps:
		if stage.id == id:
			column.add_child(SplatUiTheme.text(str(stage.name), 26, true))
			column.add_child(SplatUiTheme.body(str(stage.blurb), 17))
	return panel
