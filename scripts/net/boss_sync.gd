class_name InkNetBossSync
extends RefCounted
## The host simulates the boss. Guests retain its sockets and draw the host's action pose.
const HazardVisuals=preload("res://scripts/fx/boss_hazard_visuals.gd")

var network: InkNetwork
var _buffer: Array = []
var _crabs: Dictionary = {}
var _hazards: Array[MeshInstance3D] = []
var _display: Dictionary = {}
var _event_history:Array[Dictionary]=[]
var _event_serial:int=0
var _last_event:int=0

func clear() -> void:
	_buffer.clear()
	_display.clear()
	_event_history.clear();_event_serial=0;_last_event=0
	for node: Node3D in _crabs.values():
		if is_instance_valid(node): node.queue_free()
	for node: Node3D in _hazards:
		if is_instance_valid(node): node.queue_free()
	_crabs.clear()
	_hazards.clear()

static func _v(value: Vector3) -> Array:
	return [snappedf(value.x, 0.01), snappedf(value.y, 0.01), snappedf(value.z, 0.01)]

static func _vector(value: Array) -> Vector3:
	return Vector3(float(value[0]), float(value[1]), float(value[2]))

func pack(boss: Node3D) -> Dictionary:
	var p: Vector3 = boss.global_position
	var velocity: Vector3 = boss.get("velocity") as Vector3
	var flags: int = (1 if bool(boss.get("stunned")) else 0) | (2 if bool(boss.get("dead")) else 0) | (8 if boss.visible else 0) | (4 if bool(boss.get("invuln")) else 0)
	var crabs: Array = []
	for crab: Dictionary in boss.get("_crablets"):
		if bool(crab.get("dead",false)):continue
		var node: Node3D = crab.node as Node3D
		if not is_instance_valid(node):continue
		crabs.append([int(crab.get("id",node.get_meta("crablet_id",crabs.size()))), node.global_position.x, node.global_position.y, node.global_position.z, node.rotation.y, float(crab.hp)])
	var native: Dictionary = {"move": str(boss.get("move_id")), "move_phase": str(boss.get("move_phase")), "move_time": float(boss.get("move_time")), "timing": (boss.get("_timing") as Array).duplicate(), "clip": str(boss.get("_source_clip")), "flash": float(boss.get("_flash")), "hazards": []}
	native.params=_pack_value(boss.get("_move_params"))
	native.tear=float(boss.get("_tear"));native.tear_velocity=float(boss.get("_tear_velocity"))
	var animation:AnimationPlayer=boss.get("_source_anim") as AnimationPlayer
	if animation!=null:native.clip_position=animation.current_animation_position;native.clip_rate=animation.speed_scale
	var now:float=Time.get_ticks_msec()/1000.0
	while not _event_history.is_empty() and now-float(_event_history.front().time)>1.0:_event_history.pop_front()
	native.display_events=[]
	for event:Dictionary in _event_history:native.display_events.append([event.id,event.kind,event.data])
	var model: Node3D = boss.get("_model") as Node3D
	if model != null:
		native.model_position = _v(model.position)
		native.model_rotation = _v(model.rotation)
	for key: String in ["_telegraph", "_beam"]:
		var mesh: Node3D = boss.get(key) as Node3D
		if mesh != null:
			native[key] = {"visible": mesh.visible, "p": _v(mesh.position), "r": _v(mesh.rotation), "s": _v(mesh.scale)}
			if mesh is MeshInstance3D and mesh.has_meta("boss_visual_kind"):native[key].visual=_pack_value(HazardVisuals.describe(mesh))
	for hazard: Dictionary in boss.get("_hazards"):
		if native.hazards.size() >= 64: break
		var mesh: Node3D = hazard.node as Node3D
		if not is_instance_valid(mesh):continue
		native.hazards.append(_pack_mesh(mesh,"ring",float(hazard.radius)))
		var barrel:Node3D=hazard.get("barrel") as Node3D
		if is_instance_valid(barrel):native.hazards.append(_pack_mesh(barrel,"barrel",.42))
	return {"B": [float(boss.get("clock")), p.x, p.y, p.z, boss.rotation.y, velocity.x, velocity.z, float(boss.get("hp")), int(boss.get("phase")), flags, -1, str(boss.get("_source_clip")), 0, 0, 0, -1, crabs, float(boss.get("max_hp"))], "NB": native}

func receive(timestamp: float, sample: Variant, native: Variant) -> void:
	if not sample is Array or sample.size() < 18 or sample.size() > 20: return
	for index: int in [0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 17]:
		if not sample[index] is int and not sample[index] is float: return
		if not is_finite(float(sample[index])): return
	if not sample[16] is Array or sample[16].size() > 32: return
	if not _buffer.is_empty() and timestamp <= float(_buffer.back().t): return
	_buffer.append({"t": timestamp, "a": sample, "native": native if native is Dictionary else {}})
	while _buffer.size() > 32: _buffer.pop_front()

func update(delta: float, playback: float) -> void:
	var boss: Node3D = network.game.get("boss") as Node3D
	if boss == null or _buffer.is_empty() or network.is_authority: return
	while _buffer.size() > 2 and float(_buffer[1].t) < playback: _buffer.pop_front()
	var first: Dictionary = _buffer.front()
	var second: Dictionary = _buffer[1] if _buffer.size() > 1 else first
	var blend: float = clampf((playback - float(first.t)) / maxf(0.001, float(second.t) - float(first.t)), 0, 1)
	var a: Array = first.a as Array
	var b: Array = second.a as Array
	boss.global_position = Vector3(float(a[1]), float(a[2]), float(a[3])).lerp(Vector3(float(b[1]), float(b[2]), float(b[3])), blend)
	boss.rotation.y = lerp_angle(float(a[4]), float(b[4]), blend)
	boss.set("velocity",Vector3(lerpf(float(a[5]),float(b[5]),blend),0,lerpf(float(a[6]),float(b[6]),blend)))
	boss.set("clock", lerpf(float(a[0]), float(b[0]), blend))
	boss.set("hp", float(b[7]))
	boss.set("max_hp", float(b[17]))
	boss.set("phase", int(b[8]))
	boss.set("stunned", (int(b[9]) & 1) != 0)
	boss.set("dead", (int(b[9]) & 2) != 0)
	boss.set("alive", (int(b[9]) & 2) == 0)
	boss.set("invuln",(int(b[9])&4)!=0)
	boss.visible = (int(b[9]) & 8) != 0
	var native: Dictionary = first.native as Dictionary
	for key: String in ["move_id", "move_phase", "move_time"]:
		boss.set(key, native.get("move" if key == "move_id" else key, "" if key != "move_time" else 0.0))
	if native.get("params") is Dictionary:boss.set("_move_params",_unpack_value(native.params))
	if native.get("timing") is Array:boss.set("_timing",native.timing)
	boss.set("_tear",float(native.get("tear",0)));boss.set("_tear_velocity",float(native.get("tear_velocity",0)))
	if not str(native.get("clip", b[11])).is_empty(): boss.call("_play_source_clip", str(native.get("clip", b[11])))
	var player: AnimationPlayer = boss.get("_source_anim") as AnimationPlayer
	if player != null and boss.visible:
		player.speed_scale=float(native.get("clip_rate",1))
		if native.has("clip_position"):
			var position:float=float(native.clip_position)+maxf(0,float(boss.get("clock"))-float(a[0]))*player.speed_scale
			var clip:Animation=player.get_animation(player.current_animation)
			if clip!=null:position=fposmod(position,clip.length) if clip.loop_mode==Animation.LOOP_LINEAR else minf(position,clip.length)
			player.seek(position,true)
		else:player.advance(delta)
	if boss.has_method("update_visual_channels"):boss.call("update_visual_channels",delta)
	var model: Node3D = boss.get("_model") as Node3D
	if model != null and native.has("model_position"):
		model.position = _vector(native.model_position)
		model.rotation = _vector(native.model_rotation)
	for material: ShaderMaterial in boss.get("_source_materials"):
		material.set_shader_parameter("uTime", float(boss.get("clock")))
		material.set_shader_parameter("uPhase", int(b[8]))
		material.set_shader_parameter("hit_flash", float(native.get("flash", 0)) * 0.3)
	for key: String in ["_telegraph", "_beam"]:
		var mesh: Node3D = boss.get(key) as Node3D
		var value: Dictionary = native.get(key, {}) as Dictionary
		if mesh != null and not value.is_empty():
			if mesh is MeshInstance3D and value.get("visual") is Dictionary:HazardVisuals.apply_description(mesh,_unpack_value(value.visual),boss.call("team_color"))
			mesh.visible = bool(value.visible)
			mesh.position = _vector(value.p)
			mesh.rotation = _vector(value.r)
			mesh.scale = _vector(value.s)
	_crablets(b[16] as Array, boss,delta)
	_draw_hazards(native.get("hazards", []) as Array, boss)
	_display_events(boss, b, native)
	if boss.has_method("push_actors"):boss.call("push_actors")

static func _pack_value(value:Variant,depth:int=0)->Variant:
	if depth>4:return null
	if value is Vector3:return {"v3":_v(value)}
	if value is float:return snappedf(value,.001) if is_finite(value) else 0.0
	if value is int or value is bool or value is String:return value
	if value is Array or value is PackedFloat32Array:
		var rows:Array=[]
		for item:Variant in value:
			if rows.size()>=128:break
			rows.append(_pack_value(item,depth+1))
		return rows
	if value is Dictionary:
		var result:Dictionary={}
		for key:Variant in value:
			if result.size()>=32:break
			result[str(key)]=_pack_value(value[key],depth+1)
		return result
	return null

static func _unpack_value(value:Variant,depth:int=0)->Variant:
	if depth>4:return null
	if value is Dictionary:
		if value.get("v3") is Array and value.v3.size()==3:return _vector(value.v3)
		var result:Dictionary={}
		for key:Variant in value:
			if result.size()>=32:break
			result[str(key)]=_unpack_value(value[key],depth+1)
		return result
	if value is Array:
		var rows:Array=[]
		for item:Variant in value:
			if rows.size()>=128:break
			rows.append(_unpack_value(item,depth+1))
		return rows
	if value is float:return value if is_finite(value) else 0.0
	if value is String or value is int or value is bool:return value
	return null

static func _pack_mesh(node:Node3D,kind:String,radius:float)->Dictionary:
	var packet:Dictionary={"p":_v(node.global_position),"r":_v(node.rotation),"s":_v(node.scale),"radius":radius,"kind":kind,"visible":node.visible}
	var mesh:MeshInstance3D=node as MeshInstance3D
	if mesh.has_meta("boss_visual_kind"):packet.visual=_pack_value(HazardVisuals.describe(mesh))
	var material:StandardMaterial3D=mesh.material_override as StandardMaterial3D
	if material!=null:
		packet.material={"color":material.albedo_color.to_html(true),"roughness":material.roughness,"metallic":material.metallic,"emission":material.emission.to_html(true),"emission_enabled":material.emission_enabled,"emission_energy":material.emission_energy_multiplier}
	return packet

func _emit(kind: String, data: Dictionary) -> void:
	# These are display events derived from an authoritative snapshot, as boss.js _events().
	# They never become another damage request or an outgoing relay event.
	var previous: bool = network.applying
	network.applying = true
	network.game.call("notify_event", kind, data)
	network.applying = previous

func record_event(kind:String,data:Dictionary)->void:
	if kind not in ["boss:foot","boss:impact","boss:crablet","boss:fx"]:return
	_event_serial+=1
	var packed:Dictionary=InkNetEventCodec.pack(data)
	if data.get("data") is Dictionary:packed.data=_pack_value(data.data)
	_event_history.append({"id":_event_serial,"time":Time.get_ticks_msec()/1000.0,"kind":kind,"data":packed})
	while _event_history.size()>32:_event_history.pop_front()

func _display_events(boss: Node3D, sample: Array, native: Dictionary) -> void:
	var current_hp: float = float(sample[7])
	var current_phase: int = int(sample[8])
	var current_stun: bool = (int(sample[9]) & 1) != 0
	var current_dead: bool = (int(sample[9]) & 2) != 0
	var clip: String = str(native.get("clip", sample[11]))
	if _display.is_empty():
		_display = {"intro": false, "hp": current_hp, "phase": 1, "stun": false, "dead": false, "move": "", "move_phase": "", "move_start": -100.0, "crabs": {}}
		_emit("boss:spawn", {"boss": boss})
	if clip == "boss_intro" and (int(sample[9])&8)!=0 and not bool(_display.intro):
		_display.intro = true
		_emit("boss:intro", {"boss": boss, "dur": 3.4})
	var move: String = str(native.get("move", ""))
	var move_phase: String = str(native.get("move_phase", "")) if not current_dead else ""
	var move_start: float = float(sample[0]) - float(native.get("move_time", 0.0))
	var timing: Array = native.get("timing", InkBoss.MOVE_TIMES.get(move, [1.0, 1.0, 1.0])) as Array
	var changed: bool = move != str(_display.move) or move_phase != str(_display.move_phase) or absf(move_start - float(_display.move_start)) > 0.35
	if changed:
		_display.move = move
		_display.move_phase = move_phase
		_display.move_start = move_start
		var phase_index: int = ["tele", "act", "rec"].find(move_phase)
		if not move.is_empty() and phase_index >= 0:
			_emit("boss:move", {"boss": boss, "id": move, "phase": move_phase, "dur": float(timing[phase_index]) if timing.size() > phase_index else 1.0})
	if current_stun != bool(_display.stun):
		_display.stun = current_stun
		if current_stun:
			var remaining: float = 1.5
			if timing.size() == 3: remaining = maxf(0.5, float(timing[0]) + float(timing[1]) + float(timing[2]) - float(native.get("move_time", 0.0)))
			_emit("boss:stun", {"boss": boss, "dur": remaining})
	if current_phase != int(_display.phase):
		_display.phase = current_phase
		_emit("boss:phase", {"boss": boss, "phase": current_phase})
	if absf(current_hp - float(_display.hp)) > 0.01:
		_display.hp = current_hp
		_emit("boss:hp", {"boss": boss, "hp": current_hp, "max": float(sample[17])})
	if current_dead and not bool(_display.dead):
		_display.dead = true
		_emit("boss:defeat", {"boss": boss, "by": null})
		_emit("shake", {"amount": 0.9, "pos": boss.global_position})
	var crab_events:Dictionary={}
	for event:Variant in native.get("display_events",[]):
		if not event is Array or event.size()!=3 or not event[2] is Dictionary:continue
		if int(event[0])<=_last_event:continue
		_last_event=int(event[0])
		var kind:String=str(event[1])
		if kind not in ["boss:foot","boss:impact","boss:crablet","boss:fx"]:continue
		var payload:Dictionary=InkNetEventCodec.unpack(event[2],network.replication.actors);payload.boss=boss
		if event[2].get("data") is Dictionary:payload.data=_unpack_value(event[2].data)
		if kind=="boss:crablet":crab_events[int(payload.get("id",-1))]=true
		_emit(kind,payload)
		if kind=="boss:impact" or kind=="boss:foot" and float(payload.get("strength",0))>.5:_emit("shake",{"pos":payload.get("pos",boss.global_position),"amount":float(payload.get("strength",1))*(.5 if kind=="boss:impact" else .12)})
	var crabs: Dictionary = {}
	for crab: Array in sample[16]:
		if crab.size() < 6: continue
		var id: int = int(crab[0])
		var point := Vector3(float(crab[1]), float(crab[2]) + 0.3, float(crab[3]))
		crabs[id] = point
		if not (_display.crabs as Dictionary).has(id) and not crab_events.has(id): _emit("boss:crablet", {"boss":boss,"id":id,"phase": "spawn", "pos": point})
	for id: Variant in (_display.crabs as Dictionary).keys():
		if not current_dead and not crabs.has(id) and not crab_events.has(id): _emit("boss:crablet", {"boss":boss,"id":id,"phase": "pop", "pos": _display.crabs[id], "killed": true})
	_display.crabs = crabs

func _crablets(samples: Array, boss: Node3D,delta:float) -> void:
	var records: Array[Dictionary] = []
	var active:Dictionary={}
	for sample:Array in samples:
		if sample.size() < 6: continue
		var id:int=int(sample[0]);active[id]=true
		var position:=Vector3(float(sample[1]),float(sample[2]),float(sample[3]))
		if not _crabs.has(id):
			var spawned:=Node3D.new();network.game.add_child(spawned);spawned.global_position=position
			spawned.add_child(InkAvatar.create_source_asset("crablet", boss.call("team_color"), (boss.get("_weak_material") as StandardMaterial3D).albedo_color));spawned.set_meta("crablet_id",id);spawned.set_meta("last_position",position);spawned.set_meta("speed",0.0);spawned.set_meta("last_hp",float(sample[5]));_crabs[id]=spawned
		var root:Node3D=_crabs[id] as Node3D
		var speed:float=root.global_position.distance_to(position)/maxf(.001,delta)
		speed=lerpf(float(root.get_meta("speed",0)),speed,minf(1,delta*12));root.set_meta("speed",speed)
		root.global_position=position;root.rotation.y=float(sample[4]);root.visible=true
		if float(sample[5])<float(root.get_meta("last_hp",sample[5])):InkAvatar.hit_source_crablet(root)
		root.set_meta("last_hp",float(sample[5]));InkAvatar.update_source_crablet(root,delta,speed,false)
		records.append({"id":id,"node":root,"hp":float(sample[5]),"life":12.0,"dead":false})
	for id:Variant in _crabs.keys():
		if active.has(id):continue
		var root:Node3D=_crabs[id] as Node3D
		if InkAvatar.update_source_crablet(root,delta,0,true):root.queue_free();_crabs.erase(id)
	boss.set("_crablets", records)

func _draw_hazards(samples: Array, boss: Node3D) -> void:
	samples=samples.slice(0,64)
	var visual_hazards:Array[Dictionary]=[]
	while _hazards.size() < samples.size():
		var node := MeshInstance3D.new()
		node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		network.game.add_child(node)
		_hazards.append(node)
	for index: int in _hazards.size():
		_hazards[index].visible = index < samples.size()
		if index >= samples.size(): continue
		var sample: Dictionary = samples[index]
		var node:MeshInstance3D=_hazards[index]
		var kind:String=str(sample.get("kind","ring"));var radius:float=maxf(.101,float(sample.radius))
		var signature:String=kind+str(radius)
		var visual:Dictionary=_unpack_value(sample.visual) if sample.get("visual") is Dictionary else {}
		if not visual.is_empty():
			HazardVisuals.apply_description(node,visual,boss.call("team_color"))
			node.set_meta("mesh_signature","")
		elif str(node.get_meta("mesh_signature",""))!=signature:
			node.set_meta("mesh_signature",signature)
			node.remove_meta("boss_visual_signature")
			if kind=="barrel":
				var cylinder:=CylinderMesh.new();cylinder.top_radius=.42;cylinder.bottom_radius=.42;cylinder.height=.95;cylinder.radial_segments=16;node.mesh=cylinder
			else:
				var ring:=TorusMesh.new();ring.inner_radius=radius-.1;ring.outer_radius=radius;ring.rings=96;ring.ring_segments=6;node.mesh=ring
			node.material_override=(boss.get("_weak_material") as Material).duplicate() if kind=="ring" else StandardMaterial3D.new()
		var properties:Dictionary=sample.get("material",{}) as Dictionary
		var material:StandardMaterial3D=node.material_override as StandardMaterial3D
		if material!=null and not properties.is_empty():
			material.albedo_color=Color(str(properties.get("color","ffffff")));material.roughness=float(properties.get("roughness",.55));material.metallic=float(properties.get("metallic",0))
			material.emission=Color(str(properties.get("emission","000000")));material.emission_enabled=bool(properties.get("emission_enabled",false));material.emission_energy_multiplier=float(properties.get("emission_energy",0))
		_hazards[index].global_position = _vector(sample.p)
		_hazards[index].rotation = _vector(sample.get("r",[0,0,0]))
		_hazards[index].scale = _vector(sample.s)
		_hazards[index].visible=bool(sample.get("visible",true))
		if node.visible and str(visual.get("kind",""))=="ring":visual_hazards.append({"kind":"ring","pos":node.global_position-Vector3.UP*.06,"display_radius":float(visual.get("uniforms",{}).get("uR",0)),"reach":visual.get("recipe",{}).get("reach",[])})
	boss.set("_visual_hazards",visual_hazards)

func send_hit(attacker: Node, amount: float, weapon: String, weak: bool, crab: int) -> bool:
	if network.is_authority: return false
	if not network.owns_actor(attacker): return true
	var payload:Dictionary={"k": "bhit", "a": int(attacker.get_meta("net_slot", -1)), "d": clampf(amount, 0, 200), "w": weapon, "weak": weak, "c": crab}
	var boss:Node=network.game.get("boss") as Node
	if crab>=0 and is_instance_valid(boss):
		var records:Array=boss.get("_crablets") as Array
		if crab<records.size():payload.cid=int(records[crab].get("id",-1))
	network.send(payload, network.host_id)
	return true

func apply_hit(data: Dictionary) -> void:
	if not network.is_authority: return
	var boss: Node = network.game.get("boss") as Node
	var id: int = int(data.get("a", -1))
	if boss == null or id < 0 or id >= network.replication.actors.size(): return
	var crab: int = int(data.get("c", -1))
	if crab >= 0:
		var crabs: Array = boss.get("_crablets") as Array
		if data.has("cid"):
			crab=-1
			for index:int in crabs.size():
				if int(crabs[index].get("id",-1))==int(data.cid):crab=index;break
		if crab>=0 and crab<crabs.size() and boss.has_method("damage_crablet"):boss.call("damage_crablet",crab,float(data.d),network.replication.actors[id],str(data.get("w","shooter")))
	else:
		var before:float=float(boss.get("hp"))
		var attacker:Node=network.replication.actors[id]
		boss.call("damage", float(data.d), attacker, str(data.get("w", "shooter")), bool(data.get("weak", false)))
		var applied:float=maxf(0,before-float(boss.get("hp")))
		# The remote shooter receives its accepted hit marker/number, with the canonical weapon multipliers.
		network.send({"k":"bhfx","a":id,"d":applied,"weak":bool(data.get("weak",false)),"blocked":applied<=0},str(attacker.get_meta("net_owner",network.host_id)))

func receive_hit_feedback(data:Dictionary)->void:
	var id:int=int(data.get("a",-1))
	if id<0 or id>=network.replication.actors.size():return
	var attacker:Node=network.replication.actors[id]
	if not network.owns_actor(attacker):return
	var boss:Node3D=network.game.get("boss") as Node3D
	if boss==null:return
	_emit("boss:hit",{"boss":boss,"attacker":attacker,"damage":maxf(0,float(data.get("d",0))),"weak":bool(data.get("weak",false)),"blocked":bool(data.get("blocked",false))})
