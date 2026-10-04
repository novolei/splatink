class_name InkRelayLink
extends RefCounted
## Exact INKWAVE transport v1 envelope. Room payloads are never Godot RPC frames.

signal control_received(data: Dictionary)
signal message_received(sender: String, data: Dictionary)
signal closed(reason: String)

const PRODUCTION_RELAY := "wss://inkwave-net.inkwave.workers.dev"
const CODE_CHARS := "BCEFGHJKLMNPQRTUVXYZ23456789"
const MAX_PACKET := 65536
var peer: WebSocketPeer
var id: String = ""
var rtt_ms: float = 0
var _elapsed: float = 0
var _ping_timer: float = 0
var _ping_sent: int = 0
var _welcomed: bool = false
var _closing: bool = false

static func room_code() -> String:
	var result: String = ""
	for index: int in 5:
		result += CODE_CHARS[randi_range(0, CODE_CHARS.length() - 1)]
	return result

func connect_room(code: String, player_name: String, create: bool, relay: String = PRODUCTION_RELAY) -> Error:
	disconnect_room()
	code = code.to_upper().strip_edges()
	if code.length() != 5:
		return ERR_INVALID_PARAMETER
	for letter: String in code:
		if not CODE_CHARS.contains(letter):
			return ERR_INVALID_PARAMETER
	if not relay.begins_with("ws://") and not relay.begins_with("wss://"):
		return ERR_INVALID_PARAMETER
	peer = WebSocketPeer.new()
	peer.inbound_buffer_size = 262144
	peer.outbound_buffer_size = 262144
	peer.max_queued_packets = 256
	_elapsed = 0
	_ping_timer = 0
	_welcomed = false
	_closing = false
	var url: String = "%s/room/%s?name=%s&v=1%s" % [relay.trim_suffix("/"), code.uri_encode(), player_name.substr(0, 16).uri_encode(), "&create=1" if create else ""]
	return peer.connect_to_url(url)

func poll(delta: float) -> void:
	if peer == null:
		return
	_elapsed += delta
	peer.poll()
	var state: WebSocketPeer.State = peer.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN:
		while peer.get_available_packet_count() > 0:
			var packet: PackedByteArray = peer.get_packet()
			if packet.size() > MAX_PACKET:
				continue
			_receive(packet.get_string_from_utf8())
		_ping_timer -= delta
		if _ping_timer <= 0 and _welcomed:
			_ping_timer = 2.0
			_ping_sent = Time.get_ticks_msec()
			_raw("ping")
	elif state == WebSocketPeer.STATE_CLOSED:
		var reason: String = peer.get_close_reason()
		peer = null
		if not _closing:
			closed.emit(reason if not reason.is_empty() else "Disconnected from room")
	if not _welcomed and _elapsed > 8:
		disconnect_room()
		closed.emit("Could not connect to the room relay")

func _receive(text: String) -> void:
	if text == "pong":
		var measured: float = float(Time.get_ticks_msec() - _ping_sent)
		rtt_ms = lerpf(rtt_ms, measured, 0.3) if rtt_ms > 0 else measured
		return
	if text.begins_with("m|"):
		var separator: int = text.find("|", 2)
		if separator < 3:
			return
		var value: Variant = JSON.parse_string(text.substr(separator + 1))
		if value is Dictionary:
			message_received.emit(text.substr(2, separator - 2), value as Dictionary)
		return
	var value: Variant = JSON.parse_string(text)
	if not value is Dictionary:
		return
	var data: Dictionary = value as Dictionary
	if str(data.get("t", "")) == "welcome":
		id = str(data.get("id", ""))
		_welcomed = true
	control_received.emit(data)

func broadcast(data: Dictionary) -> bool:
	return _raw("b|" + JSON.stringify(data))

func send_to(target: String, data: Dictionary) -> bool:
	if target.is_empty() or target.contains("|"):
		return false
	return _raw("s|%s|%s" % [target, JSON.stringify(data)])

func lock_room(value: bool) -> bool:
	return _raw(JSON.stringify({"t": "lock", "v": value}))

func _raw(text: String) -> bool:
	return peer != null and peer.get_ready_state() == WebSocketPeer.STATE_OPEN and text.to_utf8_buffer().size() <= MAX_PACKET and peer.send_text(text) == OK

func disconnect_room() -> void:
	_closing = true
	if peer != null:
		peer.close(1000, "bye")
	peer = null
	id = ""
