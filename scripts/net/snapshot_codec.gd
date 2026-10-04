class_name InkSnapshotCodec
extends RefCounted
## Actor state retains the 21-number INKWAVE packet layout and flag bit assignments.

static func pack(actor: Node3D, nid: int) -> Array:
	var flags: int = 1 if bool(actor.get("alive")) else 0
	if str(actor.get("form")) == "squid": flags |= 2
	if bool(actor.get("submerged")): flags |= 4
	if bool(actor.get("climbing")): flags |= 8
	var grounded:bool=bool(actor.call("is_grounded")) if actor.has_method("is_grounded") else actor is CharacterBody3D and (actor as CharacterBody3D).is_on_floor()
	if grounded:flags|=16
	if bool(actor.get("rolling")): flags |= 256
	if bool(actor.get("firing")): flags |= 4096
	if not str(actor.get("special_active")).is_empty(): flags |= 8192
	var jump_state:Variant=actor.get("super_jump_state")
	if jump_state is Dictionary and not jump_state.is_empty():flags|=32768 if str(jump_state.get("phase","charge"))=="flight" else 16384
	if float(actor.get("invuln")) > 0: flags |= 262144
	var position: Vector3 = actor.call("visual_position") as Vector3 if actor.has_method("visual_position") else actor.global_position
	var velocity: Vector3 = actor.get("velocity") as Vector3
	return [nid, snappedf(position.x, 0.01), snappedf(position.y, 0.01), snappedf(position.z, 0.01), snappedf(velocity.x, 0.01), snappedf(velocity.y, 0.01), snappedf(velocity.z, 0.01), snappedf(actor.rotation.y, 0.001), snappedf(float(actor.get("aim_yaw")), 0.001), snappedf(float(actor.get("aim_pitch")), 0.001), flags, roundi(float(actor.get("hp"))), roundi(float(actor.get("ink"))), roundi(float(actor.get("special_charge"))), snappedf(float(actor.get("charge")), 0.01), roundi(float(actor.get("turf_points"))), int(actor.get_meta("net_teleport", 0)), 0, 0, 0, 0]

static func valid(sample: Array) -> bool:
	if sample.size() < 21 or sample.size() > 32:
		return false
	for index: int in 21:
		if not sample[index] is int and not sample[index] is float:
			return false
		if not is_finite(float(sample[index])):
			return false
	return int(sample[0]) >= 0 and int(sample[0]) < 8 and absf(float(sample[1])) < 512 and absf(float(sample[2])) < 512 and absf(float(sample[3])) < 512 and float(sample[11]) >= 0 and float(sample[11]) <= 100 and float(sample[12]) >= 0 and float(sample[12]) <= 100

static func position_of(sample: Array) -> Vector3:
	return Vector3(float(sample[1]), float(sample[2]), float(sample[3]))

static func velocity_of(sample: Array) -> Vector3:
	return Vector3(float(sample[4]), float(sample[5]), float(sample[6]))

static func interpolate(a: Array, b: Array, blend: float, duration: float) -> Dictionary:
	var t: float = clampf(blend, 0, 1)
	var square: float = t * t
	var cube: float = square * t
	var position: Vector3 = (2 * cube - 3 * square + 1) * position_of(a) + (cube - 2 * square + t) * duration * velocity_of(a) + (-2 * cube + 3 * square) * position_of(b) + (cube - square) * duration * velocity_of(b)
	if (int(a[10]) & 16) != 0 or (int(b[10]) & 16) != 0:
		position.y = clampf(position.y, minf(float(a[2]), float(b[2])) - 0.02, maxf(float(a[2]), float(b[2])) + 0.02)
	return {"position": position, "velocity": velocity_of(a).lerp(velocity_of(b), t), "yaw": lerp_angle(float(a[7]), float(b[7]), t), "aim_yaw": lerp_angle(float(a[8]), float(b[8]), t), "aim_pitch": lerpf(float(a[9]), float(b[9]), t), "flags": int(a[10]), "hp": float(b[11]), "ink": lerpf(float(a[12]), float(b[12]), t), "special": lerpf(float(a[13]), float(b[13]), t), "charge": lerpf(float(a[14]), float(b[14]), t), "points": float(b[15])}

static func apply(actor: Node3D, state: Dictionary) -> void:
	actor.global_position = state.position as Vector3
	if actor.has_method("visual_position"):
		actor.set("smooth_y",0.0)
		actor.set("smooth_y_velocity",0.0)
	actor.rotation.y = float(state.yaw)
	actor.set("velocity", state.velocity)
	actor.set("aim_yaw", float(state.aim_yaw))
	actor.set("aim_pitch", float(state.aim_pitch))
	actor.set("hp", float(state.hp))
	actor.set("ink", float(state.ink))
	actor.set("special_charge", float(state.special))
	actor.set("charge", float(state.charge))
	actor.set("turf_points", float(state.points))
	var flags: int = int(state.flags)
	if actor.has_method("set_remote_grounded"):actor.call("set_remote_grounded",(flags&16)!=0)
	actor.set("alive", (flags & 1) != 0)
	actor.visible = (flags & 1) != 0
	actor.set("form", "squid" if (flags & 2) != 0 else "kid")
	actor.set("submerged", (flags & 4) != 0)
	actor.set("climbing", (flags & 8) != 0)
	actor.set("rolling", (flags & 256) != 0)
	actor.set("firing", (flags & 4096) != 0)
	if actor.get("super_jump_state") is Dictionary:
		actor.set("super_jump_state",{"phase":"flight" if (flags&32768)!=0 else "charge","net":true} if (flags&49152)!=0 else {})
	actor.set("invuln",.1 if (flags&262144)!=0 else 0.0)
	actor.set("special_active",str(InkRules.weapon(str(actor.get("weapon_id"))).get("special","slam")) if (flags&8192)!=0 else "")
