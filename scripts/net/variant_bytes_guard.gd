extends RefCounted
## Preflight for finite, object-free source packet values before Godot Variant decoding.
## Unsupported/typed values fall back to the existing framing at the encoder, never get rewritten.
const MAX_BYTES:int=65536
const MAX_DEPTH:int=32
const MAX_NODES:int=8192

static func valid(bytes:PackedByteArray)->bool:
	if bytes.size()<8 or bytes.size()>MAX_BYTES or bytes.decode_u32(0)!=TYPE_DICTIONARY:return false
	var cursor:Dictionary={"offset":0,"nodes":0}
	return _walk(bytes,cursor,0) and int(cursor.offset)==bytes.size()

static func _walk(bytes:PackedByteArray,cursor:Dictionary,depth:int)->bool:
	var offset:int=cursor.offset
	if depth>MAX_DEPTH or int(cursor.nodes)>=MAX_NODES or offset+4>bytes.size():return false
	cursor.nodes+=1
	var header:int=bytes.decode_u32(offset);cursor.offset=offset+4
	var kind:int=header&0xff
	var flags:int=header&0xffffff00
	var wide:bool=flags==0x10000
	if kind in [TYPE_INT,TYPE_FLOAT]:
		if flags not in [0,0x10000]:return false
		return _numeric(bytes,cursor,1,8 if wide else 4,kind==TYPE_FLOAT)
	if flags!=0:return false
	match kind:
		TYPE_NIL:return true
		TYPE_BOOL:
			if int(cursor.offset)+4>bytes.size():return false
			var value:int=bytes.decode_u32(cursor.offset);cursor.offset+=4
			return value<=1
		TYPE_STRING,TYPE_STRING_NAME:return _string(bytes,cursor)
		TYPE_ARRAY,TYPE_DICTIONARY:
			if int(cursor.offset)+4>bytes.size():return false
			var count:int=bytes.decode_u32(cursor.offset);cursor.offset+=4
			var fields:int=count*(2 if kind==TYPE_DICTIONARY else 1)
			if count>MAX_NODES or fields>MAX_NODES-int(cursor.nodes) or fields*4>bytes.size()-int(cursor.offset):return false
			for index:int in fields:
				if not _walk(bytes,cursor,depth+1):return false
			return true
		TYPE_PACKED_BYTE_ARRAY,TYPE_PACKED_INT32_ARRAY,TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY:
			if int(cursor.offset)+4>bytes.size():return false
			var count:int=bytes.decode_u32(cursor.offset);cursor.offset+=4
			var width:int=1 if kind==TYPE_PACKED_BYTE_ARRAY else 8 if kind in [TYPE_PACKED_INT64_ARRAY,TYPE_PACKED_FLOAT64_ARRAY] else 4
			if not _numeric(bytes,cursor,count,width,kind in [TYPE_PACKED_FLOAT32_ARRAY,TYPE_PACKED_FLOAT64_ARRAY]):return false
			if width==1:cursor.offset=(int(cursor.offset)+3)&~3
			return int(cursor.offset)<=bytes.size()
		TYPE_PACKED_STRING_ARRAY:
			if int(cursor.offset)+4>bytes.size():return false
			var count:int=bytes.decode_u32(cursor.offset);cursor.offset+=4
			if count>MAX_NODES or count*4>bytes.size()-int(cursor.offset):return false
			for index:int in count:
				if not _string(bytes,cursor,true):return false
			return true
		_:
			return false

static func _numeric(bytes:PackedByteArray,cursor:Dictionary,count:int,width:int,floating:bool)->bool:
	var offset:int=cursor.offset
	if count<0 or count>(bytes.size()-offset)/width:return false
	if floating:
		for index:int in count:
			var number:float=bytes.decode_double(offset+index*width) if width==8 else bytes.decode_float(offset+index*width)
			if not is_finite(number):return false
	cursor.offset=offset+count*width
	return true

static func _string(bytes:PackedByteArray,cursor:Dictionary,allow_terminal_nul:bool=false)->bool:
	var offset:int=cursor.offset
	if offset+4>bytes.size():return false
	var count:int=bytes.decode_u32(offset);offset+=4
	if count>bytes.size()-offset:return false
	var end:int=offset+count
	while offset<end:
		var first:int=bytes[offset];offset+=1
		# Ordinary String/StringName encoding has no terminal NUL. PackedStringArray
		# elements include exactly one at the advertised end. An embedded NUL would
		# truncate Godot's UTF8 decoder, so reject it before object-free decoding.
		if first==0:
			if not allow_terminal_nul or offset!=end:return false
			continue
		if first<128:continue
		var continuation:int=1 if first>=0xc2 and first<=0xdf else 2 if first>=0xe0 and first<=0xef else 3 if first>=0xf0 and first<=0xf4 else -1
		if continuation<0 or offset+continuation>end:return false
		var next:int=bytes[offset]
		if (first==0xe0 and next<0xa0) or (first==0xed and next>=0xa0) or (first==0xf0 and next<0x90) or (first==0xf4 and next>=0x90):return false
		for index:int in continuation:
			if bytes[offset+index]<0x80 or bytes[offset+index]>0xbf:return false
		offset+=continuation
	cursor.offset=(end+3)&~3
	return int(cursor.offset)<=bytes.size()
