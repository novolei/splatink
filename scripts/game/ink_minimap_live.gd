class_name InkMinimapLive
extends Control

var map: Node
const EDGE := Color("15121c")

func _alpha(color: Color,value: float) -> Color:
	return Color(color.r,color.g,color.b,value)

func _ring(point: Vector2,radius: float,color: Color,line: float,start: float = 0.0,end: float = TAU) -> void:
	if radius > 0.0 and end > start:
		draw_arc(point,radius,start,end,maxi(24,ceili(radius*1.7)),color,line,true)

func _cross(point: Vector2,radius: float,color: Color,line: float) -> void:
	draw_line(point-Vector2.ONE*radius,point+Vector2.ONE*radius,color,line,true)
	draw_line(point+Vector2(radius,-radius),point+Vector2(-radius,radius),color,line,true)

func _cloud(point: Vector2,radius: float,color: Color) -> void:
	# Fill all three lobes after their outline, as the original continuous canvas path.
	var centers: Array[Vector2] = [point+Vector2(-.55,.1)*radius,point+Vector2(.55,.1)*radius,point+Vector2(0,-.25)*radius]
	var radii: Array[float] = [.55*radius,.5*radius,.7*radius]
	for i in 3:
		draw_circle(centers[i],radii[i]+1.5,EDGE)
	for i in 3:
		draw_circle(centers[i],radii[i],color)
	draw_circle(point+Vector2(-.15,-.45)*radius,.25*radius,Color(1,1,1,.6))

func _dashed_ring(point: Vector2,radius: float,color: Color,clock: float) -> void:
	var angle: float = 4.0/maxf(radius,1.0)
	var offset: float = fposmod(-clock*12.0,8.0)/maxf(radius,1.0)
	var cursor: float = -offset
	while cursor < TAU:
		_ring(point,radius,color,2.0,maxf(0.0,cursor),minf(TAU,cursor+angle))
		cursor += angle*2.0

func _draw() -> void:
	if not is_instance_valid(map) or not bool(map.get("_built")):
		return
	var stage: Node = map.get("stage")
	if not is_instance_valid(stage):
		return
	var colors: Array = map.get("_colors")
	var layout: Dictionary = stage.get("layout")
	var pads: Array = layout.get("spawnPads",[])
	var scale_m: float = float(map.PX_PER_M)
	var clock: float = float(map.get("time"))
	for team in mini(2,pads.size()):
		var p: Array = pads[team]
		var point: Vector2 = map.call("to_canvas",float(p[0]),float(p[2]))
		var r: float = float(layout.get("spawnBarrier",4.0))*scale_m*.62
		var color: Color = colors[team]
		draw_circle(point,r,_alpha(color,.28))
		_ring(point,r,EDGE,3.0)
		_ring(point,r,Color.WHITE,1.6)
		draw_circle(point,r*.45,color)
		_ring(point,r*.45,EDGE,2.5)
	for effect: Dictionary in map.get("effects"):
		var pos: Vector3 = effect.pos
		var point: Vector2 = map.call("to_canvas",pos.x,pos.z)
		var k: float = float(effect.t)/float(effect.life)
		var color: Color = colors[int(effect.team)]
		match str(effect.kind):
			"slam","boom":
				var r: float = float(effect.r)*scale_m*(.3+.7*(1.0-pow(1.0-k,3)))
				draw_circle(point,r,_alpha(color,(1.0-k)*.45))
				_ring(point,r,Color(1,1,1,1.0-k),4.0 if effect.kind == "slam" else 3.0)
			"jump":
				var pulse: float = .5+.5*sin(clock*10.0)
				var r: float = scale_m*(1.1+.35*pulse)
				_ring(point,r+1.0,EDGE,3.0)
				_ring(point,r,color,2.0)
				for direction: Vector2 in [Vector2.LEFT,Vector2.RIGHT,Vector2.UP,Vector2.DOWN]:
					draw_line(point+direction*r*.5,point+direction*r*1.5,color,2.0,true)
			"spawn":
				_ring(point,scale_m*(2.0+5.0*k),Color(1,1,1,1.0-k),3.0)
			"splat":
				var opacity: float = maxf(0.0,k/.15 if k < .15 else 1.0-(k-.15)/.85)
				_cross(point,scale_m*.9,_alpha(EDGE,opacity),4.0)
				_cross(point,scale_m*.9,_alpha(color,opacity),2.2)
	var game: Node = map.get("game")
	if not is_instance_valid(game):
		return
	var manager = game.get("projectiles")
	if not is_instance_valid(manager):
		return
	for storm: Dictionary in manager.get("storms"):
		var pos: Vector3 = storm.get("pos",Vector3.ZERO)
		var point: Vector2 = map.call("to_canvas",pos.x,pos.z)
		var color: Color = colors[int(storm.get("team",0))]
		var r: float = 3.4*scale_m
		var left: float = clampf(float(storm.get("life",6.5))/6.5,0.0,1.0)
		draw_circle(point,r,_alpha(color,.22))
		_dashed_ring(point,r,color,clock)
		_ring(point,r+3.0,Color.WHITE,3.0,-PI*.5,-PI*.5+left*TAU)
		_cloud(point-Vector2(0,1),scale_m*1.1,color)
	for bomb: Dictionary in manager.get("bullets"):
		var kind: String = str(bomb.get("kind"))
		if kind not in ["bomb","storm_pod"]:
			continue
		var pos: Vector3 = bomb.pos
		var point: Vector2 = map.call("to_canvas",pos.x,pos.z)
		var color: Color = colors[int(bomb.team)]
		if kind == "storm_pod":
			_cloud(point,scale_m*.8,color)
			continue
		var fuse: float = float(bomb.get("fuse",-1.0))
		if fuse >= 0.0:
			var k: float = 1.0-fuse/.95
			var blink: float = .5+.5*sin(float(bomb.age)*(10.0+k*30.0))
			draw_circle(point,3.1*scale_m*(.5+.5*k),_alpha(color,.35+blink*.4))
		var r: float = scale_m*.62
		draw_circle(point,r+1.5,EDGE)
		draw_circle(point,r,color)
		draw_circle(point-Vector2.ONE*r*.3,r*.3,Color(1,1,1,.75))
