class_name InkRules
extends RefCounted

## Native rules read the exported JavaScript tuning without changing units or IDs.
static var _catalog: Dictionary = {}

static func catalog() -> Dictionary:
	if not _catalog.is_empty():
		return _catalog
	for path in ["res://data/config.json", "res://assets/data/config.json"]:
		if FileAccess.file_exists(path):
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_catalog = parsed
				return _catalog
	return {}

static func section(key: String) -> Dictionary:
	var data: Dictionary = catalog()
	var result = data.get(key, data.get(key.to_lower(), {}))
	return result if result is Dictionary else {}

static func player(key: String, fallback: float) -> float:
	return float(section("PLAYER").get(key, fallback))

static func weapon(id: String) -> Dictionary:
	var weapons: Dictionary = section("WEAPONS")
	return weapons.get(id, weapons.get("shooter", {}))

static func emit_event(game: Node, kind: String, data: Dictionary = {}) -> void:
	if is_instance_valid(game) and game.has_method("notify_event"):
		game.call("notify_event", kind, data)
