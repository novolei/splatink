extends SceneTree
## One engine, real ENet sockets, independently rooted multiplayer APIs.
## Root runs through tools/run_godot.ps1; this script never starts another process.
const Probe := preload("res://scripts/net/tests/room_probe.gd")
const CASES:Array[String]=["starting","match","results","lobby","intentional_guest_leave"]
var games:Array=[]
var nets:Array=[]
var apis:Array[SceneMultiplayer]=[]
var scenario:String=""
var started:bool=false
var aborts:Array[int]=[0,0]
var reasons:Array=[]
var failures:Array[String]=[]
var cases:Array=[]

func _initialize()->void:
	create_timer(45).timeout.connect(func()->void:failures.append("Connection loss probe watchdog expired");_finish())
	_run.call_deferred()

func _run()->void:
	for case_index:int in CASES.size():
		scenario=CASES[case_index];started=false;aborts=[0,0];reasons=[]
		var first_failure:int=failures.size()
		_make_pair(case_index)
		var options:Dictionary={"transport":"enet","port":27845+case_index,"name":"Host","weapon":"shooter","match":{"map":"cargo","mode":"turf","bots":false,"duration":30}}
		if nets[0].host(options)!=OK:failures.append(scenario+": host socket failed");await _dispose();continue
		options={"transport":"enet","port":27845+case_index,"address":"127.0.0.1","name":"Guest","weapon":"dualies"}
		if nets[1].join(options)!=OK:failures.append(scenario+": guest socket failed");await _dispose();continue
		var expected:String="lobby" if scenario in ["lobby","intentional_guest_leave"] else "starting" if scenario=="starting" else "match"
		var arrived:bool=await _until(func()->bool:return nets[0].phase==expected and nets[1].phase==expected and nets[0].peers.size()==2,7.0)
		if not arrived:failures.append(scenario+": room never reached "+expected)
		if arrived and scenario=="results":
			nets[0].publish_result({"mode":"turf","winner":0,"percents":[55,45],"players":[]})
			arrived=await _until(func()->bool:return nets[1].phase=="results",3.0)
			if not arrived:failures.append("results: guest never received result packet")
		var phase_before:Array=[nets[0].phase,nets[1].phase]
		if scenario=="intentional_guest_leave":nets[1].leave()
		else:nets[0].leave()
		if scenario in ["starting","match","results"]:
			if not await _until(func()->bool:return aborts[1]>0,5.0):failures.append(scenario+": abrupt host closure did not abort guest")
		else:
			if not await _until(func()->bool:return not nets[1].active if scenario=="lobby" else nets[0].peers.size()==1,5.0):failures.append(scenario+": room closure was not observed")
		# Allow close callbacks already queued by ENet to expose duplicate signals.
		await create_timer(.35).timeout
		var expected_aborts:int=1 if scenario in ["starting","match","results"] else 0
		if aborts[0]!=0:failures.append(scenario+": intentional host leave emitted an abort")
		if aborts[1]!=expected_aborts:failures.append(scenario+": guest abort count %d, expected %d"%[aborts[1],expected_aborts])
		if nets[1].active or nets[1].phase!="offline":failures.append(scenario+": guest transport remained active")
		if expected_aborts==1 and games[1].state!="menu":failures.append(scenario+": disposal callback did not return guest to menu")
		cases.append({"scenario":scenario,"phases_before":phase_before,"aborts":aborts.duplicate(),"reasons":reasons.duplicate(true),"guest_offline":not nets[1].active and nets[1].phase=="offline","passed":failures.size()==first_failure})
		await _dispose()
	_finish()

func _make_pair(case_index:int)->void:
	for side:int in 2:
		var game:Node3D=Probe.ProbeGame.new()
		game.name="Loss%d_%s"%[case_index,"Host" if side==0 else "Guest"]
		root.add_child(game)
		var api:=SceneMultiplayer.new()
		api.root_path=game.get_path();set_multiplayer(api,game.get_path());apis.append(api)
		var net:=InkNetwork.new();game.add_child(net);net.configure(game)
		games.append(game);nets.append(net)
		var own:int=side
		net.lobby_changed.connect(func(data:Dictionary)->void:_lobby(own,data))
		net.match_started.connect(func(options:Dictionary)->void:_start(own,options))
		net.match_go.connect(func()->void:games[own].state="playing")
		net.match_aborted.connect(func(reason:String)->void:
			aborts[own]+=1;reasons.append({"side":own,"reason":reason})
			# Disposal is deliberately reentrant, matching the real Game teardown.
			nets[own].leave();games[own].state="menu"
		)

func _lobby(side:int,data:Dictionary)->void:
	if scenario in ["lobby","intentional_guest_leave"]:return
	if side==1 and nets[1].peers.has(nets[1].local_id) and not bool(nets[1].peers[nets[1].local_id].ready):nets[1].set_ready(true)
	if side!=0 or started:return
	var ready:bool=data.get("players",[]).size()==2
	for player:Dictionary in data.get("players",[]):
		if str(player.id)!=nets[0].local_id and not bool(player.ready):ready=false
	if ready:started=true;nets[0].start()

func _start(side:int,options:Dictionary)->void:
	for entry:Dictionary in options.roster:
		var actor:Node3D=Probe.ProbeActor.new();actor.team_id=int(entry.team);actor.name="Actor%d"%int(entry.nid)
		games[side].add_child(actor);games[side].actors.append(actor)
	if scenario!="starting" or side==0:nets[side].bind_match()

func _process(delta:float)->bool:
	for net:InkNetwork in nets:net.update(delta)
	return false

func _until(condition:Callable,timeout:float)->bool:
	var deadline:int=Time.get_ticks_msec()+roundi(timeout*1000)
	while not bool(condition.call()):
		if Time.get_ticks_msec()>=deadline:return false
		await process_frame
	return true

func _dispose()->void:
	for net:InkNetwork in nets:net.leave()
	for game:Node3D in games:game.queue_free()
	nets.clear();games.clear();apis.clear()
	await process_frame

func _finish()->void:
	var report:Dictionary={"passed":failures.is_empty(),"single_process":true,"transport":"real ENet localhost","cases":cases,"failures":failures}
	var file:FileAccess=FileAccess.open("res://shots/net_connection_loss.json",FileAccess.WRITE)
	if file!=null:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("CONNECTION_LOSS_PROBE ",JSON.stringify(report))
	for net:InkNetwork in nets:net.leave()
	quit(0 if failures.is_empty() else 1)
