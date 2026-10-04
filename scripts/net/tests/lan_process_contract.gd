extends SceneTree
## Opt-in, two-process/two-machine ENet contract. No service discovery or production endpoint.
## Run host first, guest second through the owning host's serialized Godot wrapper:
## --script res://scripts/net/tests/lan_process_contract.gd -- --lan-probe-role=host
## --lan-probe-host=192.168.x.x --lan-probe-port=27897 --lan-probe-run=unique-id
## --lan-probe-output=/absolute/writable/report.json
## This is a deterministic ProbeGame, not a rendered InkGame/UI acceptance test.
const Probe=preload("res://scripts/net/tests/room_probe.gd")

class ProbeNetwork:
	extends InkNetwork
	signal qa_received(sender:String,data:Dictionary)
	func _receive(sender:String,data:Dictionary)->void:
		# Test-only coordination rides the same reliable ENet RPC/channel as room control.
		# Production InkNetwork remains unchanged and never accepts this packet kind.
		if str(data.get("k",""))=="qa":qa_received.emit(sender,data)
		else:super._receive(sender,data)

var role:String=""
var address:String="127.0.0.1"
var port:int=27897
var run_id:String="manual"
var output:String=""
var timeout:float=90.0
var game:Node3D
var network:ProbeNetwork
var elapsed:float=0.0
var match_time:float=0.0
var round_index:int=0
var round_live:bool=false
var statuses:Array=[]
var checks:Array=[]
var failures:Array[String]=[]
var rounds:Array=[]
var checkpoints:Dictionary={}
var go_count:int=0
var ended_count:int=0
var aborts:int=0
var abort_reasons:Array[String]=[]
var ready_sent:bool=false
var paint_sent:bool=false
var hit_sent:bool=false
var checkpoint_sent:bool=false
var published:bool=false
var result_received:bool=false
var published_at:float=-1.0
var result_at:float=-1.0
var returned_at:float=-1.0
var guest_returned:bool=false
var guest_round_two_ready:bool=false
var closed_at:float=-1.0
var aborted_at:float=-1.0
var done:bool=false

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		var parts:PackedStringArray=argument.trim_prefix("--").split("=",true,1)
		if parts.size()!=2:continue
		match parts[0]:
			"lan-probe-role":role=parts[1]
			"lan-probe-host":address=parts[1]
			"lan-probe-port":port=int(parts[1])
			"lan-probe-run":run_id=parts[1].validate_filename().substr(0,64)
			"lan-probe-output":output=parts[1]
			"lan-probe-timeout":timeout=clampf(float(parts[1]),30,180)
	if output.is_empty():output="user://lan-probe/%s-%s.json"%[run_id,role]
	_begin.call_deferred()

func _begin()->void:
	if role not in ["host","guest"] or port<1024 or port>65535:
		failures.append("Explicit --lan-probe-role=host|guest and valid UDP port are required");_finish();return
	seed(0x494e4b)
	game=Probe.ProbeGame.new();game.name="Game";root.add_child(game)
	network=ProbeNetwork.new();game.add_child(network);network.configure(game)
	network.qa_received.connect(_qa)
	network.status_changed.connect(func(message:String)->void:statuses.append({"t":snappedf(elapsed,.001),"message":message});print("LAN_STATUS ",role," ",message))
	network.lobby_changed.connect(_lobby)
	network.match_started.connect(_start)
	network.match_go.connect(_go)
	network.match_finished.connect(_result)
	network.match_ended.connect(_ended)
	network.match_aborted.connect(_aborted)
	var options:Dictionary={"transport":"enet","port":port,"address":address,"name":"LAN "+role,"weapon":"shooter" if role=="host" else "dualies","style":{"hair":2,"skin":3,"outfit":4,"eyes":2,"hat":0,"brows":1},"match":{"map":"tidewater","mode":"turf","bots":true,"duration":90,"difficulty":"normal","time":"day"}}
	var error:Error=network.host(options) if role=="host" else network.join(options)
	_check("socket opened",error==OK,{"error":error_string(error),"port":port,"address":address,"listen":"0.0.0.0" if role=="host" else "client"})
	if error!=OK:_finish();return
	print("LAN_PROCESS_READY role=",role," port=",port," report=",ProjectSettings.globalize_path(output))

func _lobby(data:Dictionary)->void:
	if done or network.phase!="lobby":return
	if role=="guest":
		if not ready_sent and network.peers.has(network.local_id):
			ready_sent=true;network.set_ready(true)
		return
	if round_index>=2:return
	if round_index==1 and not guest_returned:return
	var players:Array=data.get("players",[])
	var ready:bool=players.size()==2
	for player:Dictionary in players:
		if str(player.id)!=network.local_id and not bool(player.get("ready",false)):ready=false
	if ready:
		_check("round %d host start accepted"%(round_index+1),network.start())

func _start(options:Dictionary)->void:
	round_index+=1;round_live=false;match_time=0;paint_sent=false;hit_sent=false;checkpoint_sent=false;ready_sent=false
	_dispose_actors()
	game.state="intro";game.time_left=90;game.match_clock=0;game.paints.clear();game.events.clear()
	var teams:Array[int]=[0,0];var humans:int=0;var bots:int=0
	for entry:Dictionary in options.get("roster",[]):
		var actor:Node3D=Probe.ProbeActor.new();actor.name="Actor%d"%int(entry.nid);actor.team_id=int(entry.team);actor.weapon_id=str(entry.weapon)
		game.add_child(actor);actor.position=Vector3(int(entry.nid)*2,0,0);game.actors.append(actor)
		teams[actor.team_id]+=1
		if bool(entry.bot):bots+=1
		else:humans+=1
	_check("round %d source eight-slot roster"%round_index,game.actors.size()==8 and teams==[4,4] and humans==2 and bots==6,{"teams":teams,"humans":humans,"bots":bots,"roster":options.get("roster",[])})
	network.bind_match()

func _go()->void:
	go_count+=1;round_live=true;match_time=0;game.state="playing"
	if round_index==2 and role=="guest":_send_qa("round_two_ready",{"go":go_count,"phase":network.phase})

func _result(stats:Dictionary)->void:
	result_received=true;result_at=elapsed;game.state="results";round_live=false
	_check("guest receives source results",role=="guest" and str(stats.get("mode"))=="turf" and stats.get("players",[]).size()==8 and stats.get("percents",[])==[55.0,45.0],{"stats":stats})

func _ended()->void:
	ended_count+=1;returned_at=elapsed;round_live=false;ready_sent=false;game.state="lobby"
	var since_result:float=elapsed-(published_at if role=="host" else result_at)
	_check("normal results wait twelve seconds",since_result>=11.6 and since_result<15.0,{"elapsed":since_result})
	_check("normal result return emits no abort",aborts==0)
	_check("normal return retains room transport",network.active and network.phase=="lobby")
	_dispose_actors()
	if role=="guest":_send_qa("returned",{"elapsed":since_result,"ended":ended_count,"failures":failures.duplicate()})

func _qa(sender:String,data:Dictionary)->void:
	if str(data.get("run",""))!=run_id:return
	var message:String=str(data.get("message",""));var payload:Dictionary=data.get("payload",{})
	match message:
		"checkpoint":
			checkpoints[sender]=payload
			_check("peer first-round checkpoint received",int(payload.get("round",0))==1 and bool(payload.get("passed",false)),payload)
		"returned":
			if role=="host":
				guest_returned=true;_check("guest returned to same room",int(payload.get("ended",0))==1 and payload.get("failures",[]).is_empty(),payload)
		"round_two_ready":
			if role=="host":guest_round_two_ready=int(payload.get("go",0))==2 and str(payload.get("phase",""))=="match"

func _send_qa(message:String,payload:Dictionary)->void:
	network.send({"k":"qa","run":run_id,"message":message,"payload":payload})

func _process(dt:float)->bool:
	if done:return false
	elapsed+=dt
	if elapsed>timeout:
		failures.append("LAN process watchdog expired; peer not connected or lifecycle not completed");_finish();return false
	if network==null:return false
	if round_live:
		match_time+=dt;game.match_clock=match_time;game.time_left=maxf(0,90-match_time)
		for actor:Node3D in game.actors:
			if network.owns_actor(actor):
				var speed:float=2.0 if not bool(actor.get_meta("net_bot",false)) else .2*(int(actor.get_meta("net_slot",0))+1)
				actor.position.x+=dt*speed;actor.velocity=Vector3(speed,0,0)
	network.update(dt)
	if round_index==1 and round_live and network.phase=="match":
		if match_time>.5 and not paint_sent:
			paint_sent=true;var actor:Node3D=_human(network.local_id)
			network.record_paint(Vector3(30 if role=="host" else 34,0,17),Vector3.UP,1.5,int(actor.team_id),.42 if role=="host" else .52,{"kind":"trail","stretch":Vector3.RIGHT,"stretchAmt":2.4,"instant":true,"cosmetic":false})
		if match_time>1 and not hit_sent:
			hit_sent=true;var victim:Node3D=_other_human()
			_check("owned shooter dispatches remote hit",is_instance_valid(victim) and network.send_hit(_human(network.local_id),victim,35.0 if role=="host" else 27.0,"shooter"))
		if match_time>5 and not checkpoint_sent:
			checkpoint_sent=true;var summary:Dictionary=_checkpoint();rounds.append(summary);_send_qa("checkpoint",summary)
		if role=="host" and match_time>6 and checkpoint_sent and not checkpoints.is_empty() and not published:
			published=true;published_at=elapsed;game.state="results";round_live=false
			var players:Array=[]
			for actor:Node3D in game.actors:players.append({"id":actor.get_meta("net_slot",0),"team":actor.team_id,"weapon":actor.weapon_id,"hp":actor.hp,"turf":actor.turf_points})
			network.publish_result({"mode":"turf","winner":0,"percents":[55.0,45.0],"players":players})
			_check("host arms twelve-second return",network.phase=="results" and network._results_left==12.0)
	# A ready packet may have arrived before the test-only return acknowledgment.
	if role=="host" and round_index==1 and guest_returned and network.phase=="lobby":network.lobby.push(false)
	if role=="host" and round_index==2 and round_live and match_time>1.2 and guest_round_two_ready and closed_at<0:
		_check("both processes start second match",go_count==2 and ended_count==1)
		network.leave();closed_at=elapsed;round_live=false
		_check("host intentional close emits no abort",aborts==0 and not network.active and network.phase=="offline")
		_check("host close clears replication",network.replication.actors.is_empty() and network.peers.is_empty() and network.roster.is_empty())
		_dispose_actors()
	if role=="host" and closed_at>=0 and elapsed-closed_at>1.0:_finish()
	if role=="guest" and aborted_at>=0 and elapsed-aborted_at>.3:_finish()
	return false

func _checkpoint()->Dictionary:
	_check("match go received",go_count==1 and network.phase=="match")
	var actors:Array=[];var moved:bool=true
	for actor:Node3D in game.actors:
		var id:int=int(actor.get_meta("net_slot",-1));actors.append({"id":id,"owner":actor.get_meta("net_owner",""),"bot":actor.get_meta("net_bot",false),"x":actor.position.x,"hp":actor.hp})
		if not network.owns_actor(actor) and actor.position.x<=id*2+1:moved=false
	_check("remote owners move over real LAN",moved)
	var local:Node3D=_human(network.local_id);var other:Node3D=_other_human()
	_check("local owner receives exactly one remote damage",is_instance_valid(local) and absf(local.hp-(73.0 if role=="host" else 65.0))<.01,{"hp":local.hp if is_instance_valid(local) else -1})
	_check("remote victim HP snapshot converges",is_instance_valid(other) and absf(other.hp-(65.0 if role=="host" else 73.0))<.01,{"hp":other.hp if is_instance_valid(other) else -1})
	var paint_ok:bool=false
	for paint:Dictionary in game.paints:
		var extra:Dictionary=paint.extra
		if absf(float(paint.p.x)-(34 if role=="host" else 30))<.01 and str(extra.get("kind",""))=="trail" and extra.get("stretch") is Vector3 and absf(float(extra.get("stretchAmt",0))-2.4)<.01 and bool(extra.get("instant",false)) and not bool(extra.get("cosmetic",true)):paint_ok=true
	_check("remote paint carries exact appearance metadata",paint_ok,{"count":game.paints.size()})
	return {"round":1,"passed":failures.is_empty(),"actors":actors,"paints":game.paints.duplicate(true),"go":go_count,"failures":failures.duplicate()}

func _human(owner_id:String)->Node3D:
	for actor:Node3D in game.actors:
		if str(actor.get_meta("net_owner",""))==owner_id and not bool(actor.get_meta("net_bot",false)):return actor
	return null

func _other_human()->Node3D:
	for actor:Node3D in game.actors:
		if str(actor.get_meta("net_owner",""))!=network.local_id and not bool(actor.get_meta("net_bot",false)):return actor
	return null

func _aborted(reason:String)->void:
	aborts+=1;abort_reasons.append(reason);aborted_at=elapsed;round_live=false
	_check("guest interrupted match aborts once",role=="guest" and round_index==2 and go_count==2 and ended_count==1 and aborts==1)
	_check("disconnect transport offline",not network.active and network.phase=="offline" and network._enet==null and network.relay==null)
	_check("disconnect clears room and replication",network.peers.is_empty() and network.roster.is_empty() and network.replication.actors.is_empty())
	# The production consumer may safely dispose itself or call leave from this callback.
	network.leave();_dispose_actors();network._server_left()
	_check("stale close callback cannot abort twice",aborts==1)

func _dispose_actors()->void:
	if game==null:return
	for actor:Node in game.actors:
		if is_instance_valid(actor):actor.queue_free()
	game.actors.clear()

func _check(label:String,passed:bool,evidence:Dictionary={})->void:
	checks.append({"label":label,"passed":passed,"t":snappedf(elapsed,.001),"evidence":evidence})
	if not passed:failures.append(label);push_error("LAN_PROCESS_CONTRACT "+role+" "+label)

func _finish()->void:
	if done:return
	done=true
	var report:Dictionary={"passed":failures.is_empty(),"role":role,"run":run_id,"host_address":address,"port":port,"single_process":false,"actual_game":false,"real_enet":true,"os":OS.get_name(),"elapsed":elapsed,"rounds":rounds,"go_count":go_count,"result_received":result_received,"ended_count":ended_count,"aborts":aborts,"abort_reasons":abort_reasons,"peer_checkpoints":checkpoints,"checks":checks,"statuses":statuses,"failures":failures}
	var path:String=ProjectSettings.globalize_path(output);DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:report.passed=false;failures.append("Cannot write LAN probe report: "+error_string(FileAccess.get_open_error()))
	else:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("LAN_PROCESS_CONTRACT ",JSON.stringify(report))
	print("LAN_PROCESS_REPORT ",path)
	if network:network.leave()
	quit(0 if failures.is_empty() else 1)
