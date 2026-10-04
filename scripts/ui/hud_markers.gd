class_name SplatHudMarkers
extends Control
## Source hud.js _updMarkers: pooled ally tags, ready pulse and offscreen direction.
const C=preload("res://scripts/ui/lab_canvas.gd")
var hud:SplatMatchHud
var game:Node
var frame:Dictionary={}
var rows:Array[Dictionary]=[]
var clock:float=0

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	for index:int in 8:
		var group:=Control.new();group.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(group);group.hide()
		var tag:Control=C.panel(group,0,0,10,2.4,SplatUiTheme.ORANGE,1.2)
		(tag.material as ShaderMaterial).set_shader_parameter("border_color",SplatUiTheme.INK);(tag.material as ShaderMaterial).set_shader_parameter("border",2.0)
		var weapon:TextureRect=C.icon(tag,"weaponw_shooter",.4,.28,1.9,1.4)
		var name:Label=C.label(tag,"",2.6,.1,7,2.1,.85,false,SplatUiTheme.INK);name.add_theme_font_override("font",preload("res://assets/fonts/ink_body_800_font.tres"))
		var pointer:TextureRect=C.icon(tag,"source_pointer",4.5,2.23,1,.6)
		var arrow:Control=C.panel(group,-1.17,-1.17,2.34,2.34,SplatUiTheme.ORANGE,1.17);arrow.hide();(arrow.material as ShaderMaterial).set_shader_parameter("border_color",SplatUiTheme.INK);(arrow.material as ShaderMaterial).set_shader_parameter("border",2.0)
		arrow.pivot_offset=Vector2(15.0,15.0)
		var direction:TextureRect=C.icon(arrow,"marker_arrow",27.0/12.8,8.0/12.8,11.0/12.8,15.0/12.8)
		rows.append({"group":group,"tag":tag,"weapon":weapon,"name":name,"pointer":pointer,"arrow":arrow,"direction":direction,"last_name":"","last_weapon":""})

func configure(owner:SplatMatchHud,controller:Node)->void:
	hud=owner;game=controller

func update_frame(value:Dictionary)->void:
	frame=value

func _process(dt:float)->void:
	clock+=dt
	if hud==null:return
	visible=hud.is_visible_in_tree() and hud.is_chrome_visible() and not hud._map_open and not hud._diorama.on and float(frame.get("respawn",0))<=0
	if not visible:return
	var markers:Array=frame.get("markers",[]) as Array
	if not frame.has("markers"):markers=_project()
	for index:int in rows.size():
		var row:Dictionary=rows[index];var group:Control=row.group
		group.visible=index<markers.size()
		if not group.visible:continue
		var marker:Dictionary=markers[index];var on:bool=bool(marker.get("onScreen",true));var far:float=clampf((float(marker.get("dist",0))-14)/20,0,1)
		group.position=Vector2(float(marker.get("x",0)),float(marker.get("y",0)))/hud._view.canvas.scale
		group.modulate.a=1-far*.45
		var color:Color=marker.get("color",frame.get("team_color",SplatUiTheme.ORANGE)) if marker.get("color",frame.get("team_color",SplatUiTheme.ORANGE)) is Color else Color(str(marker.get("color","#ff8a14")))
		var text:String=str(marker.get("name","Squidkid"));var weapon:String=str(marker.get("weapon","shooter"));var ready:bool=bool(marker.get("ready",false))
		for player:Dictionary in frame.get("roster",[]):
			if str(player.get("name",""))==text:weapon=str(player.get("weapon",weapon));ready=bool(player.get("specialReady",float(player.get("special",0))>=.999));break
		var name:Label=row.name;name.text=text
		var font_px:int=11 if on else 10
		var icon_px:Vector2=Vector2(1.9,1.4)*float(font_px)
		var pads:Vector4=Vector4(5,3,9,4) if on else Vector4(3,2,6,3)
		var text_px:float=name.get_theme_font("font").get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,font_px).x
		var width:float=(pads.x+icon_px.x+4.0+text_px+pads.z)/12.8
		var height:float=(icon_px.y+pads.y+pads.w)/12.8
		var tag:Control=row.tag;C.at(tag,-width*.5,-9.0/12.8-height if on else 20.0/12.8,width,height);tag.pivot_offset=Vector2(tag.size.x*.5,tag.size.y);tag.scale=Vector2.ONE*(1-far*.18);tag.modulate.a=1.0 if on else .9
		var material:ShaderMaterial=tag.material;material.set_shader_parameter("panel_size",tag.size);material.set_shader_parameter("top_color",color);material.set_shader_parameter("bottom_color",color);material.set_shader_parameter("border_color",Color.WHITE if ready and sin(clock*TAU)>0 else SplatUiTheme.INK)
		C.at(name,(pads.x+icon_px.x+4.0)/12.8,pads.y/12.8,text_px/12.8+.1,icon_px.y/12.8);name.add_theme_font_size_override("font_size",font_px)
		var icon:TextureRect=row.weapon
		C.at(icon,pads.x/12.8,pads.y/12.8,icon_px.x/12.8,icon_px.y/12.8)
		if row.last_weapon!=weapon:icon.texture=load("res://assets/ui/source/weaponw_%s.svg"%weapon);row.last_weapon=weapon
		var pointer:TextureRect=row.pointer;pointer.visible=on;C.at(pointer,width*.5-5.0/12.8,height,10.0/12.8,6.0/12.8);pointer.self_modulate=color
		var arrow:Control=row.arrow;arrow.visible=not on;arrow.rotation=float(marker.get("angle",0))
		(arrow.material as ShaderMaterial).set_shader_parameter("top_color",color);(arrow.material as ShaderMaterial).set_shader_parameter("bottom_color",color)
		(row.direction as TextureRect).self_modulate=color

func _project()->Array:
	var output:Array=[]
	if not is_instance_valid(game) or game.get("local_player")==null or game.get("camera")==null:return output
	var local:Node3D=game.local_player;var camera:Camera3D=game.camera;var view:Vector2=get_viewport().get_visible_rect().size
	for actor:Node in game.get("actors"):
		if actor==local or not bool(actor.get("alive")) or int(actor.get("team_id"))!=int(local.get("team_id")):continue
		var position:Vector3=actor.call("visual_position") if actor.has_method("visual_position") else (actor as Node3D).global_position
		var avatar:Node=actor.get("avatar")
		if str(actor.get("form"))!="squid" and is_instance_valid(avatar) and avatar.has_method("get_head_position"):
			position=avatar.call("get_head_position") as Vector3;position.y+=.45
		else:position.y+=1.0 if str(actor.get("form"))=="squid" else 1.9
		var point:Vector2=camera.unproject_position(position);var on:bool=not camera.is_position_behind(position) and Rect2(Vector2(20,20),view-Vector2(40,40)).has_point(point)
		var angle:float=0
		if not on:
			var delta:Vector2=point-view*.5
			if camera.is_position_behind(position):delta=-delta
			angle=delta.angle();var bounds:Vector2=view*.5-Vector2(40,40);var factor:float=minf(bounds.x/maxf(.001,absf(delta.x)),bounds.y/maxf(.001,absf(delta.y)));point=view*.5+delta*factor
		output.append({"x":point.x,"y":point.y,"name":str(actor.get("display_name")),"weapon":str(actor.get("weapon_id")),"color":frame.get("team_color",SplatUiTheme.ORANGE),"onScreen":on,"angle":angle,"dist":local.global_position.distance_to((actor as Node3D).global_position)})
	return output
