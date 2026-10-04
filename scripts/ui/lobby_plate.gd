class_name SplatLobbyPlate
extends Control
var lobby:Node
var slot:int=0
var canvas:SplatLabCanvas
var previous:Vector2=Vector2(-10000,-10000)
func _ready()->void:mouse_filter=Control.MOUSE_FILTER_IGNORE
func _process(dt:float)->void:
	if not is_instance_valid(lobby) or not lobby.has_method("project_player") or not canvas:return
	visible=bool(lobby.call("player_projection_visible",slot))
	if not visible:return
	var point:Vector2=lobby.call("project_player",slot)
	var view_size:Vector2=lobby.get_viewport().get_visible_rect().size
	var display_size:Vector2=canvas.size
	point*=display_size/Vector2(maxf(1,view_size.x),maxf(1,view_size.y))
	point=(point-canvas.canvas.position)/canvas.canvas.scale
	point-=Vector2(size.x*.5,size.y+1.3*12.8)
	previous=point if previous.x< -9999 else previous.lerp(point,minf(1,dt*12))
	position=previous
