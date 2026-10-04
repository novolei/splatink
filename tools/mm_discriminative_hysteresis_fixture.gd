extends Node
## Query/decision diagnostic, not full-game input or visual acceptance.
## Root is the only operator of the serialized Godot wrapper.
const Avatar=preload("res://scripts/characters/ink_avatar.gd")
const Portable=preload("res://scripts/animation/ink_motion_matcher.gd")
const Native=preload("res://scripts/animation/native_motion_matcher.gd")

class PortableFixture extends InkMotionMatcher:
	var fixture_query:=PackedFloat32Array()
	func _update_query(_dt:float,_skeleton:Skeleton3D,_velocity:Vector3,_intent:Vector3,_facing:Vector3)->void:
		_query=fixture_query.duplicate()

class NativeFixture extends InkNativeMotionMatcher:
	var fixture_query:=PackedFloat32Array()
	func _update_query(_dt:float,_skeleton:Skeleton3D,_velocity:Vector3,_intent:Vector3,_facing:Vector3)->void:
		_query=fixture_query.duplicate()

var checks:=0
var failures:Array[String]=[]
var rows:Array[Dictionary]=[]
var native_requested:=false
var output:="res://shots/mm-discriminative-hysteresis.json"
var rig:Skeleton3D
var provider_queries:=0
var _f32_slot:=PackedFloat32Array([0.0])
var native_arithmetic_model:="uncontracted"

func _ready()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg=="--native-locomotion-mm":native_requested=true
		if arg.begins_with("--output="):output=arg.trim_prefix("--output=")
		if arg.begins_with("--native-f32-model="):native_arithmetic_model=arg.trim_prefix("--native-f32-model=")
	_check("declared native arithmetic model supported",native_arithmetic_model in ["uncontracted","arm64-fma"])
	if not failures.is_empty():_finish();return
	get_tree().create_timer(60.0).timeout.connect(func():push_error("MM_DISCRIMINATIVE watchdog");get_tree().quit(1))
	_run.call_deferred()

func _check(label:String,passed:bool,detail:Variant=null)->void:
	checks+=1
	if not passed:
		failures.append(label)
		push_error("MM_DISCRIMINATIVE "+label+" "+str(detail))

func _new_matcher(family:String,enabled:bool)->InkMotionMatcher:
	var matcher:InkMotionMatcher=NativeFixture.new() if native_requested else PortableFixture.new()
	matcher.discriminative_hysteresis_enabled=enabled
	_check("configure real provider "+family,matcher.configure(rig,family),matcher.debug_state())
	return matcher

func _run()->void:
	if native_requested:
		_check("native API registered",Native.available())
		if not Native.available():_finish();return
	var avatar:=Avatar.new()
	avatar.force_lod=1
	get_tree().root.add_child(avatar)
	await get_tree().process_frame
	rig=avatar._skeleton
	_check("source 87 bone skeleton",rig.get_bone_count()==87)
	var default_matcher:=Portable.new()
	_check("flag determines default only",default_matcher.discriminative_hysteresis_enabled==OS.get_cmdline_user_args().has("--mm-discriminative-hysteresis"))
	for family:String in Avatar.WEAPONS:
		var on:=_new_matcher(family,true)
		var off:=_new_matcher(family,false)
		_check("234 actual poses "+family,on._bucket.y-on._bucket.x==234)
		_check("63 dimensions "+family,on._query.size()==63)
		_mask_contract(on)
		var run_clip:=_action_clip(on,"run")
		var idle_clip:=_action_clip(on,"idle")
		var run_start:=int(on.database.clips[run_clip].start)
		var idle_start:=int(on.database.clips[idle_clip].start)
		for degrees:float in [-180.0,-90.0,-45.0,0.0,45.0,90.0,180.0]:
			var query:=_pose_query(on,run_start,deg_to_rad(degrees))
			var label:=family+" same clip theta "+str(degrees)
			var pair:=_pair_case(off,on,label,run_clip,.2,query,.14,false)
			_check(label+" exact nearest retains run phase zero",int(pair.best)==run_start,pair)
			_check(label+" decision improves",bool(pair.on.new_improved),pair)
			_check(label+" decision chooses phase",bool(pair.on_transition),pair)
			if degrees==0.0:
				_check(label+" zero common cost",absf(float(pair.on.common_cost))<1e-12,pair)
				_check(label+" zero-facing exact legacy ratio",pair.off.legacy_improved==pair.on.new_improved,pair)
				_check(label+" zero-facing identical state",pair.off_clip==pair.on_clip and pair.off_time==pair.on_time and pair.off_rate==pair.on_rate,pair)
			if absf(degrees)==180.0:
				_check(label+" known legacy suppression reproduced",not bool(pair.off.legacy_improved) and not bool(pair.off_transition),pair)
				_check(label+" actual transition added",int(pair.on.transition_changes)==1 and int(pair.on.added_transitions)==1,pair)
		var half_turn:=_pose_query(on,run_start,PI)
		var cooldown:=_pair_case(off,on,family+" cooldown retained",run_clip,.2,half_turn,.139,false)
		_check(family+" cooldown blocks corrected improvement",not bool(cooldown.on_transition) and int(cooldown.on.transition_changes)==0,cooldown)
		var near:=_pair_case(off,on,family+" near phase retained",run_clip,.1,half_turn,.14,false)
		_check(family+" phase distance gate retained",not bool(near.on_transition) and not bool(near.on.distance_ready),near)
		var boundary:=_pair_case(off,on,family+" 0.16 boundary retained",run_clip,.16,half_turn,.14,false)
		_check(family+" strict 0.16 distance boundary",not bool(boundary.on_transition) and not bool(boundary.on.distance_ready),boundary)
		var duration:=float(on.database.clips[run_clip].duration)
		var wrapped:=_pair_case(off,on,family+" circular phase retained",run_clip,duration-.1,half_turn,.14,false)
		_check(family+" cycle wrap uses shortest phase",absf(float(wrapped.on.distance_seconds)-.1)<1e-8 and not bool(wrapped.on_transition),wrapped)
		# A controlled blend gives a real nearest run row while keeping the old
		# ratio false. Only the query producer is replaced; both searches are real.
		var cross_query:=_pose_query(on,run_start,PI)
		var idle_query:=_pose_query(on,idle_start,PI)
		for d:int in cross_query.size():cross_query[d]=cross_query[d]*.65+idle_query[d]*.35
		var cross:=_pair_case(off,on,family+" cross clip",idle_clip,0.0,cross_query,.14,false)
		_check(family+" real cross clip candidate",int(cross.best)==run_start and int(cross.on_clip)==run_clip,cross)
		_check(family+" cross clip original ratio suppressed",not bool(cross.off.legacy_improved) and not bool(cross.off_transition),cross)
		_check(family+" cross clip corrected transition",bool(cross.on_transition) and int(cross.on.transition_changes)==1,cross)
		var bypass:=_pair_case(off,on,family+" original intent bypass",idle_clip,0.0,cross_query,.14,true)
		_check(family+" intent bypass still transitions both",bool(bypass.off_transition) and bool(bypass.on_transition) and bool(bypass.on.intent_change),bypass)
		_check(family+" bypass means no changed actual transition",int(bypass.on.predicate_changes)==1 and int(bypass.on.transition_changes)==0,bypass)
		var bypass_cooldown:=_pair_case(off,on,family+" bypass cooldown",idle_clip,0.0,cross_query,.139,true)
		_check(family+" intent bypass still respects cooldown",not bool(bypass_cooldown.off_transition) and not bool(bypass_cooldown.on_transition),bypass_cooldown)
		# This real binary32 threshold case differs from the double mathematical
		# ratio despite having zero shared cost. ON must retain the provider ratio.
		var boundary_query:=on._features.slice(run_start*63,(run_start+1)*63)
		for d:int in boundary_query.size():boundary_query[d]=float(on._features[run_start*63+d])*.132508129546182+float(on._features[(run_start+6)*63+d])*.867491870453818
		var zero_boundary:=_pair_case(off,on,family+" zero common binary32 boundary",run_clip,.2,boundary_query,.14,false)
		_check(family+" zero common state is exactly OFF",bool(zero_boundary.on.zero_common_passthrough) and zero_boundary.off_transition==zero_boundary.on_transition and zero_boundary.off_clip==zero_boundary.on_clip and zero_boundary.off_time==zero_boundary.on_time and zero_boundary.off_rate==zero_boundary.on_rate,zero_boundary)
		_check(family+" zero common never changes transition count",int(zero_boundary.on.predicate_changes)==0 and int(zero_boundary.on.transition_changes)==0,zero_boundary)
		if family=="shooter" and native_requested:
			var edge_reference:Dictionary=zero_boundary.reference.native_f32
			var expected_edge:bool=float(edge_reference.best_total)<float(edge_reference.continuation_total)*.72
			_check("known shooter binary32 boundary retains declared provider arithmetic",int(zero_boundary.best)==run_start+16 and bool(zero_boundary.off.legacy_improved)==expected_edge and bool(zero_boundary.on.new_improved)==expected_edge,zero_boundary)
			_check("known boundary double comparison retained as diagnosis",float(zero_boundary.reference.best_decision)<float(zero_boundary.reference.continuation_decision)*.72,zero_boundary)
		_clock_and_cadence_contract(off,on,family,run_clip,half_turn)
		_no_constant_passthrough_contract(off,on,family,run_clip,boundary_query)
		_varying_dimension_contract(on,family)
		var swap_family:String=Avatar.WEAPONS[(Avatar.WEAPONS.find(family)+1)%Avatar.WEAPONS.size()]
		on.set_weapon(swap_family)
		_check(family+" weapon swap invalidates decision attribution",String(on.debug_state().discriminative_hysteresis.last_query_weapon)=="" and not bool(on.debug_state().discriminative_hysteresis.decision_available))
	avatar.queue_free()
	await get_tree().process_frame
	_finish()

func _mask_contract(matcher:InkMotionMatcher)->void:
	var expected_constant:=PackedInt32Array()
	var dimensions:=int(matcher.database.dimensions)
	for d:int in dimensions:
		var first:=float(matcher._features[matcher._bucket.x*dimensions+d])
		var all_equal:=true
		for pose:int in range(matcher._bucket.x+1,matcher._bucket.y):
			if float(matcher._features[pose*dimensions+d])!=first:all_equal=false;break
		if all_equal:expected_constant.append(d)
	_check(matcher.weapon+" mask equals independent exact row equality",matcher._constant_dimensions==expected_constant,matcher.debug_state())
	_check(matcher.weapon+" present database constant dimensions",expected_constant==PackedInt32Array([42,43,44,47,50,53,56,59,62]),expected_constant)
	_check(matcher.weapon+" partition covers full dimensions",matcher._constant_dimensions.size()+matcher._decision_dimensions.size()==dimensions)

func _action_clip(matcher:InkMotionMatcher,action:String)->int:
	for index:int in matcher.database.clips.size():
		var record:Dictionary=matcher.database.clips[index]
		if record.weapon==matcher.weapon and record.action==action:return index
	return -1

func _pose_query(matcher:InkMotionMatcher,pose:int,theta:float)->PackedFloat32Array:
	var dimensions:=int(matcher.database.dimensions)
	var query:=matcher._features.slice(pose*dimensions,(pose+1)*dimensions)
	for index:int in matcher.database.trajectory_times.size():
		var d:=44+index*3
		var time:=float(matcher.database.trajectory_times[index])
		query[d]=(theta*(1.0-exp(-time*8.0))-matcher._mean[d])/matcher._std[d]
	return query

func _prepare(matcher:InkMotionMatcher,clip:int,time:float,query:PackedFloat32Array,since:float,abrupt:bool)->void:
	matcher.clip_index=clip
	matcher.sample_time=time
	matcher.playback_rate=1.0
	matcher.matched_pose=int(matcher.database.clips[clip].start)+mini(int(matcher.database.clips[clip].count)-1,int(time*float(matcher.database.fps)))
	matcher._since_transition=since
	matcher._first_step=false
	matcher._query_timer=0.0
	matcher._last_intent=Vector3.ZERO
	matcher.transition_count=0
	matcher.hysteresis_predicate_changes=0
	matcher.hysteresis_transition_changes=0
	matcher.hysteresis_added_transitions=0
	matcher.hysteresis_suppressed_transitions=0
	matcher.set("fixture_query",query)
	# The one step supplies the same intent to both providers/modes.
	if not abrupt:matcher._last_intent=Vector3.BACK*5.5

func _pair_case(off:InkMotionMatcher,on:InkMotionMatcher,label:String,clip:int,time:float,query:PackedFloat32Array,since:float,abrupt:bool)->Dictionary:
	_prepare(off,clip,time,query,since,abrupt)
	_prepare(on,clip,time,query,since,abrupt)
	var continuation:=off.matched_pose
	var before_off:int=int(off.get("native_query_count")) if native_requested else off.query_count
	var before_on:int=int(on.get("native_query_count")) if native_requested else on.query_count
	off.step(0.0,rig,Vector3.BACK*5.5,Vector3.BACK*5.5,Vector3.BACK,true,true)
	on.step(0.0,rig,Vector3.BACK*5.5,Vector3.BACK*5.5,Vector3.BACK,true,true)
	var after_off:int=int(off.get("native_query_count")) if native_requested else off.query_count
	var after_on:int=int(on.get("native_query_count")) if native_requested else on.query_count
	_check(label+" both real providers called",after_off==before_off+1 and after_on==before_on+1)
	provider_queries+=after_off-before_off+after_on-before_on
	if native_requested:
		_check(label+" native both evaluate actual 234 rows",int(off.get("native_poses_evaluated"))==234 and int(on.get("native_poses_evaluated"))==234)
	_check(label+" search candidate unchanged",off._best_pose==on._best_pose)
	_check(label+" search total exact unchanged",off.match_cost==on.match_cost and off.continuation_cost==on.continuation_cost)
	var reference:=_reference_query(on,query,continuation)
	_check(label+" independent exact nearest",on._best_pose==int(reference.best),reference)
	var arithmetic_difference:Dictionary={"best_provider_minus_double":on.match_cost-float(reference.best_total),"continuation_provider_minus_double":on.continuation_cost-float(reference.continuation_total)}
	if native_requested:
		var native_reference:=_reference_native_query(on,query,continuation)
		reference["native_f32"]=native_reference
		_check(label+" independent native f32 nearest",on._best_pose==int(native_reference.best),native_reference)
		# Compare the declared, independently verified compiled arithmetic exactly.
		# Never infer the model from returned costs or retry with a looser tolerance.
		_check(label+" reference total best",on.match_cost==float(native_reference.best_total),native_reference)
		_check(label+" reference total continuation",on.continuation_cost==float(native_reference.continuation_total),native_reference)
		arithmetic_difference["best_provider_minus_f32"]=on.match_cost-float(native_reference.best_total)
		arithmetic_difference["continuation_provider_minus_f32"]=on.continuation_cost-float(native_reference.continuation_total)
	else:
		_check(label+" reference total best",_near(on.match_cost,float(reference.best_total)),reference)
		_check(label+" reference total continuation",_near(on.continuation_cost,float(reference.continuation_total)),reference)
	var off_state:Dictionary=off.debug_state().discriminative_hysteresis
	var on_state:Dictionary=on.debug_state().discriminative_hysteresis
	_check(label+" default-off original ratio",off_state.legacy_improved==(off.match_cost<off.continuation_cost*.72) and off_state.new_improved==off_state.legacy_improved and not bool(off_state.decision_available),off_state)
	var zero_common:=float(reference.common)==0.0
	_check(label+" exact zero common passthrough classification",bool(on_state.zero_common_passthrough)==zero_common,on_state)
	_check(label+" current query weapon attribution",String(on_state.last_query_weapon)==on.weapon and String(off_state.last_query_weapon)==off.weapon)
	if zero_common:
		_check(label+" exact provider best cost passthrough",float(on_state.best_decision_cost)==on.match_cost,on_state)
		_check(label+" exact provider continuation cost passthrough",float(on_state.continuation_decision_cost)==on.continuation_cost,on_state)
	else:
		_check(label+" directly summed decision best",_near(float(on_state.best_decision_cost),float(reference.best_decision)),on_state)
		_check(label+" directly summed decision continuation",_near(float(on_state.continuation_decision_cost),float(reference.continuation_decision)),on_state)
	_check(label+" shared constant cost",_near(float(on_state.common_cost),float(reference.common)),on_state)
	var expected_improved:=on.match_cost<on.continuation_cost*.72 if zero_common else float(reference.best_decision)<float(reference.continuation_decision)*.72
	_check(label+" exact corrected ratio",on_state.new_improved==expected_improved,on_state)
	var expected_off:=bool(off_state.cooldown_ready) and (bool(off_state.legacy_improved) or bool(off_state.intent_change)) and bool(off_state.distance_ready)
	var expected_on:=bool(on_state.cooldown_ready) and (bool(on_state.new_improved) or bool(on_state.intent_change)) and bool(on_state.distance_ready)
	_check(label+" unchanged transition gates off",off.transitioned==expected_off,off_state)
	_check(label+" unchanged transition gates on",on.transitioned==expected_on,on_state)
	var result:Dictionary={"label":label,"best":on._best_pose,"continuation":continuation,"off":off_state,"on":on_state,"off_transition":off.transitioned,"on_transition":on.transitioned,"off_clip":off.clip_index,"on_clip":on.clip_index,"off_time":off.sample_time,"on_time":on.sample_time,"off_rate":off.playback_rate,"on_rate":on.playback_rate,"reference":reference,"arithmetic_difference":arithmetic_difference}
	rows.append(result)
	return result

func _reference_query(matcher:InkMotionMatcher,query:PackedFloat32Array,continuation:int)->Dictionary:
	var best:=continuation
	var continuation_total:=_reference_cost(matcher,query,continuation,false)
	var best_total:=continuation_total
	for pose:int in range(matcher._bucket.x,matcher._bucket.y):
		var cost:=_reference_cost(matcher,query,pose,false)
		if cost<best_total:best_total=cost;best=pose
	var common:=0.0
	for d:int in matcher._constant_dimensions:
		var delta:=float(matcher._features[matcher._bucket.x*int(matcher.database.dimensions)+d])-float(query[d])
		common+=delta*delta*float(matcher._weights[d])
	return {"best":best,"best_total":best_total,"continuation_total":continuation_total,"best_decision":_reference_cost(matcher,query,best,true),"continuation_decision":_reference_cost(matcher,query,continuation,true),"common":common}

func _reference_cost(matcher:InkMotionMatcher,query:PackedFloat32Array,pose:int,skip_constant:bool)->float:
	var dimensions:=int(matcher.database.dimensions)
	var total:=0.0
	# Separate implementation intentionally uses a full ordered scan, no pruning.
	for ordered:int in dimensions:
		var d:=(ordered+42)%dimensions
		if skip_constant and matcher._constant_dimensions.has(d):continue
		var delta:=float(matcher._features[pose*dimensions+d])-float(query[d])
		total+=delta*delta*float(matcher._weights[d])
	return total

func _round_f32(value:float)->float:
	# A reusable PackedFloat32Array element performs the same binary32 rounding
	# after each primitive operation without allocating a new array per term.
	_f32_slot[0]=value
	return float(_f32_slot[0])

func _reference_native_cost(matcher:InkMotionMatcher,query:PackedFloat32Array,pose:int)->float:
	var dimensions:=int(matcher.database.dimensions)
	var total:=0.0
	for d:int in dimensions:
		var delta:=_round_f32(float(matcher._features[pose*dimensions+d])-float(query[d]))
		var square:=_round_f32(delta*delta)
		if native_arithmetic_model=="arm64-fma":
			# Observed ARM64 external loop: fsub, fmul, fmadd. For these frozen
			# diagnostic inputs the double intermediate matches exact rational FMA;
			# the independent audit checks that before accepting this model.
			total=_round_f32(square*float(matcher._weights[d])+total)
		else:
			var weighted:=_round_f32(square*float(matcher._weights[d]))
			total=_round_f32(total+weighted)
	return total

func _reference_native_query(matcher:InkMotionMatcher,query:PackedFloat32Array,continuation:int)->Dictionary:
	# External native animation blocks are ordered by the library name list,
	# so retain that mapping when resolving exact ties in the independent scan.
	var native_order:PackedInt32Array=matcher.get("_native_to_source")
	var best:=-1
	var best_total:=_round_f32(3.4028234663852886e38)
	for pose:int in native_order:
		var cost:=_reference_native_cost(matcher,query,pose)
		if cost<best_total:best_total=cost;best=pose
	return {"best":best,"best_total":best_total,"continuation_total":_reference_native_cost(matcher,query,continuation),"arithmetic_model":native_arithmetic_model,"arithmetic":"binary32 delta/square/fmadd in dimension order 0..62" if native_arithmetic_model=="arm64-fma" else "binary32 delta/square/weight/add in dimension order 0..62","rounding":"PackedFloat32Array reusable slot after each compiled primitive operation","rows_evaluated":native_order.size()}

func _near(a:float,b:float)->bool:
	return absf(a-b)<=maxf(1.0,absf(b))*1e-7

func _clock_and_cadence_contract(off:InkMotionMatcher,on:InkMotionMatcher,family:String,clip:int,query:PackedFloat32Array)->void:
	_prepare(off,clip,.21,query,.2,false)
	_prepare(on,clip,.21,query,.2,false)
	# No query: both clocks and rate smoothing must remain bit-identical.
	off._query_timer=.4
	on._query_timer=.4
	var qoff:=off.query_count
	var qon:=on.query_count
	for frame:int in 7:
		off.step(1.0/60.0,rig,Vector3.BACK*2.7,Vector3.BACK*5.5,Vector3.BACK,true,true)
		on.step(1.0/60.0,rig,Vector3.BACK*2.7,Vector3.BACK*5.5,Vector3.BACK,true,true)
		_check(family+" exact clock/rate with unchanged cadence %d"%frame,off.sample_time==on.sample_time and off.playback_rate==on.playback_rate and off.matched_pose==on.matched_pose)
	_check(family+" cadence suppressed query unchanged",off.query_count==qoff and on.query_count==qon)
	# Query cooldown, remote interval and disabled matching remain original.
	for matcher:InkMotionMatcher in [off,on]:
		_prepare(matcher,clip,.2,query,.2,false)
		matcher.step(0.0,rig,Vector3.BACK*5.5,Vector3.BACK*5.5,Vector3.BACK,false,true)
		_check(family+" remote 0.125 cadence",matcher._query_timer==.125)
		var count:=matcher.query_count
		matcher.step(.01,rig,Vector3.BACK*5.5,Vector3.BACK*5.5,Vector3.BACK,false,true)
		_check(family+" remote interval skips search",matcher.query_count==count)
		matcher._query_timer=0.0
		matcher.step(.01,rig,Vector3.BACK*5.5,Vector3.BACK*5.5,Vector3.BACK,true,false)
		_check(family+" disabled matching skips search",matcher.query_count==count)

func _varying_dimension_contract(matcher:InkMotionMatcher,family:String)->void:
	var dimensions:=int(matcher.database.dimensions)
	# Change only the in-memory diagnostic feature copy, restore before returning.
	# No file, native provider database, or normalized source data is rewritten.
	var pose:=matcher._bucket.x+1
	var d:=47
	var at:=pose*dimensions+d
	var original:=float(matcher._features[at])
	matcher._features[at]=original+.125
	matcher._classify_decision_dimensions()
	_check(family+" future varying yaw retained",matcher._decision_dimensions.has(d) and not matcher._constant_dimensions.has(d))
	matcher._features[at]=original
	matcher._classify_decision_dimensions()
	_check(family+" exact mask restored",matcher._constant_dimensions.has(d) and not matcher._decision_dimensions.has(d))
	# A very small but nonzero stored value also counts as variation.
	d=42
	at=pose*dimensions+d
	original=float(matcher._features[at])
	matcher._features[at]=1e-12
	matcher._classify_decision_dimensions()
	_check(family+" exact tiny variation retained",matcher._decision_dimensions.has(d))
	matcher._features[at]=original
	matcher._classify_decision_dimensions()

func _rebuild_fixture_native(matcher:InkMotionMatcher)->void:
	if not native_requested:return
	# Only these diagnostic instances receive the temporary derived feature
	# database. The shared Native cache and source files remain untouched.
	var actual:=matcher as InkNativeMotionMatcher
	var bundle:=actual._build_native_database(actual.weapon)
	_check(actual.weapon+" derived native fixture schema accepted",not bundle.is_empty(),bundle)
	if bundle.is_empty():return
	actual._native_library=bundle.library as AnimationLibrary
	actual._native_to_source=bundle.native_to_source
	actual._source_to_native=bundle.source_to_native

func _no_constant_passthrough_contract(off:InkMotionMatcher,on:InkMotionMatcher,family:String,clip:int,query:PackedFloat32Array)->void:
	var constants:=on._constant_dimensions.duplicate()
	var saved:=PackedFloat32Array()
	var dimensions:=int(on.database.dimensions)
	var pose:=on._bucket.x+1
	for d:int in constants:
		var at:=pose*dimensions+d
		saved.append(on._features[at])
		on._features[at]=float(on._features[at])+.125
	on._classify_decision_dimensions()
	_check(family+" derived future bucket has no constant feature",on._constant_dimensions.is_empty() and on._decision_dimensions.size()==dimensions)
	_rebuild_fixture_native(off)
	_rebuild_fixture_native(on)
	var pair:=_pair_case(off,on,family+" future no constant passthrough",clip,.2,query,.14,false)
	_check(family+" no constant uses exact provider ratio",bool(pair.on.zero_common_passthrough) and pair.off.legacy_improved==pair.on.new_improved and pair.off_transition==pair.on_transition and pair.off_clip==pair.on_clip and pair.off_time==pair.on_time and pair.off_rate==pair.on_rate,pair)
	_check(family+" no constant has no affected transition",int(pair.on.predicate_changes)==0 and int(pair.on.transition_changes)==0,pair)
	for index:int in constants.size():on._features[pose*dimensions+constants[index]]=saved[index]
	on._classify_decision_dimensions()
	_rebuild_fixture_native(off)
	_rebuild_fixture_native(on)
	_check(family+" derived fixture restores exact source mask",on._constant_dimensions==constants)

func _finish()->void:
	var report:Dictionary={"diagnostic_only":true,"accepted_for_production":false,"real_game_input":false,"query_fixture":true,"native_requested":native_requested,"provider":"native MMAnimationLibrary exact query" if native_requested else "portable InkMotionMatcher exact query","provider_queries_in_pairs":provider_queries,"checks":checks,"failures":failures,"cases":rows}
	report["native_arithmetic_model"]=native_arithmetic_model
	report["os"]=OS.get_name()
	var directory:=output.get_base_dir()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var file:=FileAccess.open(output,FileAccess.WRITE)
	if file==null:push_error("MM_DISCRIMINATIVE report write failed "+output);get_tree().quit(1);return
	file.store_string(JSON.stringify(report,"\t"))
	file.close()
	print("MM_DISCRIMINATIVE ",checks," checks; ",failures.size()," failures; ",provider_queries," paired real queries; ",output)
	get_tree().quit(1 if not failures.is_empty() else 0)
