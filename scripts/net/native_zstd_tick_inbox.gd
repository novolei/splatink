extends "res://scripts/net/native_tick_inbox.gd"
## Room membership is registered only after the authenticated native RPC sender checks.
const ZSTD=preload("res://scripts/net/native_zstd_tick_codec.gd")
const BYTE_GUARD=preload("res://scripts/net/variant_bytes_guard.gd")
const ZSTD_FRAME=preload("res://scripts/net/zstd_frame_guard.gd")
var _authorized:Dictionary={}
var compressed_frames:int=0
var decoded_bytes:int=0
var peak_decode_bytes:int=0

func authorize_sender(sender:String)->bool:
	if sender.is_empty() or not sender.is_valid_int() or str(int(sender))!=sender or int(sender)<1 or int(sender)>2147483647:return false
	if not _authorized.has(sender) and _authorized.size()>=8:return false
	_authorized[sender]=true
	return true

func clear()->void:
	super.clear();_authorized.clear()

func clear_peer(sender:String)->void:
	super.clear_peer(sender);_authorized.erase(sender)

func accept(sender:String,packet:Dictionary,now:int)->Dictionary:
	if not _authorized.has(sender):return _reject()
	if not packet.has("_nz"):
		if not packet.has("_nt") and not ZSTD.valid_tick(packet):return _reject()
		return super.accept(sender,packet,now)
	expire(now);received_parts+=1
	if packet.size()!=3 or packet.has("_nt") or str(packet.get("k",""))!="t" or CODEC.wire_size(sender,packet)>CODEC.BUDGET:return _reject()
	var timestamp:Variant=packet.get("ts")
	if not timestamp is int and not timestamp is float:return _reject()
	if not is_finite(float(timestamp)):return _reject()
	if _latest.has(sender) and float(timestamp)<=float(_latest[sender]):stale_parts+=1;return {}
	var header:Variant=packet.get("_nz")
	if not header is Array or header.size()!=6:return _reject()
	for index:int in 5:
		if not header[index] is int:return _reject()
	var sequence:int=header[1];var raw_size:int=header[2]
	if header[0]!=ZSTD.VERSION or sequence<0 or raw_size<8 or raw_size>ZSTD.MAX_RAW_BYTES:return _reject()
	if sequence<=int(_completed.get(sender,-1)):stale_parts+=1;return {}
	var compressed:Variant=header[5]
	if not compressed is PackedByteArray or compressed.is_empty() or compressed.size()>CODEC.BUDGET:return _reject()
	if hash(compressed)!=header[4] or ZSTD_FRAME.content_size(compressed)!=raw_size:return _reject()
	# Both advertised and ZSTD frame content sizes were bounded before any output allocation.
	var raw:PackedByteArray=compressed.decompress(raw_size,FileAccess.COMPRESSION_ZSTD)
	peak_decode_bytes=maxi(peak_decode_bytes,raw.size())
	if raw.size()!=raw_size or hash(raw)!=header[3] or not BYTE_GUARD.valid(raw):return _reject()
	var decoded:Variant=bytes_to_var(raw)
	if not decoded is Dictionary or not ZSTD.valid_tick(decoded) or decoded.ts!=timestamp:return _reject()
	if var_to_bytes(decoded)!=raw:return _reject()
	# Header timestamp/sequence only become authoritative after complete lossless validation.
	_completed[sender]=sequence;compressed_frames+=1;decoded_bytes+=raw.size()
	_mark_complete(sender,float(timestamp),now)
	return decoded

func debug_state()->Dictionary:
	var state:Dictionary=super.debug_state()
	state.merge({"compressed_completed":compressed_frames,"decoded_bytes":decoded_bytes,"peak_decode_bytes":peak_decode_bytes,"authorized_senders":_authorized.size()})
	return state
