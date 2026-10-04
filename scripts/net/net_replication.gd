class_name InkNetReplication
extends RefCounted
## Actor owners simulate; peers render snapshots. Reliable events retain paint and damage.

var network: InkNetwork
var actors: Array = []
var _timelines: Dictionary = {}
var _events: Array = []
var _tick: float = 0
var _clock: float = 0
var _previous_state: String = ""
var _last_spawn: Dictionary = {}
var _stats_clock:float=0
var boss_sync: InkNetBossSync

func clear() -> void:
	if boss_sync != null: boss_sync.clear()
	actors.clear()
	_timelines.clear()
	_events.clear()
	_last_spawn.clear()
	_tick = 0
	_clock = 0
	_previous_state = ""
	_stats_clock=0

func bind_match() -> void:
	clear()
	boss_sync = InkNetBossSync.new()
	boss_sync.network = network
	actors = (network.game.get("actors") as Array).duplicate()
	for entry: Dictionary in network.roster:
		var id: int = int(entry.nid)
		if id >= actors.size(): continue
		var actor: Node = actors[id]
		actor.set_meta("net_slot", id)
		actor.set_meta("net_owner", str(entry.owner))
		actor.set_meta("net_bot", bool(entry.bot))
		actor.set_meta("slot", id)
		actor.set("is_local", str(entry.owner) == network.local_id and not bool(entry.bot))
		actor.set_meta("net_teleport", 0)
		_last_spawn[id] = bool(actor.get("alive"))

func update(delta: float) -> void:
	var now: float = float(Time.get_ticks_msec()) / 1000.0
	for sender: String in _timelines:
		var timeline: InkPeerTimeline = _timelines[sender]
		timeline.advance(delta, now)
		for entry: Dictionary in network.roster:
			var id: int = int(entry.nid)
			if str(entry.owner) != sender or id >= actors.size(): continue
			var state: Dictionary = timeline.sample(id)
			if state.is_empty(): continue
			var actor: Node3D = actors[id] as Node3D
			var was_climbing:bool=bool(actor.get("climbing"))
			InkSnapshotCodec.apply(actor, state)
			if was_climbing!=bool(actor.get("climbing")):
				var previous_applying:bool=network.applying
				network.applying=true
				network.game.call("notify_event","actor:climb",{"actor":actor,"on":bool(actor.get("climbing"))})
				network.applying=previous_applying
			_animate_remote(actor, state, delta)
		for event: Array in timeline.due_events(): _apply_event(sender, event)
		if sender == network.host_id and boss_sync != null: boss_sync.update(delta, timeline.playback)
	_tick -= delta
	_clock -= delta
	_stats_clock -= delta
	if _tick > 0: return
	_tick = 0.05
	var samples: Array = []
	for actor: Node3D in actors:
		if not network.owns_actor(actor): continue
		var id: int = int(actor.get_meta("net_slot", actors.find(actor)))
		var alive: bool = bool(actor.get("alive"))
		if alive and not bool(_last_spawn.get(id, true)):
			actor.set_meta("net_teleport", int(actor.get_meta("net_teleport", 0)) + 1)
		_last_spawn[id] = alive
		samples.append(InkSnapshotCodec.pack(actor, id))
	var message: Dictionary = {"k": "t", "ts": now, "a": samples}
	if _stats_clock<=0:
		_stats_clock=.5
		message.st=pack_stats(network.is_authority)
	if network.relay != null: message.e = _events.duplicate(true)
	elif not _events.is_empty(): network.send({"k": "ev", "ts": now, "e": _events.duplicate(true)})
	_events.clear()
	if network.is_authority:
		var boss: Node3D = network.game.get("boss") as Node3D
		if boss != null: message.merge(boss_sync.pack(boss))
		var game_state: String = str(network.game.get("state"))
		if _clock <= 0:
			message.c = [game_state, float(network.game.get("time_left"))]
			_clock = 0.5
		if game_state != _previous_state:
			_previous_state = game_state
			network.send({"k": "st", "s": game_state, "t": float(network.game.get("time_left"))})
	network.send(message)

func _animate_remote(actor: Node3D, state: Dictionary, delta: float) -> void:
	var avatar: Variant = actor.get("avatar")
	if not is_instance_valid(avatar) or not avatar.has_method("animate"): return
	if avatar is Node3D:(avatar as Node3D).position.y=0.0
	var velocity: Vector3 = state.velocity as Vector3
	var local_move: Vector3 = actor.global_basis.inverse() * velocity
	var flags: int = int(state.flags)
	avatar.visible = (flags & 1) != 0
	avatar.call("animate", delta, {"speed": Vector2(velocity.x, velocity.z).length(), "velocity": velocity, "local_move": Vector2(local_move.x, local_move.z), "grounded": (flags & 16) != 0, "vy": velocity.y, "form": "climb" if (flags & 8) != 0 else "swim" if (flags & 4) != 0 else str(actor.get("form")), "firing": (flags & 4096) != 0, "charge": state.charge, "rolling": (flags & 256) != 0, "aim_pitch": state.aim_pitch, "hp": float(state.hp) / 100.0, "ink": float(state.ink) / 100.0, "tank": float(state.ink) / 100.0, "invuln": (flags & 262144) != 0,"superJump":(flags&49152)!=0})

func _owns(sender: String, id: int) -> bool:
	for entry: Dictionary in network.roster:
		if int(entry.nid) == id: return str(entry.owner) == sender
	return false

func valid_sender(sender: String, data: Dictionary) -> bool:
	if not network.peers.has(sender): return false
	match str(data.get("k", "")):
		"t":
			var values: Variant = data.get("a", [])
			if not values is Array or values.size() > 8: return false
			for sample: Variant in values:
				if not sample is Array or not InkSnapshotCodec.valid(sample) or not _owns(sender, int(sample[0])): return false
			return _valid_events(sender, data.get("e", []))
		"ev": return _valid_events(sender, data.get("e", []))
		"hit", "bhit":
			var owner: bool = _owns(sender, int(data.get("a", -1))) or (sender == network.host_id and int(data.get("a", -1)) == -1)
			var victim: bool = str(data.k) == "bhit" or (int(data.get("v", -1)) >= 0 and int(data.get("v", -1)) < actors.size())
			return owner and victim and is_finite(float(data.get("d", 0))) and float(data.get("d", 0)) > 0 and float(data.get("d", 0)) <= 200
	return sender == network.host_id

func _valid_events(sender: String, values: Variant) -> bool:
	if not values is Array or values.size() > 128: return false
	for event: Variant in values:
		if not event is Array or event.size() < 3 or event.size() > 32: return false
		if not event[0] is float and not event[0] is int: return false
		if not is_finite(float(event[0])): return false
		if str(event[1]) == "s":
			if event.size() < 13: return false
			# A victim's owner also paints the attacker's splat burst on death.
			if int(event[6]) < 0 or int(event[6]) > 1: return false
		elif str(event[1]) == "ev":
			if event.size() < 4 or not event[3] is Dictionary or not str(event[2]) in InkNetEventCodec.ALLOWED: return false
			if not _owns(sender, InkNetEventCodec.primary_id(event[3])): return false
		elif str(event[1]) in ["tr", "p", "b"]:
			if not _owns(sender, int(event[2])): return false
		else: return false
	return true

func receive(sender: String, data: Dictionary) -> void:
	if network.phase not in ["match", "starting"]: return
	var kind: String = str(data.get("k", ""))
	if kind in ["t", "ev", "hit", "bhit"] and not valid_sender(sender, data): return
	match kind:
		"t", "ev":
			var timestamp: float = float(data.get("ts", 0))
			if not is_finite(timestamp): return
			if not _timelines.has(sender): _timelines[sender] = InkPeerTimeline.new()
			var timeline: InkPeerTimeline = _timelines[sender]
			if kind == "t":
				timeline.accept(timestamp, float(Time.get_ticks_msec()) / 1000.0, data.get("a", []) as Array)
				timeline.enqueue_events(data.get("e", []) as Array)
				if sender == network.host_id: _host_clock(data.get("c", []) as Array)
				apply_stats(sender,data.get("st",[]))
				if sender == network.host_id and boss_sync != null: boss_sync.receive(timestamp, data.get("B"), data.get("NB", {}))
			else: timeline.enqueue_events(data.get("e", []) as Array)
		"hit": _apply_hit(data)
		"bhit":
			if boss_sync != null: boss_sync.apply_hit(data)
		"bhfx":
			if sender==network.host_id and not network.is_authority and boss_sync!=null:boss_sync.receive_hit_feedback(data)
		"st":
			if sender != network.host_id or network.is_authority: return
			_host_clock([str(data.get("s", "playing")), float(data.get("t", 0))], true)
			apply_stats(sender,data.get("st",[]))
		"res":
			if sender != network.host_id or network.is_authority: return
			var stats: Dictionary = data.get("r", {}) as Dictionary
			if stats.is_empty(): stats = {"winner": data.get("win", 0), "coverage": data.get("cov", [0, 0]), "mode": data.get("mode", "turf"), "players": data.get("st", [])}
			network.begin_results()
			network.match_finished.emit(stats)
		"own":
			if sender != network.host_id or not data.get("map") is Array: return
			for entry: Dictionary in data.map:
				var id: int = int(entry.get("nid", -1))
				if id < 0 or id >= actors.size(): continue
				actors[id].set_meta("net_owner", str(entry.get("owner", sender)))
				actors[id].set_meta("net_bot", bool(entry.get("bot", true)))
			network.roster = data.map.duplicate(true)

func pack_stats(all_actors:bool=true)->Array:
	var result:Array=[]
	for actor:Node in actors:
		if not all_actors and not network.owns_actor(actor):continue
		result.append([int(actor.get_meta("net_slot",actors.find(actor))),float(actor.get("turf_points")),int(actor.get("splats")),int(actor.get("deaths")),float(actor.get_meta("boss_damage",0)),int(actor.get_meta("weak_hits",0))])
	return result

func apply_stats(sender:String,values:Variant)->void:
	if not values is Array or values.size()>8:return
	for row:Variant in values:
		if not row is Array or row.size()<4 or row.size()>6:continue
		var id:int=int(row[0])
		if id<0 or id>=actors.size() or (sender!=network.host_id and not _owns(sender,id)):continue
		var valid:bool=true
		for value:Variant in row:
			if not (value is int or value is float) or not is_finite(float(value)) or float(value)<0:valid=false;break
		if not valid:continue
		var actor:Node=actors[id]
		var splats:int=int(row[2])
		# Crablet kills are accepted by the boss authority; an earlier owner packet must not erase them.
		if network.is_authority and sender!=network.host_id and is_instance_valid(network.game.get("boss")):splats=maxi(splats,int(actor.get("splats")))
		actor.set("turf_points",float(row[1]));actor.set("splats",splats);actor.set("deaths",int(row[3]))
		if sender==network.host_id and row.size()>=6:
			actor.set_meta("boss_damage",float(row[4]));actor.set_meta("weak_hits",int(row[5]))

func _host_clock(values: Array, force: bool = false) -> void:
	if network.is_authority or values.size() != 2: return
	var time: float = maxf(0, float(values[1]))
	if not is_finite(time): return
	var current: float = float(network.game.get("time_left"))
	if force or absf(current - time) > 0.2: network.game.set("time_left", time if force else lerpf(current, time, 0.5))
	var next: String = str(values[0])
	if next == "playing" and str(network.game.get("state")) == "intro":
		network.game.set("state", "playing")
		network.match_state_changed.emit("playing")
	if next == "finish" and str(network.game.get("state")) == "playing":
		network.game.set("state", "finish")
		network.game.set("match_clock", 0.0)
		network.match_state_changed.emit("finish")

func record_paint(position: Vector3, normal: Vector3, radius: float, team: int, seed: float, options: Dictionary = {}) -> void:
	if _events.size() >= 128: return
	var extra: Dictionary = {"seed": seed}
	for key: String in ["kind", "stretch", "stretchAmt", "cosmetic", "instant", "angle", "surface"]:
		if options.has(key): extra[key] = InkNetEventCodec.pack({"value": options[key]}).get("value")
	# The first 13 entries retain web PROTO=1 compatibility. Native ink metadata is an optional tail.
	_events.append([float(Time.get_ticks_msec()) / 1000.0, "s", position.x, position.y, position.z, radius, team, seed, 0, 0, 0, 0, 0, normal.x, normal.y, normal.z, extra])

func record_event(kind: String, data: Dictionary) -> void:
	if not kind in InkNetEventCodec.ALLOWED or _events.size() >= 128: return
	var actor: Variant = data.get("actor", data.get("victim"))
	if not is_instance_valid(actor) or not network.owns_actor(actor): return
	if kind == "respawn": actor.set_meta("net_teleport", int(actor.get_meta("net_teleport", 0)) + 1)
	var native: Dictionary = InkNetEventCodec.pack(data)
	if kind == "special_activate": kind = "special:use"
	if kind in ["weapon:shot","weapon:flick","weapon:beam"]:
		native["native_kind"]=kind
		native["weapon"]=str(actor.get("weapon_id"))
		if not native.has("muzzle"):native["muzzle"]=native.get("pos",native.get("from",InkNetEventCodec.pack({"p":actor.global_position}).p))
		if kind=="weapon:beam" and data.get("from") is Vector3 and data.get("to") is Vector3:
			var delta:Vector3=data.to-data.from
			native["dir"]=InkNetEventCodec.pack({"d":delta.normalized()}).d;native["len"]=delta.length()
		kind="weapon:fire"
	_events.append([float(Time.get_ticks_msec()) / 1000.0, "ev", kind, native])

func _apply_event(sender: String, event: Array) -> void:
	network.applying = true
	match str(event[1]):
		"s":
			var position: Vector3 = Vector3(float(event[2]), float(event[3]), float(event[4]))
			var radius: float = float(event[5])
			var normal: Vector3 = Vector3(float(event[13]), float(event[14]), float(event[15])) if event.size() >= 16 else Vector3.UP
			if position.is_finite() and absf(position.x) < 512 and absf(position.y) < 512 and absf(position.z) < 512 and is_finite(radius) and radius > 0 and radius <= 20:
				var extra: Dictionary = InkNetEventCodec.unpack(event[16] as Dictionary, actors) if event.size() > 16 and event[16] is Dictionary else {}
				extra["seed"] = float(event[7])
				network.game.call("paint_splat", position, normal.normalized() if normal.length() > 0.1 else Vector3.UP, radius, clampi(int(event[6]), 0, 1), extra)
		"ev":
			var data: Dictionary = InkNetEventCodec.unpack(event[3] as Dictionary, actors)
			var actor: Variant = data.get("actor", data.get("victim"))
			if is_instance_valid(actor) and not network.owns_actor(actor):
				var replay_kind:String=str(event[2])
				if replay_kind=="weapon:fire":
					replay_kind=str(data.get("native_kind","weapon:beam" if str(actor.get("weapon_id"))=="charger" else "weapon:flick" if str(actor.get("weapon_id"))=="roller" else "weapon:shot"))
					if not data.has("pos"):data.pos=data.get("muzzle",actor.global_position)
					if replay_kind=="weapon:beam":data["from"]=data.pos;data["to"]=data.pos+data.get("dir",Vector3.FORWARD)*float(data.get("len",80))
					var projectiles:Node=network.game.get("projectiles") as Node
					if projectiles and projectiles.has_method("replay_ghost_fire"):projectiles.call("replay_ghost_fire",data)
				elif replay_kind=="bomb:throw":
					var projectiles:Node=network.game.get("projectiles") as Node
					if projectiles and projectiles.has_method("replay_ghost_bomb"):projectiles.call("replay_ghost_bomb",data)
				elif replay_kind=="special:use":
					replay_kind="special_activate"
					var projectiles:Node=network.game.get("projectiles") as Node
					if projectiles and projectiles.has_method("replay_ghost_special"):projectiles.call("replay_ghost_special",data)
				if str(event[2]) == "splatted":
					actor.set("alive", false)
					actor.set("hp", 0.0)
					actor.set("deaths", int(actor.get("deaths")) + 1)
					var attacker: Variant = data.get("attacker")
					if is_instance_valid(attacker): attacker.set("splats", int(attacker.get("splats")) + 1)
				network.game.call("notify_event", replay_kind, data)
		"tr":
			var id: int = int(event[2])
			if id >= 0 and id < actors.size() and event.size() > 3 and _owns(sender, id): actors[id].call("trigger", str(event[3]))
	network.applying = false

func send_hit(attacker: Node, victim: Node, amount: float, cause: String) -> bool:
	if network.owns_actor(victim): return false
	if not is_instance_valid(attacker) or not network.owns_actor(attacker): return true
	var victim_id: int = int(victim.get_meta("net_slot", -1))
	var attacker_id: int = int(attacker.get_meta("net_slot", -1))
	var boss_hit: bool = attacker == network.game.get("boss") and network.is_authority
	if victim_id < 0 or (attacker_id < 0 and not boss_hit): return true
	network.send({"k": "hit", "v": victim_id, "a": attacker_id, "d": snappedf(clampf(amount, 0, 200), 0.01), "w": "boss" if boss_hit else str(attacker.get("weapon_id")), "cause": cause}, str(victim.get_meta("net_owner", network.host_id)))
	return true

func _apply_hit(data: Dictionary) -> void:
	var victim: Node = actors[int(data.v)]
	var id: int = int(data.get("a", -1))
	if id >= actors.size() or not network.owns_actor(victim): return
	var attacker: Node = actors[id] if id >= 0 else network.game.get("boss") as Node
	if attacker == null: return
	if int(attacker.get("team_id")) == int(victim.get("team_id")): return
	victim.call("damage", float(data.get("d", 0)), attacker, str(data.get("cause", data.get("w", "weapon"))))
