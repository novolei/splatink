extends SceneTree
## Codec-only tests. Root executes this script through the shared engine lock.
const CODEC=preload("res://scripts/net/native_tick_codec.gd")
const INBOX=preload("res://scripts/net/native_tick_inbox.gd")
const TIMELINE=preload("res://scripts/net/peer_timeline.gd")
var checks:int=0
var failures:Array[String]=[]
var maximum_wire_bytes:int=0

func _initialize()->void:
	_run.call_deferred()

func _run()->void:
	var sender:String="2147483647"
	var original:Dictionary=_tick(10.0,8,true)
	var pristine:Dictionary=original.duplicate(true)
	var parts:Array[Dictionary]=CODEC.split(sender,original,1)
	_check(parts.size()>1,"eight actors exceed one bounded packet")
	_check(original==pristine,"split never changes the source dictionary")
	var ids:Dictionary={};var rows:int=0
	for packet:Dictionary in parts:
		maximum_wire_bytes=maxi(maximum_wire_bytes,CODEC.wire_size(sender,packet))
		_check(CODEC.wire_size(sender,packet)<=CODEC.BUDGET,"serialized RPC arguments plus header reserve fit 1200 bytes")
		_check(float(packet.ts)==10.0,"all chunks retain the same source timestamp")
		for row:Array in packet.a:
			_check(row.size()==21 and row==original.a[int(row[0])],"actor row retains all 21 original fields")
			_check(not ids.has(int(row[0])),"actor index occurs in exactly one chunk")
			ids[int(row[0])]=true;rows+=1
	_check(rows==8 and ids.size()==8,"all eight actor indices are transmitted")
	var inbox=INBOX.new();var restored:Dictionary={}
	for index:int in range(parts.size()-1,-1,-1):
		var result:Dictionary=inbox.accept(sender,parts[index],100+index)
		if index>0:_check(result.is_empty(),"partial frame does not update actors or Boss")
		else:restored=result
	_check(restored==original,"reverse-order parts reconstruct the complete original tick")
	_check(inbox.accept(sender,parts[0],200).is_empty(),"duplicate completed frame is ignored")
	var timeline=TIMELINE.new();timeline.accept(float(restored.ts),10.05,restored.a)
	_check(timeline.samples.size()==8,"one timeline frame includes every actor")
	for id:int in 8:_check(timeline.sample(id).hp==float(original.a[id][11]),"all actor HP values survive framing")
	_small_and_fragment_order(sender)
	_drop_expire_duplicate(sender)
	_bounds(sender)
	_invalid(sender)
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"maximum_wire_bytes":maximum_wire_bytes,"budget_bytes":CODEC.BUDGET,"rpc_header_reserve":CODEC.RPC_RESERVE,"actual_enet":false}
	var output:String="res://shots/native_tick_contract.json"
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):output=argument.trim_prefix("--output=")
	var file:FileAccess=FileAccess.open(output,FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"));file.close()
	else:_check(false,"report file opens")
	print("NATIVE_TICK_CONTRACT ",JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)

func _small_and_fragment_order(sender:String)->void:
	var inbox=INBOX.new()
	var old_small:Dictionary=_tick(20.0,1,false)
	var new_fragment:Dictionary=_tick(21.0,8,true)
	var packets:Array[Dictionary]=CODEC.split(sender,new_fragment,10)
	var assembled:Dictionary={}
	for packet:Dictionary in packets:assembled=inbox.accept(sender,packet,100)
	_check(assembled==new_fragment,"new fragmented tick completes")
	_check(inbox.accept(sender,old_small,110).is_empty(),"old small tick cannot revert newer fragmented HP or clock")
	var new_small:Dictionary=_tick(22.0,1,false)
	_check(CODEC.split(sender,new_small,11)==[new_small],"small source tick dictionary has no framing changes")
	_check(inbox.accept(sender,new_small,120)==new_small,"new small tick follows fragmented tick")
	for packet:Dictionary in packets:_check(inbox.accept(sender,packet,130).is_empty(),"old fragmented tick cannot revert newer small state")
	_check(inbox.accept(sender,new_small,140).is_empty(),"duplicate small tick is ignored")
	var older_parts:Array[Dictionary]=CODEC.split(sender,_tick(23.0,8,true),12)
	inbox.accept(sender,older_parts[0],150)
	var newest:Dictionary=_tick(24.0,1,false)
	_check(inbox.accept(sender,newest,160)==newest,"new small tick passes an incomplete older frame")
	for packet:Dictionary in older_parts:_check(inbox.accept(sender,packet,170).is_empty(),"late fragments of an abandoned older frame cannot apply")
	_check(inbox.debug_state().pending==0,"new completed tick discards older pending frames")
	# Reconnect and new match may reset sender time and native sequence.
	inbox.clear_peer(sender)
	_check(inbox.accept(sender,old_small,180)==old_small,"disconnect clears sender timestamp history")
	inbox.clear()
	_check(inbox.accept(sender,_tick(1.0,1,false),190).ts==1.0,"room lifecycle clears all tick ordering history")

func _drop_expire_duplicate(sender:String)->void:
	var inbox=INBOX.new();var tick:Dictionary=_tick(30.0,8,true)
	var packets:Array[Dictionary]=CODEC.split(sender,tick,30)
	_check(inbox.accept(sender,packets[0],10).is_empty(),"first fragment is pending")
	_check(inbox.accept(sender,packets[0],11).is_empty(),"duplicate pending fragment is ignored")
	_check(inbox.debug_state().pending==1,"duplicate does not allocate another frame")
	for index:int in range(2,packets.size()):_check(inbox.accept(sender,packets[index],12+index).is_empty(),"one lost fragment leaves the whole frame pending")
	inbox.expire(1200)
	_check(inbox.debug_state().pending==0 and inbox.debug_state().expired==1,"lost frame expires after the bounded timeout")
	var fresh:Dictionary=_tick(31.0,8,true);var fresh_parts:Array[Dictionary]=CODEC.split(sender,fresh,31);var result:Dictionary={}
	for packet:Dictionary in fresh_parts:result=inbox.accept(sender,packet,1210)
	_check(result==fresh,"packet loss does not prevent the next complete frame")
	var conflicting:Dictionary=packets[0].duplicate(true);conflicting.a[0][11]=23
	var another=INBOX.new();another.accept(sender,packets[0],1)
	_check(another.accept(sender,conflicting,2).is_empty() and another.debug_state().pending==0,"conflicting duplicate rejects its frame")

func _bounds(sender:String)->void:
	var inbox=INBOX.new()
	for frame:int in range(1,40):
		var parts:Array[Dictionary]=CODEC.split(sender,_tick(float(frame),8,true),frame)
		inbox.accept(sender,parts[0],frame)
	_check(inbox.debug_state().pending==INBOX.MAX_PENDING_PER_SENDER,"one sender retains at most two incomplete frames")
	for peer:int in 20:
		var identity:String=str(peer)
		var parts:Array[Dictionary]=CODEC.split(identity,_tick(50.0,8,true),50)
		inbox.accept(identity,parts.back(),100)
	_check(inbox.debug_state().pending<=INBOX.MAX_PENDING,"all incomplete sender frames share a global cap")
	_check(inbox.debug_state().buffered_metadata_bytes<=INBOX.MAX_PENDING*CODEC.MAX_METADATA_BYTES,"buffered metadata has a finite memory bound")
	var huge:Dictionary=_tick(60.0,8,true);huge.NB={"oversize":"x".repeat(CODEC.MAX_METADATA_BYTES)}
	_check(CODEC.split(sender,huge,60).is_empty(),"oversized metadata is rejected before allocating packets")
	var large:Dictionary=_tick(61.0,8,true);large.NB={"source":"s".repeat(25000)}
	var large_parts:Array[Dictionary]=CODEC.split(sender,large,61);var result:Dictionary={}
	_check(large_parts.size()>20 and large_parts.size()<=CODEC.MAX_PARTS,"large Boss metadata uses bounded small packets")
	var large_inbox=INBOX.new()
	for packet:Dictionary in large_parts:
		_check(CODEC.wire_size(sender,packet)<=CODEC.BUDGET,"large metadata fragment respects packet budget")
		result=large_inbox.accept(sender,packet,200)
	_check(result==large,"large Boss metadata is restored once with its actors")

func _invalid(sender:String)->void:
	var packets:Array[Dictionary]=CODEC.split(sender,_tick(70.0,8,true),70)
	var inbox=INBOX.new();var invalid:Dictionary=packets[0].duplicate(true);invalid._nt[2]=CODEC.MAX_PARTS+1
	_check(inbox.accept(sender,invalid,0).is_empty() and inbox.debug_state().pending==0,"unbounded part count is rejected")
	invalid=packets[0].duplicate(true);invalid._nt[3]=CODEC.MAX_METADATA_BYTES+1
	_check(inbox.accept(sender,invalid,0).is_empty() and inbox.debug_state().pending==0,"unbounded metadata size is rejected")
	invalid=packets[0].duplicate(true);invalid.ts=NAN
	_check(inbox.accept(sender,invalid,0).is_empty(),"nonfinite tick time is rejected")
	var duplicate_id:Array[Dictionary]=CODEC.split(sender,_tick(71.0,8,true),71)
	duplicate_id[1].a[0]=duplicate_id[0].a[0]
	var final:Dictionary={}
	for packet:Dictionary in duplicate_id:final=inbox.accept(sender,packet,1)
	_check(final.is_empty() and inbox.debug_state().pending==0,"duplicate actor index rejects a complete frame")
	var corrupted:Array[Dictionary]=CODEC.split(sender,_tick(72.0,8,true),72)
	var last:Dictionary=corrupted.back();last._m[0]^=1
	for packet:Dictionary in corrupted:final=inbox.accept(sender,packet,2)
	_check(final.is_empty(),"corrupted metadata fails its digest before Variant decoding")

func _tick(timestamp:float,count:int,metadata:bool)->Dictionary:
	var actors:Array=[]
	for index:int in count:
		actors.append([index,1.25+index,0.25,-8.0-index,1.5,0.0,2.5,0.123,0.321,-0.1,17,100-index,99-index,10+index,0.5,index*10,2,0,0,0,0])
	var result:Dictionary={"k":"t","ts":timestamp,"a":actors}
	if metadata:
		result.st=[]
		for index:int in count:result.st.append([index,index*10,index,0,index*30,index])
		result.c=["playing",120.0-timestamp]
		result.B=[1.0,2.0,3.0,0.1,1500,1800,2,8]
		result.NB={"clip":"slam","phase":"telegraph","dur":0.7,"hazards":[{"kind":"ring","reach":"r".repeat(1800)}]}
	return result

func _check(condition:bool,message:String)->void:
	checks+=1
	if not condition:failures.append(message);push_error(message)
