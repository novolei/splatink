extends RefCounted
## Draft only. Check Godot's dictionary-free, single-segment ZSTD frame before bounded decode.
## Format reference: facebook/zstd/doc/zstd_compression_format.md.
static func content_size(bytes:PackedByteArray)->int:
	if bytes.size()<6 or bytes.decode_u32(0)!=0xfd2fb528:return -1
	var descriptor:int=bytes[4]
	# Single-segment frames advertise their exact content size and need no large window allocation.
	if (descriptor&0x20)==0 or (descriptor&0x18)!=0 or (descriptor&3)!=0:return -1
	var flag:int=descriptor>>6
	var width:int=1 if flag==0 else 2 if flag==1 else 4 if flag==2 else 8
	if bytes.size()<5+width:return -1
	var size:int=bytes.decode_u8(5) if width==1 else bytes.decode_u16(5)+256 if width==2 else bytes.decode_u32(5) if width==4 else bytes.decode_u64(5)
	if size<1 or size>65536:return -1
	var offset:int=5+width
	var blocks:int=0
	var known_output:int=0
	while true:
		if offset+3>bytes.size() or blocks>=128:return -1
		var block:int=int(bytes[offset])|(int(bytes[offset+1])<<8)|(int(bytes[offset+2])<<16)
		offset+=3;blocks+=1
		var last:bool=(block&1)!=0
		var kind:int=(block>>1)&3
		var count:int=block>>3
		if kind==3 or count>131072:return -1
		var encoded_size:int=1 if kind==1 else count
		if offset+encoded_size>bytes.size():return -1
		if kind in [0,1]:known_output+=count
		if known_output>size:return -1
		offset+=encoded_size
		if last:break
	if (descriptor&4)!=0:offset+=4
	# Concatenated/trailing/skippable frames are not part of this native single-tick envelope.
	return size if offset==bytes.size() else -1
