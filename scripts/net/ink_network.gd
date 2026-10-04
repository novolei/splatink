class_name InkNetwork
extends Node
## Native ENet rooms and original INKWAVE WebSocket relay rooms share one ownership boundary.

signal match_started(options: Dictionary)
signal match_go
signal match_finished(stats: Dictionary)
signal lobby_changed(data: Dictionary)
signal status_changed(message: String)
signal emote_received(player_id:String,emote_name:String)
signal match_ended
signal match_state_changed(state:String)
signal match_aborted(reason:String)

var active: bool = false
var is_authority: bool = true
var local_id: String = "1"
var host_id: String = "1"
var room_code: String = ""
var transport: String = "enet"
var phase: String = "offline"
var roster: Array = []
var peers: Dictionary = {}
var match_options: Dictionary = {}
var game: Node
var relay: InkRelayLink
var lobby: InkNetLobby
var replication: InkNetReplication
var applying: bool = false
var _enet: ENetMultiplayerPeer
var _identity: Dictionary = {}
var _results_left:float=-1.0
var _abort_emitted:bool=false
const NATIVE_TICK=preload("res://scripts/net/native_tick_codec.gd")
const NATIVE_INBOX=preload("res://scripts/net/native_tick_inbox.gd")
const NATIVE_ZSTD_TICK=preload("res://scripts/net/native_zstd_tick_codec.gd")
const NATIVE_ZSTD_INBOX=preload("res://scripts/net/native_zstd_tick_inbox.gd")
# Both endpoints must explicitly opt in. Relay rooms never use the native codecs.
var _native_zstd_enabled:bool=OS.get_cmdline_user_args().has("--native-tick-zstd")
var _native_inbox=NATIVE_ZSTD_INBOX.new() if _native_zstd_enabled else NATIVE_INBOX.new()
var _native_frame:int=0
var _native_budget_error:bool=false
var _native_sent_ticks:int=0
var _native_sent_small:int=0
var _native_sent_compressed:int=0
var _native_sent_fragmented:int=0
var _native_sent_parts:int=0
var _native_max_parts:int=0

func configure(controller: Node) -> void:
	game = controller
	name = "Network"
	process_mode = Node.PROCESS_MODE_ALWAYS
	lobby = InkNetLobby.new()
	lobby.network = self
	replication = InkNetReplication.new()
	replication.network = self
	if not multiplayer.peer_connected.is_connected(_peer_connected):
		multiplayer.peer_connected.connect(_peer_connected)
		multiplayer.peer_disconnected.connect(_peer_disconnected)
		multiplayer.connected_to_server.connect(_connected)
		multiplayer.connection_failed.connect(_failed)
		multiplayer.server_disconnected.connect(_server_left)

func host(options: Dictionary) -> Error:
	leave()
	_abort_emitted=false
	_identity = _profile(options)
	match_options = (options.get("match", options) as Dictionary).duplicate(true)
	transport = str(options.get("transport", "enet"))
	if transport == "relay":
		return _connect_relay(options, true)
	_enet = ENetMultiplayerPeer.new()
	var result: Error = _enet.create_server(clampi(int(options.get("port", 27840)), 1024, 65535), 7, 3)
	if result != OK:
		status_changed.emit("Could not host room: %s" % error_string(result))
		return result
	multiplayer.multiplayer_peer = _enet
	local_id = "1"
	host_id = "1"
	is_authority = true
	active = true
	phase = "lobby"
	room_code = InkRelayLink.room_code()
	peers[local_id] = _identity
	lobby.push()
	status_changed.emit("LAN room open · UDP %d" % int(options.get("port", 27840)))
	return OK

func join(options: Dictionary) -> Error:
	leave()
	_abort_emitted=false
	_identity = _profile(options)
	transport = str(options.get("transport", "enet"))
	if transport == "relay":
		return _connect_relay(options, false)
	_enet = ENetMultiplayerPeer.new()
	var result: Error = _enet.create_client(str(options.get("address", "127.0.0.1")), clampi(int(options.get("port", 27840)), 1024, 65535), 3)
	if result != OK:
		status_changed.emit("Could not join room: %s" % error_string(result))
		return result
	multiplayer.multiplayer_peer = _enet
	is_authority = false
	active = true
	phase = "connecting"
	status_changed.emit("Connecting to native room…")
	return OK

func _profile(options: Dictionary) -> Dictionary:
	var look: Dictionary = options.get("style", {}) as Dictionary
	return {"name": str(options.get("name", look.get("name", "Fresh Kid"))).substr(0, 16), "style": look, "weapon": str(options.get("weapon", "shooter")), "ready": false, "team": 0}

func _connect_relay(options: Dictionary, create: bool) -> Error:
	relay = InkRelayLink.new()
	relay.control_received.connect(_relay_control)
	relay.message_received.connect(_receive)
	relay.closed.connect(_connection_lost)
	room_code = InkRelayLink.room_code() if create else str(options.get("code", "")).to_upper()
	var result: Error = relay.connect_room(room_code, str(_identity.name), create, str(options.get("relay", InkRelayLink.PRODUCTION_RELAY)))
	active = result == OK
	phase = "connecting" if active else "offline"
	is_authority = create
	status_changed.emit("Connecting to relay room %s…" % room_code if active else "Enter a valid five-character room code")
	return result

func _relay_control(data: Dictionary) -> void:
	match str(data.get("t", "")):
		"welcome":
			local_id = str(data.id)
			host_id = str(data.host)
			is_authority = local_id == host_id
			for member: Dictionary in data.get("members", []):
				peers[str(member.id)] = {"name": str(member.name), "weapon": "shooter", "style": {}, "ready": false, "team": peers.size() % 2}
			peers[local_id] = _identity
			phase = "lobby"
			if is_authority:
				lobby.push()
			else:
				send({"k": "me", "name": _identity.name, "weapon": _identity.weapon, "style": _identity.style}, host_id)
		"join":
			var member: Dictionary = data.get("m", {}) as Dictionary
			peers[str(member.get("id", ""))] = {"name": str(member.get("name", "Fresh Kid")), "style": {}, "weapon": "shooter", "ready": false, "team": peers.size() % 2}
			if is_authority: lobby.push()
		"leave":
			var gone: String = str(data.get("id", ""))
			peers.erase(gone)
			host_id = str(data.get("host", host_id))
			is_authority = local_id == host_id
			lobby.disconnected(gone)
		"err":
			status_changed.emit(str(data.get("e", "Could not connect")))

func set_ready(value: bool) -> void:
	if not active or phase != "lobby": return
	if is_authority:
		peers[local_id].ready = value
		lobby.push()
	else:
		send({"k": "me", "ready": value}, host_id)

func start() -> bool:
	return lobby.start() if lobby != null else false

func set_lobby_options(options: Dictionary) -> void:
	if active and is_authority and phase == "lobby":
		for key: String in ["map", "stage", "time", "time_of_day", "duration", "difficulty", "palette", "mode", "bots"]:
			if options.has(key): match_options[key] = options[key]
		lobby.push()

func set_team(team: int) -> void:
	if not active or phase != "lobby": return
	if is_authority:
		lobby.receive(local_id, {"k": "me", "team": clampi(team, 0, 1)})
	else: send({"k": "me", "team": clampi(team, 0, 1)}, host_id)

func set_me(changes:Dictionary) -> void:
	if not active or phase!="lobby":return
	var message:Dictionary={"k":"me"}
	for key:String in ["name","style","weapon"]:
		if changes.has(key):message[key]=changes[key]
	if is_authority:lobby.receive(local_id,message)
	else:send(message,host_id)

func emote(value:Variant) -> void:
	if not active or phase!="lobby":return
	var names:Array[String]=["wave","flex","booyah","dance"]
	var name:String=names[clampi(int(value),0,3)] if value is int else str(value).substr(0,16)
	emote_received.emit(local_id,name)
	send({"k":"emote","n":name})

func bind_match() -> void:
	if replication != null:
		replication.bind_match()
	if active:
		send({"k": "ready", "id": match_options.get("id", "native")}, host_id)
		if is_authority: lobby.mark_ready(local_id)

func owns_actor(actor: Node) -> bool:
	return not active or str(actor.get_meta("net_owner", local_id)) == local_id

func update(delta: float) -> void:
	if active and relay==null:_native_inbox.expire(Time.get_ticks_msec())
	if relay != null: relay.poll(delta)
	if active and phase == "match" and replication != null: replication.update(delta)
	if lobby != null: lobby.update(delta)
	if active and phase=="results" and is_authority and _results_left>=0:
		_results_left=maxf(0,_results_left-delta)
		if _results_left<=0:return_to_lobby()

func begin_results()->void:
	if not active:return
	phase="results"
	if is_authority:_results_left=12.0

func return_to_lobby()->bool:
	if not active or not is_authority or phase!="results":return false
	send({"k":"end"})
	_end_match()
	return true

func _end_match()->void:
	if not active:return
	_results_left=-1.0;phase="lobby"
	_native_inbox.clear()
	if replication:replication.clear()
	roster.clear()
	for id:String in peers:peers[id].ready=false
	if is_authority and relay:relay.lock_room(false)
	match_ended.emit()
	lobby.push()

func leave() -> void:
	# Publish offline before closing sockets: disconnect callbacks may run during close().
	active = false
	phase = "offline"
	var old_relay:InkRelayLink=relay
	var old_enet:ENetMultiplayerPeer=_enet
	relay = null
	_enet = null
	if old_relay != null: old_relay.disconnect_room()
	if old_enet != null: old_enet.close()
	if is_inside_tree(): multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	is_authority = true
	peers.clear()
	roster.clear()
	_results_left=-1.0
	_native_inbox.clear();_native_frame=0;_native_budget_error=false
	_native_sent_ticks=0;_native_sent_small=0;_native_sent_compressed=0;_native_sent_fragmented=0;_native_sent_parts=0;_native_max_parts=0
	if replication != null: replication.clear()

func _connection_lost(reason:String)->void:
	if not active and phase=="offline":return
	var interrupted:bool=phase in ["starting","match","results"]
	var should_abort:bool=interrupted and not _abort_emitted
	if should_abort:_abort_emitted=true
	leave()
	# Consumers may dispose their match in this callback; do not access it after emission.
	if should_abort:match_aborted.emit(reason)
	elif not interrupted:status_changed.emit(reason)

func send(data: Dictionary, target: String = "") -> void:
	if not active: return
	if relay != null:
		if target.is_empty(): relay.broadcast(data)
		else: relay.send_to(target, data)
		return
	var is_tick: bool = str(data.get("k", "")) == "t"
	if is_authority:
		for peer_id: int in multiplayer.get_peers():
			if not target.is_empty() and str(peer_id) != target: continue
			if is_tick: _send_native_tick(peer_id, local_id, data)
			else: _native_message.rpc_id(peer_id, local_id, data)
	else:
		if is_tick: _send_native_tick(1, "", data)
		else: _native_message.rpc_id(1, "", data)

func _send_native_tick(peer_id:int,sender:String,data:Dictionary)->void:
	_native_frame+=1
	var packets:Array[Dictionary]=_encode_native_tick(sender,data,_native_frame)
	if packets.is_empty():
		if not _native_budget_error:
			_native_budget_error=true
			push_error("Native tick exceeds bounded ENet framing limits; snapshot was not sent")
		return
	_native_sent_ticks+=1;_native_sent_parts+=packets.size();_native_max_parts=maxi(_native_max_parts,packets.size())
	if packets.size()>1:_native_sent_fragmented+=1
	elif packets[0].has("_nz"):_native_sent_compressed+=1
	else:_native_sent_small+=1
	for packet:Dictionary in packets:_native_tick.rpc_id(peer_id,sender,packet)

func _encode_native_tick(sender:String,data:Dictionary,sequence:int)->Array[Dictionary]:
	return NATIVE_ZSTD_TICK.encode(sender,data,sequence) if _native_zstd_enabled else NATIVE_TICK.split(sender,data,sequence)

func native_tick_metrics()->Dictionary:
	var inbox:Dictionary=_native_inbox.debug_state()
	return {"zstd_enabled":_native_zstd_enabled,"sent_ticks":_native_sent_ticks,"sent_small":_native_sent_small,"sent_compressed":_native_sent_compressed,"received_compressed":int(inbox.get("compressed_completed",0)),"sent_fragmented":_native_sent_fragmented,"sent_parts":_native_sent_parts,"max_parts_per_tick":_native_max_parts,"budget_error":_native_budget_error,"inbox":inbox}

@rpc("any_peer", "call_remote", "reliable", 0)
func _native_message(sender: String, data: Dictionary) -> void:
	_native_receive(sender, data, false)

@rpc("any_peer", "call_remote", "unreliable", 1)
func _native_tick(sender: String, data: Dictionary) -> void:
	# The ID originates from Godot's authenticated ENet RPC, never from the envelope.
	sender=_native_tick_sender(multiplayer.get_remote_sender_id(),sender)
	if sender.is_empty():return
	var restored:Dictionary=_decode_native_tick(sender,data,Time.get_ticks_msec())
	if not restored.is_empty():_native_receive(sender,restored,true)

func _native_tick_sender(peer_id:int,claimed_sender:String)->String:
	if not active or transport!="enet" or relay!=null or peer_id<1 or peer_id>2147483647:return ""
	if peer_id==int(local_id):return ""
	var sender:String=str(peer_id) if is_authority else claimed_sender
	if not is_authority and peer_id!=1:return ""
	return sender if peers.has(sender) else ""

func _decode_native_tick(sender:String,data:Dictionary,now:int)->Dictionary:
	# Only _native_tick calls this after RPC authentication and room membership above.
	if not active or transport!="enet" or relay!=null or not peers.has(sender):return {}
	if _native_zstd_enabled:
		if not _native_inbox.authorize_sender(sender):return {}
	elif data.has("_nz"):
		# Mixed developer configurations cannot apply an envelope as an ordinary tick.
		return {}
	return _native_inbox.accept(sender,data,now)

func _native_receive(sender: String, data: Dictionary, tick: bool) -> void:
	var peer_id: int = multiplayer.get_remote_sender_id()
	if is_authority:
		sender = str(peer_id)
		if not peers.has(sender) and str(data.get("k", "")) != "me": return
		_receive(sender, data)
		if (str(data.get("k", "")) in ["t", "paint", "ev", "hit"] and replication.valid_sender(sender, data)) or (str(data.get("k", ""))=="emote" and peers.has(sender)):
			for recipient: int in multiplayer.get_peers():
				if recipient == peer_id: continue
				if tick: _send_native_tick(recipient, sender, data)
				else: _native_message.rpc_id(recipient, sender, data)
	elif peer_id == 1:
		_receive(sender, data)

func _receive(sender: String, data: Dictionary) -> void:
	if data.size() > 32: return
	var kind: String = str(data.get("k", ""))
	if kind in ["me", "lobby", "start", "ready", "go"]:
		lobby.receive(sender, data)
	elif kind=="emote" and peers.has(sender):emote_received.emit(sender,str(data.get("n","wave")).substr(0,16))
	elif kind=="end" and sender==host_id and phase in ["match","results"]:_end_match()
	elif kind in ["t", "paint", "ev", "hit", "bhit", "bhfx", "st", "res", "own"]:
		replication.receive(sender, data)

func _connected() -> void:
	if not active or transport!="enet":return
	local_id = str(multiplayer.get_unique_id())
	host_id = "1"
	phase = "lobby"
	send({"k": "me", "name": _identity.name, "weapon": _identity.weapon, "style": _identity.style}, host_id)

func _peer_connected(_id: int) -> void:
	pass

func _peer_disconnected(id: int) -> void:
	if not active:return
	_native_inbox.clear_peer(str(id))
	peers.erase(str(id))
	if is_authority: lobby.disconnected(str(id))

func _failed() -> void:
	_connection_lost("Could not connect to native room")

func _server_left() -> void:
	_connection_lost("The LAN host left. Return to Online to reconnect.")

func record_paint(position: Vector3, normal: Vector3, radius: float, team: int, seed: float = 0, options: Dictionary = {}) -> void:
	if active and not applying: replication.record_paint(position, normal, radius, team, seed, options)

func record_event(kind: String, data: Dictionary) -> void:
	if active and not applying:
		if is_authority and replication.boss_sync!=null:replication.boss_sync.record_event(kind,data)
		replication.record_event(kind, data)

func paint_event(position: Vector3, normal: Vector3, radius: float, team: int, options: Dictionary = {}) -> void:
	record_paint(position, normal, radius, team, float(options.get("seed", randf())), options)

func on_event(kind: String, data: Dictionary) -> void:
	record_event(kind, data)

func send_hit(attacker: Node, victim: Node, amount: float, cause: String = "weapon") -> bool:
	return replication.send_hit(attacker, victim, amount, cause) if active and not applying else false

func publish_result(stats: Dictionary) -> void:
	if active and is_authority:
		send({"k": "res", "r": stats})
		begin_results()

func send_boss_hit(attacker: Node, amount: float, weapon: String, weak: bool = false, crab: int = -1) -> bool:
	if not active or applying or replication.boss_sync == null: return false
	return replication.boss_sync.send_hit(attacker, amount, weapon, weak, crab)
