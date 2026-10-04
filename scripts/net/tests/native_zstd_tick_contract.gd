extends SceneTree
## Production codec and adapter-selection checks. Root runs the engine; no actual ENet is claimed.
const CODEC=preload("res://scripts/net/native_zstd_tick_codec.gd")
const INBOX=preload("res://scripts/net/native_zstd_tick_inbox.gd")
const BYTES=preload("res://scripts/net/variant_bytes_guard.gd")
const FRAME=preload("res://scripts/net/zstd_frame_guard.gd")
const NETWORK=preload("res://scripts/net/ink_network.gd")
var checks:int=0
var failures:Array[String]=[]
var maximum_wire:int=0
var maximum_decode:int=0
var canonicalization_probes:Array[Dictionary]=[]

func _initialize()->void:_run.call_deferred()

func _run()->void:
	var sender:String="2147483647"
	var original:Dictionary=_tick(10.0,8,true)
	var pristine:PackedByteArray=var_to_bytes(original)
	var packets:Array[Dictionary]=CODEC.encode(sender,original,1)
	_check(packets.size()==1 and packets[0].has("_nz"),"eight source actors and stats fit one compressed packet")
	_check(var_to_bytes(original)==pristine,"encoder preserves every source byte and actor float")
	for packet:Dictionary in packets:
		var wire:int=CODEC.PLAIN.wire_size(sender,packet);maximum_wire=maxi(maximum_wire,wire)
		_check(wire<=1200,"compressed RPC plus 64-byte reserve fits1200 bytes")
		_check(CODEC.PLAIN.wire_size("",packet)==wire,"empty guest identity reserves full ten-character forwarded sender")
	var inbox=INBOX.new();inbox.authorize_sender(sender)
	if packets.size()==1 and packets[0].has("_nz"):
		var restored:Dictionary=inbox.accept(sender,packets[0],100)
		_check(var_to_bytes(restored)==pristine and restored==original,"decoder restores exact original dictionary and bytes")
		maximum_decode=maxi(maximum_decode,int(inbox.debug_state().peak_decode_bytes))
		_check(inbox.accept(sender,packets[0],110).is_empty(),"duplicate compressed frame cannot apply twice")
		_invalid(sender,packets[0])
	_fallback(sender)
	_order_and_lifecycle(sender)
	_byte_guard()
	_canonical_strings(sender)
	_reject_wire_nul(sender)
	_check(canonicalization_probes.size()==8,"all six source-string and two guarded wire-string probes completed")
	_adapter_selection(sender)
	var enabled:bool=OS.get_cmdline_user_args().has("--native-tick-zstd")
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"maximum_wire_bytes":maximum_wire,"maximum_decode_bytes":maximum_decode,"budget_bytes":1200,"raw_decode_cap":65536,"rpc_header_reserve":64,"actual_enet":false,"production_paths":true,"adapter_zstd_enabled":enabled,"default_enabled":false,"canonicalization_probes":canonicalization_probes}
	var output:String="res://shots/native_zstd_contract.json"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	var file:FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	else:failures.append("Cannot write production-path report")
	print("NATIVE_ZSTD_CONTRACT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _fallback(sender:String)->void:
	var small:Dictionary=_tick(20.0,1,false)
	_check(CODEC.encode(sender,small,2)==[small],"ordinary one-actor source tick stays unchanged and uncompressed")
	var random:=RandomNumberGenerator.new();random.seed=0x494e4b
	var bytes:=PackedByteArray();bytes.resize(28000)
	for index:int in bytes.size():bytes[index]=random.randi()&255
	var large:Dictionary=_tick(21.0,8,true);large.NB={"blob":bytes}
	var packets:Array[Dictionary]=CODEC.encode(sender,large,3)
	_check(packets.size()>1 and not packets[0].has("_nz"),"incompressible source metadata falls back to existing framing")
	_check(packets==CODEC.PLAIN.split(sender,large,3),"fallback is exactly the existing actor and metadata packets")
	var inbox=INBOX.new();inbox.authorize_sender(sender);var restored:Dictionary={}
	for index:int in range(packets.size()-1,-1,-1):
		var wire:int=CODEC.PLAIN.wire_size(sender,packets[index]);maximum_wire=maxi(maximum_wire,wire)
		_check(wire<=1200,"every fallback packet respects the same1200-byte budget")
		restored=inbox.accept(sender,packets[index],100)
	_check(restored==large,"reverse fallback fragments retain every metadata byte")
	var raw_over_cap:Dictionary=_tick(22.0,8,false);raw_over_cap.NB={"text":"x".repeat(65000)}
	var plain:Array[Dictionary]=CODEC.PLAIN.split(sender,raw_over_cap,4)
	_check(var_to_bytes(raw_over_cap).size()>65536 and not plain.is_empty(),"large total source tick remains within original metadata cap")
	_check(CODEC.encode(sender,raw_over_cap,4)==plain,"raw cap prevents compression but keeps legal original framing")
	var bounded:Dictionary=_tick(23.0,8,false);bounded.NB={"text":"z".repeat(60000)}
	var compressed:Array[Dictionary]=CODEC.encode(sender,bounded,5)
	_check(compressed.size()==1 and compressed[0].has("_nz"),"large compressible tick fits one packet within raw cap")
	var other=INBOX.new();other.authorize_sender(sender)
	if compressed.size()==1 and compressed[0].has("_nz"):
		_check(other.accept(sender,compressed[0],120)==bounded,"large compressed source metadata round-trips losslessly")
		maximum_decode=maxi(maximum_decode,int(other.debug_state().peak_decode_bytes))
	_check(maximum_decode<=65536,"bounded decode output stays within64KiB advertised buffer")

func _order_and_lifecycle(sender:String)->void:
	var inbox=INBOX.new();inbox.authorize_sender(sender)
	var compressed:Array[Dictionary]=CODEC.encode(sender,_tick(31.0,8,true),31)
	var old_small:Dictionary=_tick(30.0,1,false)
	var next_small:Dictionary=_tick(32.0,1,false)
	var fragments:Array[Dictionary]=CODEC.PLAIN.split(sender,_tick(33.0,8,true),33)
	_check(not inbox.accept(sender,compressed[0],10).is_empty(),"compressed tick is accepted first")
	_check(inbox.accept(sender,old_small,11).is_empty(),"old small cannot revert compressed HP/clock/stat state")
	_check(inbox.accept(sender,next_small,12)==next_small,"new small follows compressed frame")
	_check(inbox.accept(sender,compressed[0],13).is_empty(),"old compressed cannot revert newer small frame")
	for packet:Dictionary in fragments:inbox.accept(sender,packet,14)
	_check(inbox.accept(sender,compressed[0],15).is_empty(),"old compressed sequence cannot follow newer fragmented frame")
	var late:Array[Dictionary]=CODEC.PLAIN.split(sender,_tick(34.0,8,true),34)
	inbox.accept(sender,late[0],16)
	var newest:Array[Dictionary]=CODEC.encode(sender,_tick(35.0,8,true),35)
	_check(not inbox.accept(sender,newest[0],17).is_empty(),"new compressed frame bypasses incomplete earlier fragments")
	for packet:Dictionary in late:_check(inbox.accept(sender,packet,18).is_empty(),"late fragment cannot revert the compressed complete tick")
	_check(inbox.debug_state().pending==0,"compressed completion retires old partial frames")
	var backwards_seq:Array[Dictionary]=CODEC.encode(sender,_tick(36.0,8,true),34)
	_check(inbox.accept(sender,backwards_seq[0],19).is_empty(),"old sequence with fabricated new timestamp is rejected")
	inbox.clear_peer(sender)
	_check(inbox.accept(sender,newest[0],20).is_empty(),"disconnect removes sender membership as well as time history")
	inbox.authorize_sender(sender)
	_check(not inbox.accept(sender,CODEC.encode(sender,_tick(1.0,8,true),1)[0],21).is_empty(),"reconnect resets sequence and timestamp")
	inbox.clear()
	_check(inbox.debug_state().authorized_senders==0 and inbox.debug_state().pending==0,"room clear drops authorization and memory")
	for id:int in range(1,9):_check(inbox.authorize_sender(str(id)),"one room admits at most eight authenticated senders")
	_check(not inbox.authorize_sender("9"),"ninth sender cannot grow membership memory")
	_check(not inbox.authorize_sender("-1") and not inbox.authorize_sender("01") and not inbox.authorize_sender("2147483648"),"noncanonical or out-of-range sender is rejected")

func _invalid(sender:String,original:Dictionary)->void:
	var outsider=INBOX.new()
	_check(outsider.accept(sender,original,0).is_empty(),"unknown sender cannot allocate decompression output")
	var cases:Array[Dictionary]=[]
	var bad:Dictionary=original.duplicate(true);bad._nz[0]=99;cases.append(bad)
	bad=original.duplicate(true);bad._nz[1]=-1;cases.append(bad)
	bad=original.duplicate(true);bad._nz[2]=65537;cases.append(bad)
	bad=original.duplicate(true);bad._nz[2]=0;cases.append(bad)
	bad=original.duplicate(true);bad._nz[2]+=4;cases.append(bad)
	bad=original.duplicate(true);bad._nz[3]+=1;cases.append(bad)
	bad=original.duplicate(true);bad._nz[4]+=1;cases.append(bad)
	bad=original.duplicate(true);bad._nz[5]=PackedByteArray();cases.append(bad)
	bad=original.duplicate(true);bad._nz[5][0]^=1;bad._nz[4]=hash(bad._nz[5]);cases.append(bad)
	bad=original.duplicate(true);bad._nz[5].append(0);bad._nz[4]=hash(bad._nz[5]);cases.append(bad)
	bad=original.duplicate(true);bad.ts=float(bad.ts)+.1;cases.append(bad)
	bad=original.duplicate(true);bad.a=[];cases.append(bad)
	bad=original.duplicate(true);bad._nt=[1,0,1,0,0];cases.append(bad)
	bad=original.duplicate(true);bad._nz[2]="65536";cases.append(bad)
	bad=original.duplicate(true);bad._nz[5]="bytes";cases.append(bad)
	bad=original.duplicate(true);bad.ts=NAN;cases.append(bad)
	bad=original.duplicate(true);bad._nz[5]=PackedByteArray();bad._nz[5].resize(1400);cases.append(bad)
	var wrong_body:Dictionary=_tick(float(original.ts),8,true);wrong_body.a[7][0]=0;cases.append(_envelope(wrong_body,1))
	wrong_body=_tick(float(original.ts),8,true);wrong_body.k="paint";cases.append(_envelope(wrong_body,1))
	var raw:PackedByteArray=var_to_bytes(_tick(float(original.ts),8,true));raw.resize(raw.size()-1);cases.append(_raw_envelope(raw,float(original.ts),1))
	var impossible:PackedByteArray=var_to_bytes({});impossible.encode_u32(4,0x7fffffff);cases.append(_raw_envelope(impossible,float(original.ts),1))
	for packet:Dictionary in cases:
		var inbox=INBOX.new();inbox.authorize_sender(sender)
		_check(inbox.accept(sender,packet,0).is_empty() and inbox.debug_state().compressed_completed==0,"malformed envelope rejected before any state update")
		_check(inbox.debug_state().pending==0 and inbox.debug_state().peak_decode_bytes<=65536,"malformed envelope leaves bounded memory")
	var duplicate_actor:Dictionary=_tick(10.0,8,true);duplicate_actor.a[7][0]=0
	_check(CODEC.encode(sender,duplicate_actor,1).is_empty(),"duplicate source actor identity never encodes")
	var invalid_row:Dictionary=_tick(10.0,8,true);invalid_row.a[0][11]=101
	_check(CODEC.encode(sender,invalid_row,1).is_empty(),"invalid source HP never encodes")

func _envelope(data:Dictionary,sequence:int)->Dictionary:
	return _raw_envelope(var_to_bytes(data),float(data.ts),sequence)

func _raw_envelope(raw:PackedByteArray,timestamp:float,sequence:int)->Dictionary:
	var compressed:PackedByteArray=raw.compress(FileAccess.COMPRESSION_ZSTD)
	return {"k":"t","ts":timestamp,"_nz":[1,sequence,raw.size(),hash(raw),hash(compressed),compressed]}

func _byte_guard()->void:
	_check(BYTES.valid(var_to_bytes(_tick(1.0,8,true))),"preflight accepts actual finite numeric source metadata")
	_check(BYTES.valid(var_to_bytes({"k":"t","ts":1.0,"a":[],"NB":{"name":"墨海🙂","reach":PackedFloat32Array([.1,.2,.3])}})),"preflight preserves UTF8 and packed source reach arrays")
	_check(not BYTES.valid(var_to_bytes({"bad":NAN})),"preflight refuses nonfinite nested payload")
	var truncated:PackedByteArray=var_to_bytes(_tick(1.0,8,true));truncated.resize(truncated.size()-1)
	_check(not BYTES.valid(truncated),"preflight refuses truncated Variant before object-free decoder")
	var count_bomb:PackedByteArray=var_to_bytes({});count_bomb.encode_u32(4,0x7fffffff)
	_check(not BYTES.valid(count_bomb),"preflight refuses impossible container count without allocation")
	var deep:Dictionary={};var node:Dictionary=deep
	for index:int in 40:node.n={};node=node.n
	_check(not BYTES.valid(var_to_bytes(deep)),"preflight bounds nested depth before decoder recursion")
	var random_bytes:=PackedByteArray([0,1,2,3,4,5,6,7])
	_check(FRAME.content_size(random_bytes)==-1,"ZSTD guard rejects random bytes before native decompression")

func _adapter_selection(sender:String)->void:
	var enabled:bool=OS.get_cmdline_user_args().has("--native-tick-zstd")
	var network=NETWORK.new()
	_check(network._native_zstd_enabled==enabled,"only explicit developer flag selects compressed native adapter")
	_check(bool(network.native_tick_metrics().zstd_enabled)==enabled,"telemetry independently identifies the selected codec")
	network.active=true;network.transport="enet";network.local_id="1";network.is_authority=true
	network.peers={"1":{},sender:{}}
	_check(network._native_tick_sender(int(sender),"999")==sender,"host replaces a forged packet identity with the authenticated RPC peer")
	_check(network._native_tick_sender(0,sender).is_empty(),"non-RPC sender cannot enter native authentication")
	_check(network._native_tick_sender(9,sender).is_empty(),"connected ID outside authenticated room membership is rejected")
	_check(network._native_tick_sender(1,sender).is_empty(),"host self ID cannot masquerade as a remote sender")
	var tick:Dictionary=_tick(70.0,8,true)
	var selected:Array[Dictionary]=network._encode_native_tick(sender,tick,70)
	_check(selected.size()==1 and selected[0].has("_nz") if enabled else selected==CODEC.PLAIN.split(sender,tick,70),"selected live send path uses opt-in compression or the exact original fragments")
	var packet:Dictionary=CODEC.encode(sender,tick,70)[0]
	var restored:Dictionary=network._decode_native_tick(sender,packet,100)
	_check(restored==tick if enabled else restored.is_empty(),"adapter decodes compressed source bytes only when explicitly enabled")
	var metrics:Dictionary=network.native_tick_metrics()
	_check(int(metrics.received_compressed)==(1 if enabled else 0),"received compressed frames remain separate from ordinary small ticks")
	_check(int(metrics.inbox.small_completed)==0,"compressed envelope is never counted or applied as an ordinary source tick")
	_check(network._decode_native_tick("9",packet,110).is_empty(),"decode helper also rejects absent room membership")
	network.is_authority=false;network.local_id=sender
	_check(network._native_tick_sender(1,"1")=="1","guest accepts a known room sender only through the authenticated host")
	_check(network._native_tick_sender(8,"1").is_empty(),"guest rejects peer-to-peer tick RPCs that bypass the host")
	_check(network._native_tick_sender(1,"9").is_empty(),"guest rejects host-forwarded sender absent from room membership")
	network.transport="relay"
	_check(network._native_tick_sender(1,"1").is_empty() and network._decode_native_tick("1",packet,120).is_empty(),"relay rooms cannot enter native compression helpers")
	network.transport="enet";network.leave()
	var cleared:Dictionary=network.native_tick_metrics()
	_check(network.peers.is_empty() and int(cleared.inbox.pending)==0 and int(cleared.inbox.senders)==0,"adapter leave clears room membership and native timeline state")
	_check(int(cleared.inbox.get("authorized_senders",0))==0,"adapter leave clears compression authorizations")
	_check(int(cleared.sent_compressed)==0 and int(cleared.sent_ticks)==0,"adapter leave resets separate send telemetry")
	network.free()

func _canonical_strings(sender:String)->void:
	var unicode:String="墨海🙂résumé"
	var bom:String=String.chr(0xfeff)+unicode
	# This public Godot UTF8 constructor observes how a NUL input becomes a String;
	# do not call String.chr(0), which itself logs Unicode errors in Godot 4.7.
	var nul:String=PackedByteArray([105,110,107,0,119,97,118,101]).get_string_from_utf8()
	var probes:Array[Dictionary]=[
		{"name":"ordinary_unicode","value":unicode},
		{"name":"ordinary_leading_bom","value":bom},
		{"name":"ordinary_nul_utf8_constructor","value":nul},
		{"name":"packed_unicode_and_encoded_terminal_nul","value":PackedStringArray([unicode,"", "InkWave"])},
		{"name":"packed_leading_bom","value":PackedStringArray([bom,unicode])},
		{"name":"packed_nul_utf8_constructor","value":PackedStringArray([nul,unicode])}
	]
	for index:int in probes.size():
		var probe:Dictionary=probes[index]
		var tick:Dictionary=_tick(90.0+index,8,true);tick.NB.value=probe.value
		var raw:PackedByteArray=var_to_bytes(tick)
		var guarded:bool=BYTES.valid(raw)
		var decoded:Variant=bytes_to_var(raw) if guarded else null
		var canonical:bool=decoded is Dictionary and CODEC.valid_tick(decoded) and decoded==tick and var_to_bytes(decoded)==raw
		var packets:Array[Dictionary]=CODEC.encode(sender,tick,90+index)
		var compressed:bool=packets.size()==1 and packets[0].has("_nz")
		_check(guarded,"finite UTF8 source strings pass bounded preflight: "+str(probe.name))
		_check(var_to_bytes(tick)==raw,"string probe encoding preserves the original source bytes: "+str(probe.name))
		_check(compressed==canonical,"selected string path follows actual Godot canonical round-trip: "+str(probe.name))
		if canonical:
			var inbox=INBOX.new();inbox.authorize_sender(sender)
			var restored:Dictionary=inbox.accept(sender,packets[0],100)
			_check(restored==tick and var_to_bytes(restored)==raw,"canonical Unicode and packed strings restore exact source bytes: "+str(probe.name))
		else:
			_check(packets==CODEC.PLAIN.split(sender,tick,90+index),"noncanonical source values keep exact original framing fallback: "+str(probe.name))
		var source_texts:Array[String]=[]
		if probe.value is String:source_texts.append(probe.value)
		else:
			for text:String in probe.value:source_texts.append(text)
		var nul_stored:bool=false;var leading_bom_stored:bool=false
		for text:String in source_texts:
			leading_bom_stored=leading_bom_stored or text.length()>0 and text.unicode_at(0)==0xfeff
			for character:int in text.length():nul_stored=nul_stored or text.unicode_at(character)==0
		canonicalization_probes.append({"name":probe.name,"source_type":typeof(probe.value),"preflight_valid":guarded,"godot_roundtrip_canonical":canonical,"selected_compressed":compressed,"raw_bytes":raw.size(),"source_value_length":probe.value.length() if probe.value is String else probe.value.size(),"source_contains_nul_codepoint":nul_stored,"source_contains_leading_bom":leading_bom_stored})

func _reject_wire_nul(sender:String)->void:
	# Directly construct ordinary/packed malformed Variant bytes. The guard must
	# refuse them before bytes_to_var; no unsupported NUL-bearing String is created.
	var marker:String="inkXwave"
	for packed:bool in [false,true]:
		var value:Variant=PackedStringArray([marker]) if packed else marker
		var needle:PackedByteArray=var_to_bytes(value)
		var tick:Dictionary=_tick(110.0 if packed else 109.0,8,true);tick.NB.value=value
		var raw:PackedByteArray=var_to_bytes(tick)
		var offset:int=-1
		for index:int in range(raw.size()-needle.size()+1):
			if raw.slice(index,index+needle.size())==needle:offset=index;break
		_check(offset>=0,"wire NUL probe finds its complete ordinary/packed source value")
		if offset<0:continue
		raw[offset+(12 if packed else 8)+3]=0
		var guarded:bool=BYTES.valid(raw)
		_check(not guarded,"embedded wire NUL is rejected before the Variant decoder")
		var inbox=INBOX.new();inbox.authorize_sender(sender)
		var restored:Dictionary=inbox.accept(sender,_raw_envelope(raw,float(tick.ts),110 if packed else 109),100)
		_check(restored.is_empty() and int(inbox.debug_state().compressed_completed)==0 and int(inbox.debug_state().senders)==0,"wire NUL cannot apply a truncated string or advance source time")
		canonicalization_probes.append({"name":"packed_wire_embedded_nul" if packed else "ordinary_wire_embedded_nul","probe_scope":"received_variant_bytes","preflight_valid":guarded,"godot_roundtrip":"not_attempted_rejected_preflight","receiver_accepted":not restored.is_empty(),"raw_bytes":raw.size()})

func _tick(timestamp:float,count:int,metadata:bool)->Dictionary:
	var actors:Array=[]
	for index:int in count:actors.append([index,1.25+index,.25,-8.0-index,1.5,0.0,2.5,.123,.321,-.1,17,100-index,99-index,10+index,.5,index*10,2,0,0,0,0])
	var tick:Dictionary={"k":"t","ts":timestamp,"a":actors}
	if metadata:
		tick.st=[]
		for index:int in count:tick.st.append([index,index*10,index,0,index*30,index])
		tick.c=["playing",120.0-timestamp];tick.B=[1.0,2.0,3.0,.1,1500,1800,2,8]
		tick.NB={"clip":"slam","phase":"telegraph","dur":.7,"hazards":[{"kind":"ring","reach":PackedFloat32Array([.5,.75,1.0])}]}
	return tick

func _check(ok:bool,message:String)->void:
	checks+=1
	if not ok:failures.append(message);push_error("NATIVE_ZSTD "+message)
