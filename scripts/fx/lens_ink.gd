class_name InkLens
extends Node

const MAX_PARTS: int = 220
var parts: Array[Dictionary] = []
var _pool: Array[Dictionary] = []
var target: SubViewport
var mesh: MultiMeshInstance2D
var scale_factor: float = 1.0 / 3.0
var aspect: float = 16.0 / 9.0
var _had_parts: bool = false

func initialize() -> void:
	target = SubViewport.new()
	target.disable_3d = true
	target.use_hdr_2d = true
	target.transparent_bg = true
	target.size = Vector2i(64, 36)
	target.render_target_clear_mode = SubViewport.CLEAR_MODE_ALWAYS
	target.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(target)
	mesh = MultiMeshInstance2D.new()
	target.add_child(mesh)
	mesh.multimesh = MultiMesh.new()
	mesh.multimesh.transform_format = MultiMesh.TRANSFORM_2D
	mesh.multimesh.use_colors = true
	var quad := QuadMesh.new()
	quad.size = Vector2(2, 2)
	mesh.multimesh.mesh = quad
	mesh.multimesh.instance_count = MAX_PARTS
	mesh.multimesh.visible_instance_count = 0
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://assets/shaders/fx_lens.gdshader")
	mesh.material = mat

func resize(size: Vector2) -> void:
	aspect = size.x / maxf(1, size.y)
	var desired := Vector2i(maxi(64, roundi(size.x * scale_factor)), maxi(36, roundi(size.y * scale_factor)))
	if desired != target.size:
		target.size = desired
		target.render_target_update_mode = SubViewport.UPDATE_ONCE

func _new() -> Dictionary:
	if parts.size() >= MAX_PARTS:
		var index: int = 0
		var score: float = INF
		for i in range(parts.size()):
			var candidate: float = float(parts[i].I) + (0.0 if parts[i].kind == "trail" else 10.0)
			if candidate < score:
				index = i
				score = candidate
		_pool.append(parts[index])
		parts.remove_at(index)
	var p: Dictionary = _pool.pop_back() if not _pool.is_empty() else {}
	p.clear()
	p.merge({"vx": 0.0, "vy": 0.0, "rot": 0.0, "age": 0.0, "slide": false, "trailT": 0.0, "hold": 0.0, "pop": 1.0, "grow": 0.0, "seed": randf()*100.0, "mass": 1.0})
	parts.append(p)
	return p

func add(kind: String, channel: int, x: float, y: float, radius: float, options: Dictionary = {}) -> Dictionary:
	var p: Dictionary = _new()
	p.merge({"kind": kind, "ch": channel, "x": x, "y": y, "r": radius, "rx": options.get("rx",radius), "ry": options.get("ry",radius), "rot": options.get("rot",0.0), "I0": options.get("I",1.0), "I": options.get("I",1.0), "life": options.get("life",1.5), "stick": options.get("stick",99.0), "pop": options.get("pop",0.09)}, true)
	p.grow = 0.0 if float(p.pop) > 0 else 1.0
	return p

func splat(channel: int, center: Vector2, size: float, arms: int = 6, satellites: int = 6, life: float = 2.1) -> void:
	var rotation: float = randf()*TAU
	add("drop",channel,center.x,center.y,size*.92,{"I":1.4,"life":life*randf_range(.95,1.15),"stick":randf_range(.25,.55)})
	var lumps: int = 3+randi()%2
	for i in range(lumps):
		var a: float = rotation+float(i)/lumps*TAU+randf_range(-.5,.5)
		var pos: Vector2 = center+Vector2(cos(a)/aspect,sin(a))*size*randf_range(.3,.55)
		var p: Dictionary = add("drop",channel,pos.x,pos.y,size*randf_range(.5,.72),{"I":1.25,"life":life*randf_range(.75,1.0),"stick":randf_range(.5,1.2)})
		p.mass=.6
	for i in range(arms):
		var a: float = rotation+(float(i)+randf_range(-.3,.3))/arms*TAU
		var longer: bool = randf()<.3
		var length: float = size*(randf_range(1.35,1.8) if longer else randf_range(.85,1.2))
		var neck: Vector2 = center+Vector2(cos(a)/aspect,sin(a))*length*.5
		add("arm",channel,neck.x,neck.y,size*.3,{"rx":size*randf_range(.2,.3)*(.8 if longer else 1.0),"ry":length*.5,"rot":a-PI*.5,"I":1.3,"life":life*randf_range(.6,.85)})
		var tip: Vector2 = center+Vector2(cos(a)/aspect,sin(a))*length
		var p: Dictionary = add("drop",channel,tip.x,tip.y,size*(randf_range(.26,.34) if longer else randf_range(.3,.42)),{"I":1.35,"life":life*randf_range(.7,1.0),"stick":randf_range(.4,1.1)})
		p.mass=.4
	for i in range(satellites):
		var a: float=randf()*TAU
		var radius: float=size*randf_range(.07,.16)
		var pos: Vector2=center+Vector2(cos(a)/aspect,sin(a))*size*randf_range(1.45,2.5)
		var stretch: bool=randf()<.4
		add("sat",channel,pos.x,pos.y,radius,{"rx":radius*(.7 if stretch else 1.0),"ry":radius*(1.9 if stretch else 1.0),"rot":a-PI*.5,"I":1.3,"life":randf_range(.5,1.3),"pop":.05})

func droplet(channel: int, pos: Vector2, radius: float, slide: float = .25, life: float = 1.1) -> void:
	var p: Dictionary = add("drop",channel,pos.x,pos.y,radius,{"I":1.3,"life":life,"stick":slide,"pop":.05})
	p.mass=.3

func clear() -> void:
	while not parts.is_empty():
		_pool.append(parts.pop_back())
	if mesh:
		mesh.multimesh.visible_instance_count=0
		target.render_target_update_mode=SubViewport.UPDATE_ONCE

func update(dt: float) -> void:
	# Snapshot references so appended trails/recycling do not change iteration indices.
	var snapshot: Array = parts.duplicate()
	for p: Dictionary in snapshot:
		if not parts.has(p): continue
		p.age+=dt
		p.grow=minf(1.0,float(p.grow)+dt/maxf(.01,float(p.pop)))
		var fade: float=1.0-(float(p.age)-float(p.life))/(.9 if p.kind=="trail" else .55) if float(p.age)>float(p.life) else 1.0
		p.I=float(p.I0)*clampf(1.0-float(p.age)/float(p.life) if p.kind=="trail" else fade,0,1)
		if float(p.I)<=.01:
			parts.erase(p)
			_pool.append(p)
			continue
		if p.kind=="drop":
			if not bool(p.slide) and float(p.age)>float(p.stick) and float(p.r)>.012:p.slide=true
			if bool(p.slide):
				p.hold-=dt
				if float(p.hold)<=0 and randf()<dt*.45:p.hold=randf_range(.06,.22)
				var gravity: float=0 if float(p.hold)>0 else 1.05*(float(p.r)/.05)*(.55+.45*float(p.mass))
				p.vy=(float(p.vy)-gravity*dt)*exp(-dt*(12.0 if float(p.hold)>0 else 2.1))
				p.vx=sin(float(p.age)*2.3+float(p.seed))*.006+sin(float(p.age)*6.1+float(p.seed)*2)*.003
				var distance:=Vector2(float(p.vx)*dt,float(p.vy)*dt)
				p.x+=distance.x
				p.y+=distance.y
				p.trailT+=Vector2(distance.x*aspect,distance.y).length()
				if float(p.trailT)>float(p.r)*.55:
					p.trailT=0.0
					add("trail",p.ch,p.x,float(p.y)+float(p.r)*.45,float(p.r)*.55,{"rx":float(p.r)*.42,"ry":float(p.r)*.72,"I":.5,"life":1.2,"pop":0.0})
					p.r*=.965
				p.ry=float(p.r)*(1+minf(.9,-float(p.vy)*9))
				p.rx=float(p.r)*(1-minf(.25,-float(p.vy)*2.5))
				if float(p.r)<.01:
					p.slide=false
					p.life=minf(float(p.life),float(p.age)+.2)
			else:
				p.rx=p.r
				p.ry=p.r
			if float(p.y)<-.1:
				parts.erase(p)
				_pool.append(p)
	for i in range(parts.size()):
		var p: Dictionary=parts[i]
		var g: float=1.0 if float(p.grow)>=1.0 else .35+.65*(1-pow(1-float(p.grow),3))*(1+.12*sin(float(p.grow)*PI))
		var rotation: float=-float(p.rot)
		var rx: float=float(p.rx)*g*target.size.y
		var ry: float=float(p.ry)*g*target.size.y
		mesh.multimesh.set_instance_transform_2d(i,Transform2D(Vector2(cos(rotation),sin(rotation))*rx,Vector2(-sin(rotation),cos(rotation))*ry,Vector2(float(p.x)*target.size.x,(1-float(p.y))*target.size.y)))
		var color:=Color(0,0,0,1)
		color[int(p.ch)]=float(p.I)
		mesh.multimesh.set_instance_color(i,color)
	mesh.multimesh.visible_instance_count=parts.size()
	if not parts.is_empty():
		target.render_target_update_mode=SubViewport.UPDATE_ALWAYS
	elif _had_parts:
		target.render_target_update_mode=SubViewport.UPDATE_ONCE
	elif target.render_target_update_mode!=SubViewport.UPDATE_ONCE:
		target.render_target_update_mode=SubViewport.UPDATE_DISABLED
	_had_parts=not parts.is_empty()
