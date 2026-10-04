class_name InkSwimWake
extends RefCounted
## The original four 12-point trails, with local priority and teleport breaks.
var slots: Array[Dictionary]=[]

func _init() -> void:
	for i in 4:slots.append({"actor":null,"pts":[],"k":0.0,"speed":0.0,"forward":Vector3.BACK,"head":Vector3.ZERO,"last":null,"swimming":false})

func update(dt: float,now: float,actors: Array,camera_position: Vector3) -> Dictionary:
	var candidates:Array=[]
	for actor in actors:
		if not actor.alive or actor.form not in ["swim","climb"]:continue
		if not actor.is_local and actor.global_position.distance_squared_to(camera_position)>38*38:continue
		candidates.append(actor)
	candidates.sort_custom(func(a,b):return (-1.0 if a.is_local else a.global_position.distance_squared_to(camera_position))<(-1.0 if b.is_local else b.global_position.distance_squared_to(camera_position)))
	for slot in slots:slot.swimming=false
	for actor in candidates:
		var slot:Dictionary={}
		for existing in slots:
			if existing.actor==actor:slot=existing;break
		if slot.is_empty():
			for existing in slots:
				if not is_instance_valid(existing.actor):slot=existing;break
		if slot.is_empty() and actor.is_local:
			var far:= -1.0
			for existing in slots:
				var distance:float=existing.actor.global_position.distance_squared_to(camera_position)
				if distance>far:slot=existing;far=distance
		if slot.is_empty():continue
		if slot.actor!=actor:slot.actor=actor;slot.pts.clear();slot.last=null;slot.k=0.0
		slot.swimming=true
	for slot in slots:
		if not is_instance_valid(slot.actor):slot.actor=null;slot.pts.clear();slot.k=0;continue
		while not slot.pts.is_empty() and (slot.pts[0].w== -9.0 or now-slot.pts[0].w>1.15):slot.pts.pop_front()
		if slot.swimming:
			var position:Vector3=slot.actor.global_position;var velocity:Vector3=slot.actor.velocity;var speed:=velocity.length()
			if speed>.6:slot.forward=Vector3(velocity.x,velocity.y if slot.actor.form=="climb" else 0.0,velocity.z).normalized()
			slot.speed=lerpf(slot.speed,clampf(speed/11.8,0,1),1-exp(-10*dt))
			if slot.last!=null and slot.last.distance_squared_to(position)>2.5*2.5:
				if not slot.pts.is_empty() and slot.pts[-1].w!= -9:slot.pts.append(Vector4(0,0,0,-9))
				slot.last=null
			if slot.last==null or slot.last.distance_squared_to(position)>.75*.75:
				if speed>.8 or slot.last==null:slot.pts.append(Vector4(position.x,position.y,position.z,now));slot.last=position
			slot.head=position;slot.k=lerpf(slot.k,1,1-exp(-14*dt))
		else:
			if not slot.pts.is_empty() and slot.pts[-1].w!= -9:slot.pts.append(Vector4(0,0,0,-9))
			slot.last=null;slot.k=lerpf(slot.k,0,1-exp(-16*dt))
			if slot.k<.004 and slot.pts.is_empty():slot.actor=null;slot.k=0.0
		while slot.pts.size()>11:slot.pts.pop_front()
	var points:=PackedVector4Array();points.resize(48);points.fill(Vector4(0,0,0,-9))
	var bounds:=PackedVector4Array();bounds.resize(4)
	var heads:=PackedVector4Array();heads.resize(4)
	var forwards:=PackedVector4Array();forwards.resize(4)
	for i in 4:
		var slot:Dictionary=slots[i]
		if not is_instance_valid(slot.actor):continue
		var n:=0;var center:=Vector3.ZERO;var valid:=0
		for point in slot.pts:
			points[i*12+n]=point;n+=1
			if point.w!= -9:center+=Vector3(point.x,point.y,point.z);valid+=1
		if slot.swimming:
			points[i*12+n]=Vector4(slot.head.x,slot.head.y,slot.head.z,now);n+=1;center+=slot.head;valid+=1
		if valid>0:
			center/=valid;var radius:=center.distance_to(slot.head)
			for j in n:
				var point:=points[i*12+j]
				if point.w!= -9:radius=maxf(radius,center.distance_to(Vector3(point.x,point.y,point.z)))
			bounds[i]=Vector4(center.x,center.y,center.z,radius+1.6)
		heads[i]=Vector4(slot.head.x,slot.head.y,slot.head.z,slot.k)
		forwards[i]=Vector4(slot.forward.x,slot.forward.y,slot.forward.z,slot.speed)
	return {"wake_points":points,"wake_bounds":bounds,"swimmers":heads,"swimmer_dirs":forwards}
