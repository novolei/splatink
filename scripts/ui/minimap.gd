class_name SplatMiniMap
extends Control
signal jump_requested(index: int)

var data: Dictionary = {}
var expanded: bool = false
var _beacons: Array[Dictionary] = []
var _frame_style:StyleBoxFlat
var _inner:Rect2
var _image:TextureRect
var _icons:Dictionary={}
var _key_style:StyleBoxFlat

func _ready() -> void:
	custom_minimum_size = Vector2.ZERO
	mouse_filter = Control.MOUSE_FILTER_STOP
	gui_input.connect(_clicked)
	_frame_style=StyleBoxFlat.new()
	_frame_style.bg_color=Color("22314a");_frame_style.border_color=Color.WHITE
	_frame_style.set_border_width_all(3);_frame_style.set_corner_radius_all(18)
	_image=TextureRect.new();_image.expand_mode=TextureRect.EXPAND_IGNORE_SIZE;_image.stretch_mode=TextureRect.STRETCH_SCALE;_image.mouse_filter=Control.MOUSE_FILTER_IGNORE;_image.show_behind_parent=true;add_child(_image)
	var mat:=ShaderMaterial.new();mat.shader=preload("res://assets/ui/lab_map_clip.gdshader");_image.material=mat
	_key_style=StyleBoxFlat.new();_key_style.bg_color=Color.WHITE;_key_style.border_color=SplatUiTheme.INK;_key_style.set_border_width_all(2);_key_style.set_corner_radius_all(5)

func update_map(value: Dictionary) -> void:
	data = value
	queue_redraw()

func clear_map()->void:
	data={};_beacons.clear()
	if _image:_image.texture=null
	queue_redraw()

func _draw() -> void:
	var inner := Rect2(Vector2.ZERO, size)
	var texture: Texture2D = data.get("texture") as Texture2D
	if texture != null:
		var source_size:Vector2=data.get("texture_size",data.get("size",Vector2(350,616)))
		if not texture is ViewportTexture and not data.has("texture_size"):source_size=texture.get_size()
		var factor:float=minf(inner.size.x/maxf(1,source_size.x),inner.size.y/maxf(1,source_size.y))
		var drawn:Vector2=source_size*factor
		inner=Rect2(inner.get_center()-drawn*.5,drawn)
		_image.texture=texture;_image.position=inner.position;_image.size=inner.size;(_image.material as ShaderMaterial).set_shader_parameter("panel_size",inner.size)
	_frame_style.bg_color=Color.TRANSPARENT
	draw_style_box(_frame_style,Rect2(Vector2.ZERO,size))
	_inner=inner
	var cells: Variant = data.get("cells", [])
	if cells is Array:
		var grid: int = int(data.get("grid", 32))
		for index: int in mini((cells as Array).size(), grid * grid):
			var owner: int = int(cells[index])
			if owner < 0:
				continue
			var color: Color = SplatUiTheme.ORANGE if owner == 0 else SplatUiTheme.BLUE
			draw_rect(Rect2(inner.position + Vector2(index % grid, index / grid) * inner.size / grid, inner.size / grid + Vector2.ONE), color)
	_beacons.clear()
	var players: Array = data.get("players", []) as Array
	var extent: float = maxf(1.0, float(data.get("extent", 32)))
	var local_team: int = int(data.get("local_team", 0))
	var bounds: Dictionary = data.get("bounds", {}) as Dictionary
	var ally_index: int = 0
	for index: int in players.size():
		var player: Dictionary = players[index] as Dictionary
		var team: int = int(player.get("team", 0))
		if team != local_team and not bool(player.get("visible", false)):
			continue
		var position_data: Variant = player.get("position", Vector2(float(player.get("x", 0)), float(player.get("z", 0))))
		var point := Vector2.ZERO
		if position_data is Vector3:
			point = Vector2(position_data.x, position_data.z)
		elif position_data is Vector2:
			point = position_data
		var coordinate: Vector2 = point / extent + Vector2.ONE * 0.5
		if bounds.has("minX") and bounds.has("minZ"):
			coordinate = Vector2((float(bounds.maxX)-point.x) / maxf(1, float(bounds.maxX) - float(bounds.minX)), (float(bounds.maxZ)-point.y) / maxf(1, float(bounds.maxZ) - float(bounds.minZ)))
			if local_team==1:coordinate=Vector2.ONE-coordinate
		if player.get("uv") is Vector2:coordinate=player.uv
		var location: Vector2 = inner.position + coordinate.clamp(Vector2.ZERO, Vector2.ONE) * inner.size
		var color: Color = data.get("local_color", SplatUiTheme.ORANGE) if team == local_team else data.get("enemy_color", SplatUiTheme.BLUE)
		if team==local_team and not bool(player.get("local",player.get("isSelf",false))):
			ally_index+=1;_beacons.append({"point":location,"index":ally_index,"name":player.get("name","Teammate %d"%ally_index),"weapon":player.get("weapon","shooter"),"ok":bool(player.get("alive",true)) and not bool(player.get("superjump_state",false)),"respawn":player.get("respawn",0),"home":false})
		if not bool(player.get("alive",true)):continue
		draw_circle(location, 7, SplatUiTheme.INK)
		draw_circle(location, 4, color)
		if bool(player.get("local", false)):
			draw_arc(location, 10, 0, TAU, 24, Color.WHITE, 2, true)
			var yaw:float=float(player.get("aim_yaw",player.get("yaw",0)))
			var forward:Vector2=Vector2(sin(yaw),cos(yaw))*(1 if local_team==0 else -1)
			var side:Vector2=Vector2(-forward.y,forward.x)
			draw_colored_polygon(PackedVector2Array([location+forward*9,location-forward*6+side*5,location-forward*3,location-forward*6-side*5]),Color.WHITE)
	if data.get("beacons") is Array and not (data.beacons as Array).is_empty():
		_beacons.clear()
		for index:int in mini(4,data.beacons.size()):
			var source:Dictionary=data.beacons[index];var beacon:Dictionary=source.duplicate();beacon.point=inner.position+Vector2(float(source.x),float(source.y))*inner.size;beacon.index=index+1;_beacons.append(beacon)
	elif data.get("base_uv") is Vector2:
		_beacons.append({"point":inner.position+data.base_uv*inner.size,"index":4,"name":"Base","home":true,"ok":true})
	if expanded:_draw_beacons()

func _draw_beacons()->void:
	var color:Color=data.get("local_color",SplatUiTheme.ORANGE)
	for beacon:Dictionary in _beacons:
		var point:Vector2=beacon.point;var home:bool=bool(beacon.get("home",false));var radius:float=21.76
		draw_circle(point+Vector2(0,4),radius+5.5,Color(0,0,0,.35));draw_circle(point,radius+5.5,SplatUiTheme.INK);draw_circle(point,radius+3,Color.WHITE);draw_circle(point,radius,SplatUiTheme.INK if home else color if bool(beacon.get("ok",true)) else Color("5a5468"))
		var path:String="res://assets/ui/source/special_slam.svg" if home else "res://assets/ui/source/weaponw_%s.svg"%str(beacon.get("weapon","shooter"))
		if not _icons.has(path):_icons[path]=load(path) as Texture2D
		var texture:Texture2D=_icons[path]
		if texture:draw_texture_rect(texture,Rect2(point-Vector2.ONE*radius*.74,Vector2.ONE*radius*1.48),false,color if home else Color.WHITE)
		var key:Rect2=Rect2(point+Vector2(radius*.44,-radius*1.56),Vector2(21,19));draw_style_box(_key_style,key)
		draw_string(preload("res://assets/fonts/ink_body_900_font.tres"),key.position+Vector2(6.0,14.0),str(beacon.index),HORIZONTAL_ALIGNMENT_LEFT,-1,12,SplatUiTheme.INK)

func _clicked(event: InputEvent) -> void:
	if not expanded:return
	var mouse := event as InputEventMouseButton
	if mouse == null or not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return
	for beacon: Dictionary in _beacons:
		if mouse.position.distance_to(beacon.point as Vector2) < 28 and bool(beacon.get("ok",true)):
			jump_requested.emit(int(beacon.index))
			return
