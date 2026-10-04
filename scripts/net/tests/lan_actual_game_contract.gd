extends SceneTree
## Opt-in real InkGame on each physical endpoint. Root owns all serialized engine execution.
## --script res://scripts/net/tests/lan_actual_game_contract.gd -- --lan-game-role=host|guest
## --lan-game-host=<host-address> --lan-game-port=27898 --lan-game-run=<unique-id>
## --lan-game-output=<absolute-writable-report.json> --nonpersistent --benchmark-background
const Game=preload("res://scripts/ink_game.gd")

class QuietBots:
	extends InkBots
	# The real Actor.tick/controller/physics stay active. Only autonomous attacks are quieted.
	func command_for(actor, _dt:float)->Dictionary:
		return {"move":Vector3.ZERO,"aim_dir":Vector3(sin(actor.aim_yaw),0,cos(actor.aim_yaw)),"fire":false,"sub":false,"swim":false,"jump":false,"special":false}

class Coordinator:
	extends Node
	signal received(sender:int,data:Dictionary)
	@rpc("any_peer","call_remote","reliable",0)
	func checkpoint(data:Dictionary)->void:
		received.emit(multiplayer.get_remote_sender_id(),data)

var role:String=""
var address:String="127.0.0.1"
var port:int=27898
var run_id:String="manual"
var output:String=""
var timeout:float=120.0
var game:InkGame
var network:InkNetwork
var coordinator:Coordinator
var elapsed:float=0.0
var playing_time:float=0.0
var round_index:int=0
var go_count:int=0
var ended_count:int=0
var aborts:int=0
var abort_reasons:Array[String]=[]
var statuses:Array=[]
var checks:Array=[]
var failures:Array[String]=[]
var rounds:Array=[]
var peer_checkpoint:Dictionary={}
var profile_before:Dictionary={}
var profile_after_results:Dictionary={}
var persistence_before:Dictionary={}
var old_actors:Array=[]
var old_stage:Node
var initial_positions:Dictionary={}
var remote_paint:Dictionary={}
var local_move_peak:float=0.0
var remote_move_peak:float=0.0
var local_hp_min:float=100.0
var remote_hp_min:float=100.0
var ready_sent:bool=false
var playing_seen:bool=false
var move_pressed:bool=false
var move_released:bool=false
var paint_sent:bool=false
var hit_sent:bool=false
var checkpoint_sent:bool=false
var published:bool=false
var results_seen:bool=false
var result_received:bool=false
var result_at:float=-1.0
var returned_at:float=-1.0
var return_verified:bool=false
var guest_returned:bool=false
var guest_second_playing:bool=false
var closed_at:float=-1.0
var aborted_at:float=-1.0
var abort_verified:bool=false
var done:bool=false
var native_framing:Array=[]
var native_locomotion_required:bool=false
var native_locomotion:Array=[]
var native_zstd_required:bool=false

func _initialize()->void:
	native_locomotion_required=OS.get_cmdline_user_args().has("--native-locomotion-mm")
	native_zstd_required=OS.get_cmdline_user_args().has("--native-tick-zstd")
	for argument:String in OS.get_cmdline_user_args():
		var parts:PackedStringArray=argument.trim_prefix("--").split("=",true,1)
		if parts.size()!=2:continue
		match parts[0]:
			"lan-game-role":role=parts[1]
			"lan-game-host":address=parts[1]
			"lan-game-port":port=int(parts[1])
			"lan-game-run":run_id=parts[1].validate_filename().substr(0,64)
			"lan-game-output":output=parts[1]
			"lan-game-timeout":timeout=clampf(float(parts[1]),40,240)
	if output.is_empty():output="user://lan-actual-game/%s-%s.json"%[run_id,role]
	_begin.call_deferred()

func _begin()->void:
	if role not in ["host","guest"] or port<1024 or port>65535:
		failures.append("Explicit --lan-game-role=host|guest and valid isolated UDP port required");_finish();return
	seed(0x494e4b)
	root.size=Vector2i(1280,720);root.content_scale_size=Vector2i(1280,720)
	persistence_before=_persistence_state()
	coordinator=Coordinator.new();coordinator.name="LanGameCoordinator";root.add_child(coordinator);coordinator.received.connect(_qa)
	game=Game.new();game.name="Game"
	# Before _ready: no user progression or settings loads/saves; no fixture/UI shortcut mode.
	game._args={"nonpersistent":true,"benchmark-background":true,"page":"online"}
	if native_locomotion_required:game._args["native-locomotion-mm"]=true
	root.add_child(game);network=game.network as InkNetwork
	network._native_inbox.measure_cadence=true
	_check("native compression adapter matches explicit endpoint flag",bool(network.native_tick_metrics().zstd_enabled)==native_zstd_required)
	game.apply_settings({"quality":"low"});_quiet_bots()
	profile_before=game._profile.duplicate(true)
	_check("real Game and UI nonpersistent before ready",game._args.has("nonpersistent") and game.ui.nonpersistent and not game.ui.fixture_mode)
	network.status_changed.connect(func(message:String)->void:statuses.append({"t":snappedf(elapsed,.001),"message":message});print("LAN_GAME_STATUS ",role," ",message))
	network.lobby_changed.connect(_lobby)
	network.match_started.connect(_started)
	network.match_go.connect(func()->void:go_count+=1)
	network.match_finished.connect(_result)
	network.match_ended.connect(_ended)
	network.match_aborted.connect(_aborted)
	# Let the real deferred Online page/wipe settle before using the production room entry point.
	await create_timer(.8).timeout
	var options:Dictionary={"transport":"enet","port":port,"address":address,"name":"Actual "+role,"weapon":"shooter" if role=="host" else "dualies","style":{"hair":2,"skin":3,"outfit":4,"eyes":2,"hat":0,"brows":1},"match":{"map":"tidewater","mode":"turf","bots":true,"duration":90,"difficulty":"normal","time":"day","palette":0}}
	var error:Error=network.host(options) if role=="host" else network.join(options)
	_check("real Game ENet socket opened",error==OK,{"error":error_string(error),"listen":"0.0.0.0" if role=="host" else "client","port":port,"address":address})
	if error!=OK:_finish();return
	print("LAN_ACTUAL_GAME_READY role=",role," port=",port," report=",ProjectSettings.globalize_path(output))

func _quiet_bots()->void:
	var quiet:QuietBots=QuietBots.new();quiet.configure(game,"normal");game.bots=quiet

func _lobby(data:Dictionary)->void:
	if done or network.phase!="lobby":return
	if role=="guest":
		if round_index==0 or return_verified:_ready_guest()
		return
	if round_index>=2 or round_index==1 and (not return_verified or not guest_returned):return
	var players:Array=data.get("players",[])
	var ready:bool=players.size()==2
	for player:Dictionary in players:
		if str(player.id)!=network.local_id and not bool(player.get("ready",false)):ready=false
	if ready:_check("round %d production room start accepted"%(round_index+1),network.start())

func _ready_guest()->void:
	if not ready_sent and network.phase=="lobby" and network.peers.has(network.local_id):
		ready_sent=true;network.set_ready(true)

func _started(options:Dictionary)->void:
	# Parent production start_match listener ran first, including real Stage/Actor/Network.bind_match.
	round_index+=1;playing_seen=false;playing_time=0;ready_sent=false;move_pressed=false;move_released=false;paint_sent=false;hit_sent=false;checkpoint_sent=false
	initial_positions.clear();local_move_peak=0;remote_move_peak=0;local_hp_min=100;remote_hp_min=100;remote_paint.clear()
	_quiet_bots()
	var teams:Array[int]=[0,0];var humans:int=0;var bots:int=0;var real_actors:int=0;var source_physics:int=0
	for actor:Node3D in game.actors:
		teams[int(actor.team_id)]+=1
		if actor is InkActor:real_actors+=1
		if actor.get("source_physics")!=null:source_physics+=1
		if bool(actor.get_meta("net_bot",false)):bots+=1
		else:humans+=1;initial_positions[str(actor.get_meta("net_owner",""))]=actor.global_position
	_check("round %d eight real source Actors"%round_index,real_actors==8 and source_physics==8 and teams==[4,4] and humans==2 and bots==6,{"teams":teams,"humans":humans,"bots":bots,"source_physics":source_physics})
	_check("round %d real baked Stage and weapon systems"%round_index,game.stage is InkStage and game.stage.stage_id=="tidewater" and game.stage.level_queries!=null and game.projectiles is InkWeapons)
	_check("round %d production HUD active, menu hidden"%round_index,game.ui.in_match and not game.ui._menu.visible,{"state":game.state,"phase":network.phase,"page":game.ui.page})
	_check("round %d production roster binds local human"%round_index,is_instance_valid(game.local_player) and game.local_player==_human(network.local_id) and options.get("roster",[]).size()==8)
	if native_locomotion_required:_check_native_locomotion("round_start",false)
	if round_index==2:old_actors=game.actors.duplicate();old_stage=game.stage

func _process(dt:float)->bool:
	if done:return false
	elapsed+=dt
	if elapsed>timeout:
		failures.append("Actual Game LAN watchdog expired; lifecycle or peer checkpoints incomplete");_finish();return false
	if game==null or network==null:return false
	# InkGame owns its network/physics tick. This harness never double-polls InkNetwork.update.
	if network.active and network.phase=="match" and game.state=="playing":
		if not playing_seen:
			playing_seen=true;playing_time=0
			_check("round %d authoritative playing uses follow camera"%round_index,str(game.camera_rig.get("mode"))=="follow" and game.ui.in_match and not game.ui._menu.visible,{"camera":game.camera_rig.get("mode"),"go":go_count})
			if round_index==2 and role=="guest":_send_qa("second_playing",{"go":go_count,"phase":network.phase,"hud":game.ui.in_match})
		playing_time+=dt
		if round_index==1:_exercise_round_one()
		elif role=="host" and guest_second_playing and playing_time>1.2 and closed_at<0:_close_host()
	if round_index==1 and game.state=="results" and not results_seen:
		results_seen=true;result_at=elapsed;Input.action_release("move_forward")
		_check("real results UI entered",game.ui.page=="results" and not game.ui.in_match and game.ui._menu.visible)
		_check("completed match awards memory progression once",int(game._profile.matches)==int(profile_before.matches)+1)
		profile_after_results=game._profile.duplicate(true)
	if returned_at>=0 and not return_verified and elapsed-returned_at>.6:_verify_return()
	if role=="host" and round_index==1 and return_verified and guest_returned and network.phase=="lobby":network.lobby.push(false)
	if role=="guest" and return_verified and network.phase=="lobby":_ready_guest()
	if aborted_at>=0 and not abort_verified and elapsed-aborted_at>.8:_verify_abort()
	if role=="host" and closed_at>=0 and elapsed-closed_at>1.2:_finish()
	if role=="guest" and abort_verified:_finish()
	return false

func _exercise_round_one()->void:
	var local:InkActor=game.local_player;var other:InkActor=_other_human()
	if not is_instance_valid(local) or not is_instance_valid(other):return
	local_move_peak=maxf(local_move_peak,_horizontal_distance(local.global_position,initial_positions.get(network.local_id,local.global_position)))
	remote_move_peak=maxf(remote_move_peak,_horizontal_distance(other.global_position,initial_positions.get(str(other.get_meta("net_owner","")),other.global_position)))
	local_hp_min=minf(local_hp_min,local.hp);remote_hp_min=minf(remote_hp_min,other.hp)
	if playing_time>.2 and not move_pressed:move_pressed=true;Input.action_press("move_forward")
	if playing_time>1.25 and not move_released:move_released=true;Input.action_release("move_forward")
	if playing_time>1.5 and not paint_sent:
		paint_sent=true;var point:Vector3=_paint_point();var extra:Dictionary={"seed":.42 if role=="host" else .52,"kind":"trail","stretch":Vector3.RIGHT,"stretchAmt":2.4,"instant":true,"cosmetic":false}
		var area:float=game.paint_splat(point,Vector3.UP,1.5,local.team_id,extra);local.add_turf(area)
		_check("local real Stage paint scores CPU cells",area>0 and game.sample_ink(point)==local.team_id,{"point":[point.x,point.y,point.z],"area":area,"team":local.team_id})
		_send_qa("paint",{"point":[point.x,point.y,point.z],"team":local.team_id})
	if playing_time>2.0 and not hit_sent:
		hit_sent=true;var before_hp:float=other.hp
		# Call the real Actor damage ownership guard; the remote owner must accept this packet.
		other.damage(35.0 if role=="host" else 27.0,local,"shooter")
		_check("proxy damage waits for remote victim owner",is_equal_approx(other.hp,before_hp),{"proxy_hp":other.hp,"before":before_hp})
	if playing_time>4.5 and not checkpoint_sent:
		checkpoint_sent=true;var checkpoint:Dictionary=_checkpoint();rounds.append(checkpoint);_send_qa("checkpoint",checkpoint)
	if role=="host" and playing_time>5.4 and checkpoint_sent and not peer_checkpoint.is_empty() and not published:
		published=true
		# Native result assembly, XP, podium and packet path are all production functions.
		game._show_results()
		_check("production host arms source twelve-second room return",network.phase=="results" and absf(network._results_left-12)<.01)

func _paint_point()->Vector3:
	# Deterministically choose a large paintable source floor, away from protected spawn cells.
	var selected:Vector3=Vector3.ZERO;var best_area:float=-1.0
	for face:Dictionary in game.stage.faces:
		if not bool(face.turf) or Vector3(face.n).y<.9:continue
		var point:Vector3=face.origin+face.u*float(face.su)*.5+face.v*float(face.sv)*.5
		if (role=="guest" and point.x<0) or (role=="host" and point.x>=0):continue
		var middle_u:int=floori(float(face.nu)*.5);var middle_v:int=floori(float(face.nv)*.5)
		var cell:int=int(face.grid)+middle_v*int(face.nu)+middle_u
		if game.stage.dead[cell]!=0:continue
		var area:float=float(face.su)*float(face.sv)
		if area>best_area:best_area=area;selected=point
	return selected+Vector3.UP*.02

func _checkpoint()->Dictionary:
	_check("real local controller moves source Actor",local_move_peak>.3,{"distance":local_move_peak})
	_check("remote real Actor snapshots move over LAN",remote_move_peak>.3,{"distance":remote_move_peak})
	var expected_local:float=73.0 if role=="host" else 65.0;var expected_remote:float=65.0 if role=="host" else 73.0
	_check("real owner receives exactly one remote damage",absf(local_hp_min-expected_local)<.01,{"minimum_hp":local_hp_min,"expected":expected_local})
	_check("real remote damage snapshot converges",absf(remote_hp_min-expected_remote)<.01,{"minimum_hp":remote_hp_min,"expected":expected_remote})
	var paint_ok:bool=false
	if remote_paint.has("point"):
		var p:Array=remote_paint.point;paint_ok=game.sample_ink(Vector3(float(p[0]),float(p[1]),float(p[2])))==int(remote_paint.team)
	_check("remote paint reaches actual Stage CPU ink",paint_ok,remote_paint)
	_check("live production HUD survives network startup",game.ui.in_match and not game.ui._menu.visible and game.actors.size()==8)
	var framing:Dictionary=_check_native_framing()
	var motion:Dictionary=_check_native_locomotion("playing_checkpoint",true) if native_locomotion_required else {}
	return {"round":round_index,"passed":failures.is_empty(),"local_move":local_move_peak,"remote_move":remote_move_peak,"local_min_hp":local_hp_min,"remote_min_hp":remote_hp_min,"coverage":[game.stage.coverage().x,game.stage.coverage().y],"go":go_count,"native_framing":framing,"native_locomotion":motion,"failures":failures.duplicate()}

func _check_native_locomotion(point:String,require_queries:bool)->Dictionary:
	# Observe production avatars; never instantiate a matcher or replace their animation provider.
	var actors:Array=[]
	var providers_ok:bool=game.actors.size()==8
	var queries_ok:bool=game.actors.size()==8
	for actor:InkActor in game.actors:
		var state:Dictionary=actor.avatar.motion_state if is_instance_valid(actor.avatar) else {}
		var profile:Dictionary=actor.avatar.profile_metrics if is_instance_valid(actor.avatar) else {}
		var active:bool=int(profile.get("native_mm_active",0))==1
		var provider_ok:bool=active and str(state.get("provider",""))=="native MMAnimationLibrary exact contiguous search" and str(state.get("native_error",""))=="" and int(state.get("native_bucket_poses",0))==234 and state.get("upper_body_masked",false)==true
		var query_ok:bool=int(state.get("native_queries",0))>0 and int(state.get("native_poses_evaluated",0))==234
		providers_ok=providers_ok and provider_ok
		queries_ok=queries_ok and query_ok
		actors.append({"slot":int(actor.get_meta("net_slot",-1)),"owner":str(actor.get_meta("net_owner","")),"bot":actor.get_meta("net_bot",false)==true,"local":actor.is_local,"weapon":actor.weapon_id,"active":active,"provider":str(state.get("provider","")),"native_queries":int(state.get("native_queries",0)),"native_bucket_poses":int(state.get("native_bucket_poses",0)),"native_poses_evaluated":int(state.get("native_poses_evaluated",0)),"upper_body_masked":state.get("upper_body_masked",false)==true,"native_error":str(state.get("native_error",""))})
	var evidence:Dictionary={"round":round_index,"point":point,"requested":native_locomotion_required,"queries_required":require_queries,"actors":actors,"providers_ok":providers_ok,"queries_ok":queries_ok}
	_check("round %d eight real native lower-body providers (%s)"%[round_index,point],providers_ok,evidence)
	if require_queries:_check("round %d eight native providers queried actual weapon buckets"%round_index,queries_ok,evidence)
	native_locomotion.append(evidence)
	return evidence

func _check_native_framing()->Dictionary:
	var inbox:Dictionary=network._native_inbox.debug_state()
	var remote:InkActor=_other_human()
	var timeline:Variant=network.replication._timelines.get(str(remote.get_meta("net_owner",""))) if is_instance_valid(remote) else null
	var small_receive:bool=timeline!=null and not timeline.samples.is_empty()
	var sender_metrics:Dictionary=network.native_tick_metrics()
	var evidence:Dictionary={"round":round_index,"sent_native_frame":network._native_frame,"budget_error":network._native_budget_error,"inbox":inbox,"sender_metrics":sender_metrics,"received_actor_timeline":small_receive,"fragmented_sender":role=="host" and not native_zstd_required,"compressed_sender":role=="host" and native_zstd_required,"lossless_encoding":_encoding_metrics()}
	_check("native framing sends source ticks without budget failure",not network._native_budget_error and network._native_frame>0,evidence)
	# Host receives one guest actor; guest receives seven host-owned rows in the selected native format.
	var correct_path:bool=small_receive
	if role=="guest":correct_path=int(inbox.get("compressed_completed",0))>0 if native_zstd_required else int(inbox.completed)>0
	_check("native receive exercises the correct small or reconstructed frame path",correct_path,evidence)
	if native_zstd_required:
		_check("compressed host frames and small guest frames have separate telemetry",int(sender_metrics.sent_compressed)>0 and int(inbox.small_completed)>0 if role=="host" else int(sender_metrics.received_compressed)>0 and int(sender_metrics.sent_small)>0,evidence)
		_check("compressed receive respects authorization and advertised decode cap",int(inbox.authorized_senders)<=8 and int(inbox.peak_decode_bytes)<=65536,evidence)
	_check("native pending metadata and frames remain bounded",int(inbox.pending)<=16 and int(inbox.buffered_metadata_bytes)<=16*65536,evidence)
	native_framing.append(evidence)
	return evidence

func _encoding_metrics()->Array:
	# Standalone entropy-codec timing; selected live transport is reported separately.
	var rows:Array=[]
	for actor:InkActor in game.actors:
		if network.owns_actor(actor):rows.append(InkSnapshotCodec.pack(actor,int(actor.get_meta("net_slot",-1))))
	var actual:Dictionary={"k":"t","ts":float(Time.get_ticks_msec())/1000.0,"a":rows}
	var stats:Dictionary=actual.duplicate();stats.st=network.replication.pack_stats(network.is_authority)
	if network.is_authority:stats.c=[game.state,game.time_left]
	var result:Array=[]
	for sample:Dictionary in [actual,stats]:
		var raw:PackedByteArray=var_to_bytes(sample);var compressed:PackedByteArray=PackedByteArray();var encode_usec:int=0;var decode_usec:int=0;var same:bool=true
		for iteration:int in 10:
			var began:int=Time.get_ticks_usec();compressed=raw.compress(FileAccess.COMPRESSION_ZSTD);encode_usec+=Time.get_ticks_usec()-began
			began=Time.get_ticks_usec();var decoded:PackedByteArray=compressed.decompress(raw.size(),FileAccess.COMPRESSION_ZSTD);decode_usec+=Time.get_ticks_usec()-began
			same=same and decoded==raw and bytes_to_var(decoded)==sample
		var wrapper:Dictionary={"k":"t","ts":sample.ts,"_nz":[InkNetwork.NATIVE_ZSTD_TICK.VERSION,0,raw.size(),hash(raw),hash(compressed),compressed]}
		var compressed_wire:int=InkNetwork.NATIVE_TICK.wire_size(network.local_id,wrapper)
		var metric:Dictionary={"actors":rows.size(),"with_stats":sample.has("st"),"raw_variant_bytes":raw.size(),"source_wire_budget_bytes":InkNetwork.NATIVE_TICK.wire_size(network.local_id,sample),"zstd_bytes":compressed.size(),"zstd_wire_budget_bytes":compressed_wire,"fits_one_packet":compressed_wire<=InkNetwork.NATIVE_TICK.BUDGET,"encode_mean_usec":encode_usec/10.0,"decode_mean_usec":decode_usec/10.0,"exact_bytes_restored":same,"transport_changed":native_zstd_required,"live_zstd_enabled":native_zstd_required,"timing_includes_receive_guards":false}
		_check("measured compression restores every source tick byte",same,metric);result.append(metric)
	return result

func _result(stats:Dictionary)->void:
	result_received=true
	_check("guest receives eight real result rows",role=="guest" and str(stats.get("mode",""))=="turf" and stats.get("players",[]).size()==8 and game.state=="results")

func _ended()->void:
	ended_count+=1;returned_at=elapsed;ready_sent=false
	_check("normal results return after twelve seconds",result_at>=0 and elapsed-result_at>=11.5 and elapsed-result_at<16,{"seconds":elapsed-result_at})
	_check("normal result return retains ENet without abort",network.active and network.phase=="lobby" and aborts==0)
	if native_zstd_required:_check("normal return clears compressed sender authorization and timelines",int(network._native_inbox.debug_state().authorized_senders)==0 and int(network._native_inbox.debug_state().senders)==0)

func _verify_return()->void:
	return_verified=true
	_check("real Game returns to live lobby UI",game.state=="menu" and game.ui.page=="lobby" and not game.ui.in_match and game.ui._menu.visible and game.local_player==null and game.actors.is_empty(),{"state":game.state,"page":game.ui.page,"actors":game.actors.size()})
	_check("normal return preserves awarded memory XP",game._profile==profile_after_results)
	if role=="guest":_send_qa("returned",{"ended":ended_count,"passed":failures.is_empty(),"failures":failures.duplicate()})

func _close_host()->void:
	_check("second real match starts on both endpoints",go_count==2 and ended_count==1 and guest_second_playing)
	network.leave();closed_at=elapsed
	_check("intentional host close emits no abort",aborts==0 and not network.active and network.phase=="offline")
	# Local explicit cleanup uses production menu teardown; interrupted round gets no XP.
	game.quit_to_menu();_quiet_bots()
	_check("intentional host cleanup awards no aborted XP",game._profile==profile_after_results)
	_check("intentional host closes room and replication",network.peers.is_empty() and network.roster.is_empty() and network.replication.actors.is_empty())
	if native_zstd_required:_check("intentional host close clears compressed sender authorization",int(network._native_inbox.debug_state().authorized_senders)==0)

func _aborted(reason:String)->void:
	aborts+=1;abort_reasons.append(reason);aborted_at=elapsed;Input.action_release("move_forward")
	_check("guest interrupted real match aborts once",role=="guest" and round_index==2 and go_count==2 and ended_count==1 and aborts==1)
	_check("abrupt disconnect clears transport and replication",not network.active and network.phase=="offline" and network._enet==null and network.peers.is_empty() and network.roster.is_empty() and network.replication.actors.is_empty())
	if native_zstd_required:_check("guest disconnect clears compressed sender authorization",int(network._native_inbox.debug_state().authorized_senders)==0)
	# The production Game consumer is CONNECT_DEFERRED; do not preempt its cleanup here.

func _verify_abort()->void:
	abort_verified=true
	var old_removed:bool=true
	for actor in old_actors:
		if is_instance_valid(actor) and game.actors.has(actor):old_removed=false
	_check("actual disconnect opens Online and restores mouse",game.state=="menu" and game.ui.page=="online" and not game.ui.in_match and game.ui._menu.visible and Input.mouse_mode==Input.MOUSE_MODE_VISIBLE,{"state":game.state,"page":game.ui.page})
	_check("actual disconnect disposes old actors and Stage",old_removed and game.local_player==null and (not is_instance_valid(old_stage) or game.stage!=old_stage))
	_check("actual disconnect clears pause and preserves memory XP",not game.paused and not paused and game._profile==profile_after_results)
	network.leave();network._server_left()
	_check("reentrant leave and stale close remain one abort",aborts==1)

func _qa(sender:int,data:Dictionary)->void:
	if str(data.get("run",""))!=run_id or not network.active:return
	if role=="guest" and sender!=1:return
	if role=="host" and not str(sender) in network.peers:return
	var payload:Dictionary=data.get("payload",{})
	match str(data.get("message","")):
		"paint":remote_paint=payload
		"checkpoint":
			peer_checkpoint=payload;_check("peer real Game checkpoint passed",int(payload.get("round",0))==1 and bool(payload.get("passed",false)),payload)
		"returned":
			if role=="host":guest_returned=true;_check("guest actual Game returned to same room",int(payload.get("ended",0))==1 and bool(payload.get("passed",false)),payload)
		"second_playing":
			if role=="host":guest_second_playing=int(payload.get("go",0))==2 and bool(payload.get("hud",false)) and str(payload.get("phase",""))=="match"

func _send_qa(message:String,payload:Dictionary)->void:
	var packet:Dictionary={"run":run_id,"message":message,"payload":payload}
	for peer:int in coordinator.multiplayer.get_peers():coordinator.checkpoint.rpc_id(peer,packet)

func _human(owner_id:String)->InkActor:
	for actor:InkActor in game.actors:
		if str(actor.get_meta("net_owner",""))==owner_id and not bool(actor.get_meta("net_bot",false)):return actor
	return null

func _other_human()->InkActor:
	for actor:InkActor in game.actors:
		if str(actor.get_meta("net_owner",""))!=network.local_id and not bool(actor.get_meta("net_bot",false)):return actor
	return null

func _horizontal_distance(a:Vector3,b:Vector3)->float:return Vector2(a.x-b.x,a.z-b.z).length()

func _check(label:String,passed:bool,evidence:Dictionary={})->void:
	checks.append({"label":label,"passed":passed,"t":snappedf(elapsed,.001),"evidence":evidence})
	if not passed:failures.append(label);push_error("LAN_ACTUAL_GAME "+role+" "+label)

func _persistence_state()->Dictionary:
	var state:Dictionary={}
	# Record only hashes/existence, never include user settings contents in reports.
	for path:String in ["user://splatink_ui.cfg","user://splatink_progress.cfg"]:
		state[path]=FileAccess.get_sha256(path) if FileAccess.file_exists(path) else "absent"
	return state

func _finish()->void:
	if done:return
	done=true;Input.action_release("move_forward")
	if not persistence_before.is_empty():_check("user settings and progression files unchanged",_persistence_state()==persistence_before)
	var report:Dictionary={"passed":failures.is_empty(),"role":role,"run":run_id,"host_address":address,"port":port,"single_process":false,"actual_game":true,"real_enet":true,"os":OS.get_name(),"display":DisplayServer.get_name(),"fixture_bot_ai":"quiet","paint_damage":"injected through real Game.paint_splat and Actor.damage","elapsed":elapsed,"rounds":rounds,"go_count":go_count,"result_received":result_received,"ended_count":ended_count,"aborts":aborts,"abort_reasons":abort_reasons,"profile_before":profile_before,"profile_after_results":profile_after_results,"peer_checkpoint":peer_checkpoint,"native_framing":native_framing,"native_tick_zstd":{"requested":native_zstd_required,"default_enabled":false},"native_locomotion":{"requested":native_locomotion_required,"checkpoints":native_locomotion},"checks":checks,"statuses":statuses,"failures":failures}
	var path:String=ProjectSettings.globalize_path(output);DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file:FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:report.passed=false;failures.append("Cannot write Actual Game LAN report: "+error_string(FileAccess.get_open_error()))
	else:file.store_string(JSON.stringify(report,"\t"));file.close()
	print("LAN_ACTUAL_GAME_CONTRACT ",JSON.stringify(report));print("LAN_ACTUAL_GAME_REPORT ",path)
	if network:network.leave()
	quit(0 if failures.is_empty() else 1)
