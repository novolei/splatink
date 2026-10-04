extends SceneTree
## Real native Game guest + real ENet probe host, one engine and two multiplayer roots.
## Root runs via tools/run_godot.ps1 --script ... -- --nonpersistent --benchmark-background.
const Game:=preload("res://scripts/ink_game.gd")
const Probe:=preload("res://scripts/net/tests/room_probe.gd")
var game:InkGame
var host_game:Node3D
var host_net:InkNetwork
var guest_net:InkNetwork
var apis:Array[SceneMultiplayer]=[]
var started:bool=false
var aborts:int=0
var reasons:Array[String]=[]
var failures:Array[String]=[]
var checks:Dictionary={}

func _initialize()->void:
	create_timer(35).timeout.connect(func()->void:failures.append("Actual Game abort fixture watchdog expired");_finish())
	_run.call_deferred()

func _run()->void:
	var host_root:=Node3D.new();host_root.name="AbortHost";root.add_child(host_root);_api(host_root)
	host_game=Probe.ProbeGame.new();host_game.name="Game";host_root.add_child(host_game)
	host_net=InkNetwork.new();host_game.add_child(host_net);host_net.configure(host_game)
	host_net.lobby_changed.connect(_lobby)
	host_net.match_started.connect(_start_host)
	host_net.match_go.connect(func()->void:host_game.state="playing")
	var guest_root:=Node3D.new();guest_root.name="AbortGuest";root.add_child(guest_root);_api(guest_root)
	game=Game.new();game.name="Game"
	# Set before add_child/_ready so settings and progression are never persisted.
	game._args={"nonpersistent":true,"benchmark-background":true,"page":"online"}
	guest_root.add_child(game);guest_net=game.network as InkNetwork
	guest_net.match_aborted.connect(func(reason:String)->void:aborts+=1;reasons.append(reason))
	checks.nonpersistent=game.ui.nonpersistent
	var before_profile:Dictionary=game._profile.duplicate(true)
	await create_timer(.7).timeout
	var options:Dictionary={"transport":"enet","port":27851,"name":"Host","weapon":"shooter","match":{"map":"cargo","mode":"turf","bots":false,"duration":60}}
	if host_net.host(options)!=OK:failures.append("Actual Game host socket failed");_finish();return
	options={"transport":"enet","port":27851,"address":"127.0.0.1","name":"Actual Guest","weapon":"dualies","style":game.ui.profile.duplicate(true)}
	if guest_net.join(options)!=OK:failures.append("Actual Game guest socket failed");_finish();return
	if not await _until(func()->bool:return guest_net.phase=="match" and game.state=="playing",10.0):
		failures.append("Actual Game never reached authority playing state");_finish();return
	var old_actors:Array=game.actors.duplicate()
	var old_stage:Node=game.stage
	checks.before={"state":game.state,"phase":guest_net.phase,"actors":old_actors.size(),"in_match":game.ui.in_match,"menu_hidden":not game.ui._menu.visible}
	if not game.ui.in_match or game.ui._menu.visible:failures.append("Actual connected Game did not expose the live HUD")
	host_net.leave()
	if not await _until(func()->bool:return aborts>0 and game.state=="menu" and game.ui.page=="online",7.0):failures.append("Actual Game did not tear down and open Online after host closure")
	await create_timer(.5).timeout
	var no_old_actors:bool=true
	for actor in old_actors:
		if is_instance_valid(actor) and game.actors.has(actor):no_old_actors=false
	checks.after={"state":game.state,"page":game.ui.page,"phase":guest_net.phase,"active":guest_net.active,"in_match":game.ui.in_match,"menu_visible":game.ui._menu.visible,"paused":game.paused,"mouse_visible":Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,"old_actors_removed":no_old_actors,"stage_replaced":not is_instance_valid(old_stage) or old_stage!=game.stage,"local_player_cleared":game.local_player==null,"progress_unchanged":game._profile==before_profile}
	if aborts!=1:failures.append("Actual Game abort signal count %d, expected one"%aborts)
	if game.ui.in_match or not game.ui._menu.visible:failures.append("Actual Game HUD/Menu remained in match mode")
	if game.paused or paused:failures.append("Actual Game pause remained armed")
	if guest_net.active or guest_net.phase!="offline":failures.append("Actual Game transport remained active")
	if not no_old_actors or game.local_player!=null:failures.append("Actual Game retained live match actors")
	if game._profile!=before_profile:failures.append("Disconnected match awarded progression")
	if not bool(checks.nonpersistent):failures.append("Actual Game did not set UI nonpersistent before _ready")
	# A stale duplicate disconnect callback must not restart the menu or award XP.
	guest_net._server_left()
	await process_frame
	if aborts!=1:failures.append("Duplicate server-close callback aborted twice")
	_finish()

func _api(branch:Node)->void:
	var api:=SceneMultiplayer.new();api.root_path=branch.get_path();set_multiplayer(api,branch.get_path());apis.append(api)

func _lobby(data:Dictionary)->void:
	if not guest_net:return
	if guest_net.peers.has(guest_net.local_id) and not bool(guest_net.peers[guest_net.local_id].ready):guest_net.set_ready(true)
	if started:return
	var ready:bool=data.get("players",[]).size()==2
	for player:Dictionary in data.get("players",[]):
		if str(player.id)!=host_net.local_id and not bool(player.ready):ready=false
	if ready:started=true;host_net.start()

func _start_host(options:Dictionary)->void:
	for entry:Dictionary in options.roster:
		var actor:Node3D=Probe.ProbeActor.new();actor.team_id=int(entry.team);actor.name="Actor%d"%int(entry.nid)
		host_game.add_child(actor);host_game.actors.append(actor)
	host_net.bind_match()

func _process(delta:float)->bool:
	if host_net:host_net.update(delta)
	# Guest Game advances its own network from its real physics lifecycle.
	if guest_net and guest_net.phase=="lobby" and guest_net.peers.has(guest_net.local_id) and not bool(guest_net.peers[guest_net.local_id].ready):guest_net.set_ready(true)
	return false

func _until(condition:Callable,timeout:float)->bool:
	var deadline:int=Time.get_ticks_msec()+roundi(timeout*1000)
	while not bool(condition.call()):
		if Time.get_ticks_msec()>=deadline:return false
		await process_frame
	return true

func _finish()->void:
	var report:Dictionary={"passed":failures.is_empty(),"single_process":true,"actual_game":true,"aborts":aborts,"reasons":reasons,"checks":checks,"failures":failures}
	var file:FileAccess=FileAccess.open("res://shots/net_abort_game.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("ABORT_GAME_FIXTURE ",JSON.stringify(report))
	if host_net:host_net.leave()
	if guest_net:guest_net.leave()
	quit(0 if failures.is_empty() else 1)
