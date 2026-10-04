extends RefCounted
## Developer opt-in native ENet compression; ordinary ticks and fallback retain the original framing.
const PLAIN=preload("res://scripts/net/native_tick_codec.gd")
const BYTES=preload("res://scripts/net/variant_bytes_guard.gd")
const FRAME=preload("res://scripts/net/zstd_frame_guard.gd")
const SNAPSHOT=preload("res://scripts/net/snapshot_codec.gd")
const VERSION:int=1
const MAX_RAW_BYTES:int=65536

static func encode(sender:String,data:Dictionary,sequence:int)->Array[Dictionary]:
	if sequence<0 or not valid_tick(data):return []
	if PLAIN.wire_size(sender,data)<=PLAIN.BUDGET:return PLAIN.split(sender,data,sequence)
	var raw:PackedByteArray=var_to_bytes(data)
	if raw.size()<=MAX_RAW_BYTES and BYTES.valid(raw):
		# Godot may canonicalize strings (for example a leading UTF8 BOM) on decoding.
		# Select compression only when the receiver can restore every original byte and value.
		# Preflight must precede this object-disabled decoder, exactly as on receive.
		var decoded:Variant=bytes_to_var(raw)
		if decoded is Dictionary and valid_tick(decoded) and decoded==data and var_to_bytes(decoded)==raw:
			var compressed:PackedByteArray=raw.compress(FileAccess.COMPRESSION_ZSTD)
			if FRAME.content_size(compressed)==raw.size():
				var packet:Dictionary={"k":"t","ts":data.ts,"_nz":[VERSION,sequence,raw.size(),hash(raw),hash(compressed),compressed]}
				if PLAIN.wire_size(sender,packet)<=PLAIN.BUDGET:return [packet]
	# Preserve the existing bounded actor/metadata framing verbatim when single-packet compression cannot fit.
	return PLAIN.split(sender,data,sequence)

static func valid_tick(data:Dictionary)->bool:
	if str(data.get("k",""))!="t" or data.size()>32:return false
	var timestamp:Variant=data.get("ts")
	if not timestamp is int and not timestamp is float:return false
	if not is_finite(float(timestamp)):return false
	for reserved:String in ["_nz","_nt","_m"]:
		if data.has(reserved):return false
	var actors:Variant=data.get("a")
	if not actors is Array or actors.size()>8:return false
	var ids:Dictionary={}
	for row:Variant in actors:
		if not row is Array or not SNAPSHOT.valid(row) or ids.has(int(row[0])):return false
		ids[int(row[0])]=true
	return true
