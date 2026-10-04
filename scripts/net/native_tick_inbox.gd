class_name InkNativeTickInbox
extends RefCounted
## A lost unreliable fragment expires; partial frames never mutate actors or Boss state.
const CODEC=preload("res://scripts/net/native_tick_codec.gd")
const SNAPSHOT=preload("res://scripts/net/snapshot_codec.gd")
const MAX_PENDING:int=16
const MAX_PENDING_PER_SENDER:int=2
const TIMEOUT_MSEC:int=1000
var _pending:Dictionary={}
var _completed:Dictionary={}
var _latest:Dictionary={}
var completed_frames:int=0
var expired_frames:int=0
var rejected_parts:int=0
var small_frames:int=0
var received_parts:int=0
var stale_parts:int=0
var duplicate_parts:int=0
var timeout_frames:int=0
var capacity_frames:int=0
var measure_cadence:bool=false
var _cadence:Dictionary={}

func clear()->void:
	_pending.clear();_completed.clear();_latest.clear();_cadence.clear()

func clear_peer(sender:String)->void:
	_completed.erase(sender)
	_latest.erase(sender)
	_cadence.erase(sender)
	for key:String in _pending.keys():
		if str(_pending[key].sender)==sender:_pending.erase(key)

func expire(now:int)->void:
	for key:String in _pending.keys():
		if now-int(_pending[key].created)>TIMEOUT_MSEC:_pending.erase(key);expired_frames+=1;timeout_frames+=1

func accept(sender:String,packet:Dictionary,now:int)->Dictionary:
	expire(now)
	received_parts+=1
	var timestamp:Variant=packet.get("ts")
	if not timestamp is float and not timestamp is int:return _reject()
	if not is_finite(float(timestamp)):return _reject()
	if str(packet.get("k",""))!="t" or CODEC.wire_size(sender,packet)>CODEC.BUDGET:return _reject()
	if _latest.has(sender) and float(timestamp)<=float(_latest[sender]):stale_parts+=1;return {}
	if not packet.has("_nt"):
		small_frames+=1;_mark_complete(sender,float(timestamp),now)
		return packet
	var header:Variant=packet.get("_nt")
	if not header is Array or header.size()!=5:return _reject()
	for value:Variant in header:
		if not value is int:return _reject()
	var frame:int=header[0];var index:int=header[1];var count:int=header[2];var size:int=header[3];var digest:int=header[4]
	if frame<0 or count<1 or count>CODEC.MAX_PARTS or index<0 or index>=count or size<0 or size>CODEC.MAX_METADATA_BYTES:return _reject()
	if frame<=int(_completed.get(sender,-1)):stale_parts+=1;return {}
	var values:Variant=packet.get("a")
	if not values is Array or values.size()>8:return _reject()
	for row:Variant in values:
		if not row is Array or not SNAPSHOT.valid(row):return _reject()
	var chunk:Variant=packet.get("_m",PackedByteArray())
	if not chunk is PackedByteArray or chunk.size()>size:return _reject()
	var key:String="%s:%d"%[sender,frame]
	if not _pending.has(key):
		_bound(sender)
		_pending[key]={"sender":sender,"frame":frame,"created":now,"ts":timestamp,"count":count,"size":size,"digest":digest,"bytes":0,"parts":{}}
	var record:Dictionary=_pending[key]
	if record.count!=count or record.size!=size or record.digest!=digest or record.ts!=timestamp:return _reject_frame(key)
	if record.parts.has(index):
		if record.parts[index]!=packet:return _reject_frame(key)
		duplicate_parts+=1
		return {}
	record.bytes+=chunk.size()
	if record.bytes>size:return _reject_frame(key)
	record.parts[index]=packet
	if record.parts.size()!=count:return {}
	var actors:Array=[];var ids:Dictionary={};var encoded:PackedByteArray=PackedByteArray()
	for part_index:int in count:
		var part:Dictionary=record.parts[part_index]
		for row:Array in part.a:
			if ids.has(int(row[0])):return _reject_frame(key)
			ids[int(row[0])]=true;actors.append(row)
		encoded.append_array(part.get("_m",PackedByteArray()))
	if actors.size()>8 or encoded.size()!=size:return _reject_frame(key)
	var restored:Dictionary={}
	if size>0:
		# Validate the complete byte stream before decoding, with object deserialization disabled.
		if size<8 or hash(encoded)!=digest or (encoded.decode_u32(0)&0xffff)!=TYPE_DICTIONARY:return _reject_frame(key)
		var decoded:Variant=bytes_to_var(encoded)
		if not decoded is Dictionary or decoded.size()>29:return _reject_frame(key)
		restored=decoded
		for reserved:String in ["k","ts","a","_nt","_m"]:
			if restored.has(reserved):return _reject_frame(key)
	restored.k="t";restored.ts=timestamp;restored.a=actors
	_pending.erase(key);_completed[sender]=frame;completed_frames+=1
	_mark_complete(sender,float(timestamp),now)
	for old_key:String in _pending.keys():
		var old:Dictionary=_pending[old_key]
		if str(old.sender)==sender and int(old.frame)<=frame:_pending.erase(old_key)
	return restored

func _mark_complete(sender:String,timestamp:float,now:int)->void:
	if measure_cadence:
		var cadence:Dictionary=_cadence.get(sender,{"source":[],"arrival":[],"last_source":timestamp,"last_arrival":now,"frames":0})
		if int(cadence.frames)>0:
			cadence.source.append((timestamp-float(cadence.last_source))*1000.0)
			cadence.arrival.append(float(now-int(cadence.last_arrival)))
			if cadence.source.size()>64:cadence.source.pop_front();cadence.arrival.pop_front()
		cadence.last_source=timestamp;cadence.last_arrival=now;cadence.frames+=1;_cadence[sender]=cadence
	_latest[sender]=timestamp
	for key:String in _pending.keys():
		var record:Dictionary=_pending[key]
		if str(record.sender)==sender and float(record.ts)<=timestamp:_pending.erase(key)

func _bound(sender:String)->void:
	var matches:Array[String]=[]
	for key:String in _pending:
		if str(_pending[key].sender)==sender:matches.append(key)
	while matches.size()>=MAX_PENDING_PER_SENDER:
		_pending.erase(matches.pop_front());expired_frames+=1;capacity_frames+=1
	while _pending.size()>=MAX_PENDING:
		_pending.erase(_pending.keys()[0]);expired_frames+=1;capacity_frames+=1

func _reject()->Dictionary:
	rejected_parts+=1
	return {}

func _reject_frame(key:String)->Dictionary:
	_pending.erase(key)
	return _reject()

func debug_state()->Dictionary:
	var bytes:int=0
	for record:Dictionary in _pending.values():bytes+=int(record.bytes)
	var cadence:Dictionary={}
	for sender:String in _cadence:
		var record:Dictionary=_cadence[sender]
		cadence[sender]={"frames":record.frames,"source_gap_ms":_distribution(record.source),"arrival_gap_ms":_distribution(record.arrival)}
	return {"pending":_pending.size(),"buffered_metadata_bytes":bytes,"completed":completed_frames,"small_completed":small_frames,"received_parts":received_parts,"stale_parts":stale_parts,"duplicate_parts":duplicate_parts,"expired":expired_frames,"timeout_expired":timeout_frames,"capacity_evicted":capacity_frames,"rejected":rejected_parts,"senders":_latest.size(),"cadence":cadence}

func _distribution(values:Array)->Dictionary:
	if values.is_empty():return {"samples":0}
	var ordered:Array=values.duplicate();ordered.sort()
	var total:float=0
	for value:float in ordered:total+=value
	return {"samples":ordered.size(),"median":ordered[ordered.size()/2],"p95":ordered[mini(ordered.size()-1,floori(ordered.size()*.95))],"maximum":ordered.back(),"mean":total/ordered.size()}
