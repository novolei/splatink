extends SceneTree
## Run twice, sequentially launch host then client. This harness never launches another engine.

class ProbeActor extends Node3D:
	var team_id: int = 0
	var is_local: bool = false
	var weapon_id: String = "shooter"
	var hp: float = 100
	var ink: float = 100
	var special_charge: float = 0
	var charge: float = 0
	var turf_points: float = 0
	var alive: bool = true
	var form: String = "kid"
	var submerged: bool = false
	var climbing: bool = false
	var rolling: bool = false
	var firing: bool = false
	var aim_yaw: float = 0
	var aim_pitch: float = 0
	var invuln: float = 0
	var special_active: String = ""
	var super_jump_state:Dictionary={}
	var velocity: Vector3 = Vector3.ZERO
	var splats: int = 0
	var deaths: int = 0
	var avatar: Node = null
	func damage(amount: float, _attacker: Node, _cause: String) -> void:
		hp -= amount
	func trigger(_kind: String) -> void:
		pass

class ProbeGame extends Node3D:
	var boss: Node = null
	var actors: Array = []
	var state: String = "intro"
	var time_left: float = 180
	var match_clock: float = 0
	var paints: Array = []
	var events: Array = []
	func paint_splat(position: Vector3, normal: Vector3, radius: float, team: int, extra: Dictionary = {}) -> float:
		paints.append({"p": position, "n": normal, "r": radius, "team": team, "seed": extra.get("seed", 0), "extra": extra.duplicate(true)})
		return 1.0
	func notify_event(kind: String, _data: Dictionary) -> void:
		events.append(kind)

var network: InkNetwork
var game: ProbeGame
var role: String = "client"
var output: String = "res://shots/net_client.json"
var elapsed: float = 0
var sent: bool = false
var hit_sent: bool = false
var started: bool = false
var got_go: bool = false
var statuses: Array[String] = []
var failures: Array[String] = []
var args: Dictionary = {}

func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		var parts: PackedStringArray = argument.trim_prefix("--").split("=", true, 1)
		args[parts[0]] = parts[1] if parts.size() > 1 else true
	role = str(args.get("role", "client"))
	output = str(args.get("out", "res://shots/net_%s.json" % role))
	call_deferred("begin")

func begin() -> void:
	game = ProbeGame.new()
	game.name = "Probe"
	root.add_child(game)
	network = InkNetwork.new()
	game.add_child(network)
	network.configure(game)
	network.status_changed.connect(func(message: String) -> void: statuses.append(message))
	network.lobby_changed.connect(_lobby)
	network.match_started.connect(_start)
	network.match_go.connect(func() -> void: got_go = true; game.state = "playing")
	var options: Dictionary = {"transport": str(args.get("transport", "enet")), "port": int(args.get("port", 27841)), "address": str(args.get("address", "127.0.0.1")), "name": "Probe " + role, "weapon": "shooter", "match": {"map": "cargo", "mode": "turf", "bots": false, "duration": 30}}
	if args.has("relay"): options.relay = str(args.relay)
	if args.has("code"): options.code = str(args.code)
	var result: Error = network.host(options) if role == "host" else network.join(options)
	if result != OK: failures.append(error_string(result)); finish()

func _lobby(data: Dictionary) -> void:
	if role == "host":
		var ready: bool = data.get("players", []).size() == 2
		for player: Dictionary in data.get("players", []):
			if str(player.id) != network.local_id and not bool(player.ready): ready = false
		if ready and not started: started = true; network.start()
	elif network.peers.has(network.local_id) and not bool(network.peers[network.local_id].ready):
		network.set_ready(true)

func _start(options: Dictionary) -> void:
	started = true
	for entry: Dictionary in options.roster:
		var actor := ProbeActor.new()
		actor.team_id = int(entry.team)
		actor.name = "Actor%d" % int(entry.nid)
		game.add_child(actor)
		actor.position = Vector3(int(entry.nid) * 2, 0, 0)
		game.actors.append(actor)
	network.bind_match()

func _process(delta: float) -> bool:
	elapsed += delta
	if network != null: network.update(delta)
	if network != null and network.phase == "match" and game.actors.size() == 2:
		for actor: ProbeActor in game.actors:
			if network.owns_actor(actor): actor.position.x += delta * 2.0; actor.velocity = Vector3(2, 0, 0)
		if not sent:
			sent = true
			network.record_paint(Vector3(3, 0, 3), Vector3.UP, 1.5, 0 if role == "host" else 1, 0.42)
		if elapsed > 3 and not hit_sent and role == "host":
			hit_sent = true
			network.send_hit(game.actors[0], game.actors[1], 35.0, "shooter")
	if elapsed > 8: finish()
	return false

func finish() -> void:
	if not started: failures.append("Match never started")
	if not got_go: failures.append("Match go was not received")
	if game.paints.is_empty(): failures.append("Remote paint was not replayed")
	var states: Array = []
	for actor: ProbeActor in game.actors:
		states.append({"id": actor.get_meta("net_slot", -1), "owner": actor.get_meta("net_owner", ""), "x": actor.position.x, "hp": actor.hp})
		if not network.owns_actor(actor) and actor.position.x <= float(int(actor.get_meta("net_slot")) * 2): failures.append("Remote actor did not move")
	if role == "client" and game.actors.size() == 2 and game.actors[1].hp > 65: failures.append("Owner did not receive hit")
	var report: Dictionary = {"passed": failures.is_empty(), "role": role, "code": network.room_code, "go": got_go, "paints": game.paints.size(), "actors": states, "statuses": statuses, "failures": failures}
	var path: String = ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("ROOM_PROBE " + JSON.stringify(report))
	network.leave()
	quit(0 if failures.is_empty() else 1)
