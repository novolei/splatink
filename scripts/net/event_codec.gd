class_name InkNetEventCodec
extends RefCounted

const ALLOWED := ["actor:jump", "superjump", "superjump:land", "special_activate", "special:use", "special:slam", "weapon:dodge", "weapon:shot", "weapon:flick", "weapon:beam", "weapon:fire", "splatted", "respawn", "explosion", "bomb:throw", "squid_in", "squid_out", "damage"]

static func pack(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in data:
		var value: Variant = data[key]
		if value is Node and is_instance_valid(value) and value.has_meta("net_slot"):
			result[str(key)] = {"n": int(value.get_meta("net_slot"))}
		elif value is Vector3:
			result[str(key)] = [snappedf(value.x, 0.01), snappedf(value.y, 0.01), snappedf(value.z, 0.01)]
		elif value is float and is_finite(value): result[str(key)] = snappedf(value, 0.001)
		elif value is int or value is bool: result[str(key)] = value
		elif value is String: result[str(key)] = value.substr(0, 64)
	return result

static func unpack(data: Dictionary, actors: Array) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in data:
		var value: Variant = data[key]
		if value is Dictionary and value.has("n"):
			var id: int = int(value.n)
			result[str(key)] = actors[id] if id >= 0 and id < actors.size() else null
		elif value is Array and value.size() == 3:
			result[str(key)] = Vector3(float(value[0]), float(value[1]), float(value[2]))
		elif value is String or value is bool or value is int or value is float:
			result[str(key)] = value
	return result

static func primary_id(data: Dictionary) -> int:
	var actor: Variant = data.get("actor", data.get("victim", {}))
	return int(actor.get("n", -1)) if actor is Dictionary else -1
