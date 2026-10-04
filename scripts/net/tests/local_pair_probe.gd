extends SceneTree
## One Godot process, two independently rooted SceneMultiplayer APIs and real ENet sockets.
const Probe := preload("res://scripts/net/tests/room_probe.gd")
var games: Array = []
var nets: Array = []
var apis: Array[SceneMultiplayer] = []
var elapsed: float = 0
var started: bool = false
var go: Array[bool] = [false, false]
var sent: Array[bool] = [false, false]
var hit_sent: bool = false
var left: bool = false
var failures: Array[String] = []
var statuses: Array = []
var snapshot: Array = []
var results_sent:bool=false
var results_received:bool=false
var ended:Array[bool]=[false,false]
var returned:bool=false
var climb_started:bool=false
var climb_finished:bool=false
var aborts:Array[int]=[0,0]
var jump_started:bool=false
var jump_flight:bool=false
var jump_checked:bool=false
var jump_cleared:bool=false

func _initialize() -> void:
	call_deferred("begin")

func begin() -> void:
	for index: int in 2:
		var game: Node3D = Probe.ProbeGame.new()
		game.name = "Host" if index == 0 else "Guest"
		root.add_child(game)
		var api := SceneMultiplayer.new()
		api.root_path = game.get_path()
		set_multiplayer(api, game.get_path())
		apis.append(api)
		var net := InkNetwork.new()
		game.add_child(net)
		net.configure(game)
		games.append(game)
		nets.append(net)
		var own: int = index
		net.status_changed.connect(func(message: String) -> void: statuses.append({"side": own, "message": message}))
		net.match_started.connect(func(options: Dictionary) -> void: _start(own, options))
		net.match_go.connect(func() -> void: go[own] = true; games[own].state = "playing")
		net.lobby_changed.connect(func(data: Dictionary) -> void: _lobby(own, data))
		net.match_finished.connect(func(stats:Dictionary)->void:
			if own==1:results_received=stats.get("mode")=="turf"
		)
		net.match_ended.connect(func()->void:ended[own]=true)
		net.match_aborted.connect(func(_reason:String)->void:aborts[own]+=1)
	var options: Dictionary = {"transport": "enet", "port": 27843, "name": "Host", "weapon": "shooter", "match": {"map": "cargo", "mode": "turf", "bots": false, "duration": 30}}
	var result: Error = nets[0].host(options)
	if result != OK: failures.append("Host failed: " + error_string(result)); finish(); return
	options = {"transport": "enet", "port": 27843, "address": "127.0.0.1", "name": "Guest", "weapon": "dualies"}
	result = nets[1].join(options)
	if result != OK: failures.append("Join failed: " + error_string(result)); finish()

func _lobby(index: int, data: Dictionary) -> void:
	if index == 1 and nets[1].peers.has(nets[1].local_id) and not bool(nets[1].peers[nets[1].local_id].ready):
		nets[1].set_ready(true)
	if index != 0 or started: return
	var ready: bool = data.get("players", []).size() == 2
	for player: Dictionary in data.get("players", []):
		if str(player.id) != nets[0].local_id and not bool(player.ready): ready = false
	if ready: started = true; nets[0].start()

func _start(index: int, options: Dictionary) -> void:
	for entry: Dictionary in options.roster:
		var actor: Node3D = Probe.ProbeActor.new()
		actor.team_id = int(entry.team)
		actor.name = "Actor%d" % int(entry.nid)
		games[index].add_child(actor)
		actor.position = Vector3(int(entry.nid) * 2, 0, 0)
		games[index].actors.append(actor)
	nets[index].bind_match()

func _process(delta: float) -> bool:
	elapsed += delta
	for index: int in nets.size():
		var net: InkNetwork = nets[index]
		net.update(delta)
		if net.phase != "match" or games[index].actors.size() != 2: continue
		for actor: Node3D in games[index].actors:
			if net.owns_actor(actor): actor.position.x += delta * 2; actor.velocity = Vector3(2, 0, 0)
		if not sent[index]:
			sent[index] = true
			net.record_paint(Vector3(3, 0, 3), Vector3.UP, 1.5, index, .42, {"kind": "trail", "stretch": Vector3(1, 0, 0), "stretchAmt": 2.4, "instant": true, "cosmetic": false})
	if elapsed > 3 and nets.size() == 2 and not hit_sent and games[0].actors.size() == 2:
		hit_sent = true
		nets[0].send_hit(games[0].actors[0], games[0].actors[1], 35, "shooter")
	if elapsed>2.2 and not jump_started:
		jump_started=true
		for index:int in nets.size():
			for actor:Node3D in games[index].actors:
				if nets[index].owns_actor(actor):actor.super_jump_state={"phase":"charge"}
	if elapsed>2.8 and not jump_flight:
		jump_flight=true
		for index:int in nets.size():
			for actor:Node3D in games[index].actors:
				if nets[index].owns_actor(actor):actor.super_jump_state={"phase":"flight"}
	if elapsed>3.3 and not jump_checked:
		jump_checked=true
		for index:int in nets.size():
			for actor:Node3D in games[index].actors:
				if not nets[index].owns_actor(actor) and str(actor.super_jump_state.get("phase",""))!="flight":failures.append("Side %d did not expose remote super-jump BUSY/flight"%index)
	if elapsed>3.6 and not jump_cleared:
		jump_cleared=true
		for index:int in nets.size():
			for actor:Node3D in games[index].actors:
				if nets[index].owns_actor(actor):actor.super_jump_state={}
	if elapsed>3.6 and not climb_started:
		climb_started=true
		for index:int in nets.size():
			for actor:Node3D in games[index].actors:
				if nets[index].owns_actor(actor):actor.climbing=true;actor.form="squid"
	if elapsed>4.6 and not climb_finished:
		climb_finished=true
		for index:int in nets.size():
			for actor:Node3D in games[index].actors:
				if nets[index].owns_actor(actor):actor.climbing=false;actor.form="kid"
	if elapsed>6 and not results_sent:
		results_sent=true
		_capture()
		nets[0].publish_result({"mode":"turf","winner":0,"percents":[55,45],"players":[]})
		if nets[0].phase!="results" or nets[0]._results_left!=12.0:failures.append("Host results countdown was not armed at 12 seconds")
	if elapsed>17 and not returned:
		if nets[0].phase!="results":failures.append("Room returned before the 12-second host deadline")
		returned=true
	if elapsed>18.8 and not left:
		left=true
		if not results_received:failures.append("Guest did not receive results")
		if not ended[0] or not ended[1] or nets[0].phase!="lobby" or nets[1].phase!="lobby":failures.append("Host deadline did not return both peers to the room")
		if nets[0].return_to_lobby():failures.append("Repeated return_to_lobby accepted after ending")
		nets[1].leave()
	if elapsed > 20:
		if nets.size() == 2 and nets[0].peers.size() != 1: failures.append("Host did not process guest disconnect")
		if aborts!=[0,0]:failures.append("Normal result return/intentional guest leave emitted a match abort")
		finish()
	return false

func _capture() -> void:
	if not started: failures.append("Match did not start")
	for index: int in 2:
		if not go[index]: failures.append("Side %d did not receive match_go" % index)
		var game: Node = games[index]
		if game.paints.is_empty(): failures.append("Side %d did not replay remote paint" % index)
		else:
			var extra: Dictionary = game.paints[0].extra
			if str(extra.get("kind")) != "trail" or not extra.get("stretch") is Vector3 or absf(float(extra.get("stretchAmt", 0)) - 2.4) > .01 or not bool(extra.get("instant")): failures.append("Paint metadata did not survive replication")
		var actors: Array = []
		for actor: Node3D in game.actors:
			actors.append({"id": actor.get_meta("net_slot", -1), "owner": actor.get_meta("net_owner", ""), "x": actor.position.x, "hp": actor.hp})
			if not nets[index].owns_actor(actor) and actor.position.x <= float(int(actor.get_meta("net_slot")) * 2) + 1: failures.append("Side %d remote actor did not move" % index)
			if not nets[index].owns_actor(actor) and not actor.super_jump_state.is_empty():failures.append("Side %d retained remote BUSY after landing"%index)
		if index == 1 and game.actors.size() == 2 and game.actors[1].hp > 65: failures.append("Guest owner did not receive damage")
		var climb_events:int=game.events.count("actor:climb")
		if climb_events!=2:failures.append("Side %d replayed %d climb transitions, expected attach+detach once each"%[index,climb_events])
		snapshot.append({"side": index, "go": go[index], "paints": game.paints.size(), "actors": actors,"climb_events":climb_events})

func finish() -> void:
	var report: Dictionary = {"passed": failures.is_empty(), "single_process": true, "snapshots": snapshot, "statuses": statuses, "results_received":results_received,"room_returned":ended,"aborts":aborts,"failures": failures}
	var path: String = ProjectSettings.globalize_path("res://shots/net_local_pair.json")
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(report, "\t")); file.close()
	print("LOCAL_PAIR_PROBE " + JSON.stringify(report))
	for net: InkNetwork in nets: net.leave()
	quit(0 if failures.is_empty() else 1)
