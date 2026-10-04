class_name InkNativeTickCodec
extends RefCounted
## ENet-only framing. Each actor row remains intact; source tick dictionaries are restored before use.
const BUDGET:int=1200
const RPC_RESERVE:int=64
const MAX_METADATA_BYTES:int=65536
const MAX_PARTS:int=128
const SNAPSHOT=preload("res://scripts/net/snapshot_codec.gd")

static func wire_size(sender:String,packet:Dictionary)->int:
	# Guest RPCs use an empty sender; the host authenticates and replaces it with a 31-bit peer ID.
	# Reserve that same ten-character identity at both boundaries, including host forwarding.
	var identity:String="2147483647" if sender.length()<10 else sender
	return var_to_bytes([identity,packet]).size()+RPC_RESERVE

static func split(sender:String,data:Dictionary,frame:int)->Array[Dictionary]:
	if wire_size(sender,data)<=BUDGET:return [data]
	var values:Variant=data.get("a",[])
	if str(data.get("k",""))!="t" or not values is Array or values.size()>8:return []
	var metadata:Dictionary=data.duplicate()
	for key:String in ["k","ts","a"]:metadata.erase(key)
	var encoded:PackedByteArray=var_to_bytes(metadata) if not metadata.is_empty() else PackedByteArray()
	if encoded.size()>MAX_METADATA_BYTES:return []
	var digest:int=hash(encoded) if not encoded.is_empty() else 0
	var parts:Array[Dictionary]=[]
	var current:Dictionary=_part(data,frame,encoded.size(),digest)
	for row:Variant in values:
		if not row is Array or not SNAPSHOT.valid(row):return []
		var candidate:Dictionary=current.duplicate()
		candidate.a=(current.a as Array).duplicate();candidate.a.append(row)
		if wire_size(sender,candidate)>BUDGET:
			if (current.a as Array).is_empty():return []
			parts.append(current);current=_part(data,frame,encoded.size(),digest);current.a.append(row)
			if wire_size(sender,current)>BUDGET:return []
		else:current=candidate
	if not (current.a as Array).is_empty():parts.append(current)
	var offset:int=0
	while offset<encoded.size():
		var packet:Dictionary=_part(data,frame,encoded.size(),digest)
		var lo:int=1;var hi:int=mini(encoded.size()-offset,BUDGET)
		while lo<hi:
			var middle:int=(lo+hi+1)/2
			packet._m=encoded.slice(offset,offset+middle)
			if wire_size(sender,packet)<=BUDGET:lo=middle
			else:hi=middle-1
		packet._m=encoded.slice(offset,offset+lo)
		if wire_size(sender,packet)>BUDGET:return []
		parts.append(packet);offset+=lo
		if parts.size()>MAX_PARTS:return []
	if parts.is_empty() or parts.size()>MAX_PARTS:return []
	for index:int in parts.size():
		parts[index]._nt[1]=index;parts[index]._nt[2]=parts.size()
	return parts

static func _part(data:Dictionary,frame:int,metadata_size:int,digest:int)->Dictionary:
	# MAX_PARTS reserves the final header width while calculating each part's capacity.
	return {"k":"t","ts":data.get("ts",0.0),"a":[],"_nt":[frame,0,MAX_PARTS,metadata_size,digest]}
