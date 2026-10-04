class_name InkNetLobby
extends RefCounted

const WEAPONS := ["shooter", "dualies", "splatling", "roller", "slosher", "charger", "blaster"]
var network: InkNetwork
var _loaded: Dictionary = {}
var _start_timeout: float = 0

func receive(sender: String, data: Dictionary) -> void:
	match str(data.get("k", "")):
		"me":
			if not network.is_authority or network.phase != "lobby": return
			if not network.peers.has(sender):
				if network.peers.size() >= 8: return
				network.peers[sender] = {"name": "Fresh Kid", "weapon": "shooter", "style": {}, "team": network.peers.size() % 2, "ready": false}
			var player: Dictionary = network.peers[sender]
			if data.has("name"): player.name = str(data.name).substr(0, 16)
			if data.has("weapon") and str(data.weapon) in WEAPONS: player.weapon = str(data.weapon)
			if data.get("style") is Dictionary: player.style = sanitize_style(data.style as Dictionary)
			if data.has("ready"): player.ready = bool(data.ready)
			if data.has("team"):
				var wanted: int = clampi(int(data.team), 0, 1)
				var filled: int = 0
				for id: String in network.peers:
					if id != sender and int(network.peers[id].get("team", 0)) == wanted: filled += 1
				if filled < 4: player.team = wanted
			push()
		"lobby":
			if sender != network.host_id or network.phase not in ["lobby","connecting"] or not data.get("l") is Dictionary: return
			var value: Dictionary = data.l as Dictionary
			var players: Array = value.get("players", []) as Array
			if players.size() > 8: return
			network.peers.clear()
			for player: Dictionary in players:
				network.peers[str(player.get("id", ""))] = player
			network.match_options = value.duplicate(true)
			push(false)
		"start":
			if sender == network.host_id and network.phase == "lobby": _begin(data)
		"ready":
			if network.is_authority and str(data.get("id", "")) == str(network.match_options.get("id", "")): mark_ready(sender)
		"go":
			if sender == network.host_id and network.phase == "starting": _launch()

static func sanitize_style(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for pair: Array in [["hair", 8], ["skin", 9], ["outfit", 10], ["eyes", 8], ["hat", 4], ["brows", 4]]:
		result[str(pair[0])] = clampi(int(value.get(str(pair[0]), 0)), 0, int(pair[1]) - 1)
	return result

func push(send: bool = true) -> void:
	var options: Dictionary = network.match_options
	var players: Array = []
	var order: int = 0
	for id: String in network.peers:
		var player: Dictionary = network.peers[id].duplicate(true)
		player.id = id
		player.host = id == network.host_id
		player.you = id == network.local_id
		if not player.has("team"): player.team = order % 2
		players.append(player)
		order += 1
	var value: Dictionary = {"code": network.room_code, "host": network.host_id, "you": network.local_id, "transport": network.transport, "map": options.get("map", options.get("stage", "tidewater")), "time": options.get("time", options.get("time_of_day", "day")), "duration": int(options.get("duration", 180)), "difficulty": options.get("difficulty", "normal"), "palette": options.get("palette", 0), "mode": options.get("mode", "turf"), "bots": bool(options.get("bots", true)), "maxPlayers": 8, "players": players}
	if value.map == "cargo": value.bots = false
	network.lobby_changed.emit(value)
	if send and network.is_authority: network.send({"k": "lobby", "l": value})

func start() -> bool:
	if not network.active or not network.is_authority or network.phase != "lobby": return false
	var stage: String = str(network.match_options.get("map", network.match_options.get("stage", "tidewater")))
	var boss: bool = str(network.match_options.get("mode", "turf")) == "boss" and stage != "cargo"
	var bots: bool = bool(network.match_options.get("bots", true)) and stage != "cargo"
	var teams: Array[int] = [0, 0]
	for id: String in network.peers:
		var player: Dictionary = network.peers[id]
		if id != network.local_id and not bool(player.get("ready", false)):
			network.status_changed.emit("Waiting for every kid to ready up")
			return false
		teams[clampi(int(player.get("team", 0)), 0, 1)] += 1
	if not boss and (teams[0] > 4 or teams[1] > 4):
		network.status_changed.emit("Each crew can have up to four kids")
		return false
	if stage == "cargo" and (teams[0] == 0 or teams[1] == 0):
		network.status_changed.emit("Cargo Terminal needs at least one human on each team")
		return false
	var roster: Array = []
	for team: int in (1 if boss else 2):
		var slot: int = 0
		for id: String in network.peers:
			var player: Dictionary = network.peers[id]
			if not boss and int(player.get("team", 0)) != team: continue
			roster.append({"nid": roster.size(), "slot": slot, "owner": id, "bot": false, "team": team, "name": player.name, "weapon": player.weapon, "style": player.style})
			slot += 1
		if bots:
			while slot < (8 if boss else 4):
				roster.append({"nid": roster.size(), "slot": slot, "owner": network.local_id, "bot": true, "team": team, "name": "Squidkid %d" % (roster.size() + 1), "weapon": WEAPONS[slot % WEAPONS.size()], "style": {"hair": randi_range(0, 7), "skin": randi_range(0, 8), "outfit": randi_range(0, 9), "eyes": randi_range(0, 7), "hat": 0, "brows": 0}})
				slot += 1
	var config: Dictionary = network.match_options.duplicate(true)
	var time: String = str(config.get("time_of_day", config.get("time", "day")))
	config.merge({"k": "start", "roster": roster, "map": stage, "stage": stage, "mapId": stage, "time": time, "time_of_day": time, "host": network.local_id, "id": InkRelayLink.room_code(), "wait_for_network": true}, true)
	if network.relay != null: network.relay.lock_room(true)
	network.send(config)
	_begin(config)
	return true

func _begin(config: Dictionary) -> void:
	var roster: Array = config.get("roster", []) as Array
	if roster.is_empty() or roster.size() > 8: return
	for actor: Dictionary in roster:
		if int(actor.get("nid", -1)) < 0 or int(actor.get("nid", 8)) > 7 or not str(actor.get("weapon", "")) in WEAPONS: return
	network.roster = roster.duplicate(true)
	network.match_options = config.duplicate(true)
	network.phase = "starting"
	_loaded.clear()
	_start_timeout = 12.0
	var options: Dictionary = config.duplicate(true)
	options["time_of_day"] = config.get("time", config.get("time_of_day", "day"))
	options["local_slot"] = 0
	options["local_team"] = 0
	for player: Dictionary in roster:
		if str(player.owner) == network.local_id and not bool(player.bot):
			options.local_slot = int(player.nid)
			options.local_team = int(player.team)
			options.weapon = str(player.weapon)
			options.style = player.style
	network.match_started.emit(options)

func mark_ready(id: String) -> void:
	if network.phase != "starting" or not network.is_authority: return
	_loaded[id] = true
	for player: Dictionary in network.roster:
		if not bool(player.bot) and network.peers.has(str(player.owner)) and not _loaded.has(str(player.owner)): return
	network.send({"k": "go", "id": network.match_options.get("id", "")})
	_launch()

func _launch() -> void:
	network.phase = "match"
	_start_timeout = 0
	network.match_go.emit()
	network.status_changed.emit("GO! · %d kids connected" % network.peers.size())

func disconnected(id: String) -> void:
	if network.phase == "match" or network.phase == "starting":
		var humans_only: bool = str(network.match_options.get("map", "")) == "cargo"
		for entry: Dictionary in network.roster:
			if str(entry.owner) == id:
				entry.owner = network.host_id
				entry.bot = not humans_only
				if int(entry.nid) < network.replication.actors.size():
					var actor: Node = network.replication.actors[int(entry.nid)]
					actor.set_meta("net_owner", network.host_id)
					actor.set_meta("net_bot", not humans_only)
					if humans_only:
						actor.set("alive", false)
						(actor as Node3D).visible = false
		if network.is_authority: network.send({"k": "own", "map": network.roster})
		if network.phase == "starting": mark_ready(network.local_id)
	else:
		push()
	network.status_changed.emit("A kid left the room" if not network.is_authority else "Room host retained; disconnected slot updated")

func update(delta: float) -> void:
	if _start_timeout <= 0 or not network.is_authority: return
	_start_timeout -= delta
	if _start_timeout <= 0 and network.phase == "starting":
		network.send({"k": "go", "id": network.match_options.get("id", "")})
		_launch()
