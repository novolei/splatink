extends SceneTree
## Structural GPU-resource contract. It does not measure frame time or compare
## rendered pixels; tests/bloom_gpu_contract.gd remains the bloom image oracle.
var _grade:RefCounted
var _rd:RenderingDevice
var _output:String="res://shots/compositor-framebuffer-cache.json"
var _report:Dictionary={"version":2,"checks":0,"failures":[],"cases":[],"performance_measured":false,"pixel_equivalence_measured":false}

func _initialize()->void:
	for arg:String in OS.get_cmdline_user_args():
		if arg.begins_with("--framebuffer-cache-output="):_output=arg.trim_prefix("--framebuffer-cache-output=")
	create_timer(30.0).timeout.connect(func():push_error("FRAMEBUFFER_CACHE watchdog");quit(1))
	_run.call_deferred()

func _run()->void:
	# Load after SceneTree initialization, including when tools/ is gdignored.
	var script:Script=load("res://scripts/world/ink_grade.gd")
	if script==null:
		_check("grade script loaded",false);_finish();return
	_grade=script.new()
	# InkGrade queues shader initialization before this callable.
	RenderingServer.call_on_render_thread(_gpu_run)

func _check(label:String,passed:bool)->void:
	_report.checks=int(_report.checks)+1
	if not passed:_report.failures.append(label);push_error("FRAMEBUFFER_CACHE "+label)

func _gpu_run()->void:
	_rd=RenderingServer.get_rendering_device()
	if _rd==null:
		_check("RenderingDevice available",false);_finish.call_deferred();return
	if _grade.get("_rd")!=_rd:
		_check("grade render-thread initialization completed",false);_finish.call_deferred();return
	var bloom_script:Script=load("res://scripts/world/ink_bloom.gd")
	var bloom:RefCounted=bloom_script.new()
	bloom.set("_rd",_rd)
	_exercise(bloom,"bloom")
	_exercise_shared_contexts(bloom,"bloom")
	_exercise(_grade,"grade")
	_exercise_shared_contexts(_grade,"grade")
	bloom.call("release")
	bloom.call("release")
	_check("bloom repeated release leaves no cache",_cache(bloom).is_empty())
	# Leave live attachments in both caches so PREDELETE must release both.
	var grade_target:RID=_texture(Vector2i(17,13),RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	var bloom_target:RID=_texture(Vector2i(9,7),RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	var grade_fb:RID=_grade.call("_framebuffer_for_output",grade_target)
	var owned_bloom:RefCounted=_grade.get("_bloom")
	var bloom_fb:RID=owned_bloom.call("_framebuffer_for_output",bloom_target)
	_drop_grade.call_deferred(grade_fb,bloom_fb,grade_target,bloom_target)

func _cache(helper:RefCounted)->Dictionary:
	return helper.get("_framebuffers")

func _memberships(helper:RefCounted,target:RID)->Dictionary:
	var cached:Dictionary=_cache(helper).get(target,{})
	return cached.get("contexts",{})

func _valid_framebuffer(framebuffer:RID)->bool:
	return framebuffer.is_valid() and _rd.framebuffer_is_valid(framebuffer)

func _texture(size:Vector2i,data_format:int)->RID:
	var format:=RDTextureFormat.new()
	format.width=size.x;format.height=size.y;format.format=data_format
	format.usage_bits=RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT|RenderingDevice.TEXTURE_USAGE_COLOR_ATTACHMENT_BIT
	var arrays:Array[PackedByteArray]=[]
	return _rd.texture_create(format,RDTextureView.new(),arrays)

func _exercise(helper:RefCounted,label:String)->void:
	var size:=Vector2i(64,48)
	var owner_a:RefCounted=RefCounted.new()
	var owner_b:RefCounted=RefCounted.new()
	var context_a:int=owner_a.get_instance_id()
	var context_b:int=owner_b.get_instance_id()
	helper.call("_prepare_framebuffer_cache",size,context_a,owner_a)
	var first:RID=_texture(size,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	var sibling:RID=_texture(size,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	var different:RID=_texture(size,RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM)
	_check(label+" attachment textures created",first.is_valid() and sibling.is_valid() and different.is_valid())
	if not first.is_valid() or not sibling.is_valid() or not different.is_valid():
		for target:RID in [first,sibling,different]:
			if target.is_valid():_rd.free_rid(target)
		return
	var initial:RID=helper.call("_framebuffer_for_output",first)
	var sibling_fb:RID=helper.call("_framebuffer_for_output",sibling)
	var different_fb:RID=helper.call("_framebuffer_for_output",different)
	_check(label+" three framebuffers valid",_valid_framebuffer(initial) and _valid_framebuffer(sibling_fb) and _valid_framebuffer(different_fb))
	_check(label+" output RIDs stay distinct",initial!=sibling_fb and initial!=different_fb and sibling_fb!=different_fb)
	_check(label+" same data format shares pipeline format",_rd.framebuffer_get_format(initial)==_rd.framebuffer_get_format(sibling_fb))
	_check(label+" different data format has distinct pipeline format",_rd.framebuffer_get_format(initial)!=_rd.framebuffer_get_format(different_fb))
	var stable_reuses:int=0
	for iteration in 128:
		helper.call("_prepare_framebuffer_cache",size,context_a,owner_a)
		var reused:RID=helper.call("_framebuffer_for_output",first)
		if reused==initial:stable_reuses+=1
	_check(label+" 128 accesses reuse exact framebuffer RID",stable_reuses==128)
	_check(label+" stable cache count remains three",_cache(helper).size()==3)
	# Real texture formats are immutable. Corrupt the stored format deliberately
	# to verify the guard recreates instead of accepting a mismatched cache row.
	var cache:Dictionary=_cache(helper)
	var row:Dictionary=cache[first]
	row.texture_format=RenderingDevice.DATA_FORMAT_R8G8B8A8_UNORM
	var repaired:RID=helper.call("_framebuffer_for_output",first)
	_check(label+" cached format mismatch recreates",repaired!=initial and _valid_framebuffer(repaired) and not _valid_framebuffer(initial))
	_check(label+" format repair replaces rather than grows",_cache(helper).size()==3)
	helper.call("_prepare_framebuffer_cache",Vector2i(65,49),context_a,owner_a)
	_check(label+" resize clears cached framebuffers",_cache(helper).is_empty() and not _valid_framebuffer(repaired) and not _valid_framebuffer(sibling_fb) and not _valid_framebuffer(different_fb))
	_check(label+" resize keeps caller-owned attachments",_rd.texture_is_valid(first) and _rd.texture_is_valid(sibling) and _rd.texture_is_valid(different))
	var resized:RID=_texture(Vector2i(65,49),RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	var after_resize:RID=helper.call("_framebuffer_for_output",resized)
	helper.call("_prepare_framebuffer_cache",size,context_b,owner_b)
	var other_context_fb:RID=helper.call("_framebuffer_for_output",sibling)
	var interleaved_reuses:int=0
	for iteration in 64:
		helper.call("_prepare_framebuffer_cache",Vector2i(65,49),context_a,owner_a)
		if helper.call("_framebuffer_for_output",resized)==after_resize:interleaved_reuses+=1
		helper.call("_prepare_framebuffer_cache",size,context_b,owner_b)
		if helper.call("_framebuffer_for_output",sibling)==other_context_fb:interleaved_reuses+=1
	_check(label+" main/reflection context alternation reuses",interleaved_reuses==128 and _cache(helper).size()==2)
	helper.call("_prepare_framebuffer_cache",Vector2i(66,50),context_b,owner_b)
	_check(label+" resizing one context preserves the other",not _valid_framebuffer(other_context_fb) and _valid_framebuffer(after_resize) and _cache(helper).size()==1)
	owner_a=null
	helper.call("_prepare_framebuffer_cache",Vector2i(66,50),context_b,owner_b)
	_check(label+" deleted context is pruned",not _valid_framebuffer(after_resize) and _cache(helper).is_empty() and _rd.texture_is_valid(resized))
	var before_attachment_free:RID=helper.call("_framebuffer_for_output",resized)
	_rd.free_rid(resized)
	_check(label+" attachment free invalidates framebuffer",not _valid_framebuffer(before_attachment_free))
	helper.call("_prepare_framebuffer_cache",Vector2i(66,50),context_b,owner_b)
	_check(label+" automatic invalidation is pruned",_cache(helper).is_empty())
	_rd.free_rid(first);_rd.free_rid(sibling);_rd.free_rid(different)
	var maximum_live:int=0
	for iteration in 32:
		helper.call("_prepare_framebuffer_cache",Vector2i(65,49),context_b,owner_b)
		var replaced:RID=_texture(Vector2i(65,49),RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
		var replacement_fb:RID=helper.call("_framebuffer_for_output",replaced)
		_check(label+" replacement %d valid"%iteration,_valid_framebuffer(replacement_fb))
		maximum_live=maxi(maximum_live,_cache(helper).size())
		_rd.free_rid(replaced)
	helper.call("_prepare_framebuffer_cache",Vector2i(65,49),context_b,owner_b)
	_check(label+" replacement loop has bounded live cache",maximum_live==1 and _cache(helper).is_empty())
	var surviving:RID=_texture(size,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	var surviving_fb:RID=helper.call("_framebuffer_for_output",surviving)
	helper.call("_clear_framebuffer_cache")
	helper.call("_clear_framebuffer_cache")
	_check(label+" repeated clear is idempotent",_cache(helper).is_empty() and not _valid_framebuffer(surviving_fb) and _rd.texture_is_valid(surviving))
	_rd.free_rid(surviving)
	_report.cases.append({"helper":label,"stable_reuses":stable_reuses,"interleaved_context_reuses":interleaved_reuses,"replacement_cycles":32,"maximum_replacement_live_cache":maximum_live,"formats":["rgba16f","rgba8"],"sizes":[[64,48],[65,49],[66,50]],"context_ids":[str(context_a),str(context_b)],"caller_owns_textures":true})

func _exercise_shared_contexts(helper:RefCounted,label:String)->void:
	var size:=Vector2i(21,15)
	var owner_a:RefCounted=RefCounted.new()
	var owner_b:RefCounted=RefCounted.new()
	var context_a:int=owner_a.get_instance_id()
	var context_b:int=owner_b.get_instance_id()
	var target:RID=_texture(size,RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT)
	helper.call("_prepare_framebuffer_cache",size,context_a,owner_a)
	var framebuffer:RID=helper.call("_framebuffer_for_output",target)
	helper.call("_prepare_framebuffer_cache",size,context_b,owner_b)
	var reused:RID=helper.call("_framebuffer_for_output",target)
	var membership:Dictionary=_memberships(helper,target)
	_check(label+" shared output reuses exact framebuffer",reused==framebuffer and _cache(helper).size()==1)
	_check(label+" shared output records both contexts",membership.size()==2 and membership.has(context_a) and membership.has(context_b))
	helper.call("_prepare_framebuffer_cache",size+Vector2i.ONE,context_a,owner_a)
	membership=_memberships(helper,target)
	_check(label+" shared output survives first owner resize",_valid_framebuffer(framebuffer) and membership.size()==1 and membership.has(context_b) and not membership.has(context_a))
	helper.call("_prepare_framebuffer_cache",size,context_a,owner_a)
	_check(label+" shared output can rejoin without allocation",helper.call("_framebuffer_for_output",target)==framebuffer and _memberships(helper,target).size()==2)
	owner_b=null
	helper.call("_prepare_framebuffer_cache",size,context_a,owner_a)
	membership=_memberships(helper,target)
	_check(label+" shared output survives other owner deletion",_valid_framebuffer(framebuffer) and membership.size()==1 and membership.has(context_a) and not membership.has(context_b))
	var replacement_owner:RefCounted=RefCounted.new()
	var replacement_context:int=replacement_owner.get_instance_id()
	helper.call("_prepare_framebuffer_cache",size,replacement_context,replacement_owner)
	_check(label+" shared output joins a replacement owner",helper.call("_framebuffer_for_output",target)==framebuffer and _memberships(helper,target).size()==2)
	helper.call("_clear_framebuffer_cache")
	helper.call("_clear_framebuffer_cache")
	_check(label+" shared full clear releases single cache entry",_cache(helper).is_empty() and not _valid_framebuffer(framebuffer) and _rd.texture_is_valid(target))
	_rd.free_rid(target)
	_report.cases.append({"helper":label,"case":"shared_output_context_membership","context_ids":[str(context_a),str(context_b),str(replacement_context)],"maximum_live_cache":1,"contexts_before_full_clear":2,"caller_owns_textures":true})

func _drop_grade(grade_fb:RID,bloom_fb:RID,grade_target:RID,bloom_target:RID)->void:
	_grade=null
	# PREDELETE queued its static cleanup before this final render-thread check.
	RenderingServer.call_on_render_thread(_gpu_verify_teardown.bind(grade_fb,bloom_fb,grade_target,bloom_target))

func _gpu_verify_teardown(grade_fb:RID,bloom_fb:RID,grade_target:RID,bloom_target:RID)->void:
	_check("grade PREDELETE releases its framebuffer",not _valid_framebuffer(grade_fb))
	_check("grade PREDELETE releases owned bloom framebuffer",not _valid_framebuffer(bloom_fb))
	_check("grade PREDELETE keeps external attachments",_rd.texture_is_valid(grade_target) and _rd.texture_is_valid(bloom_target))
	_rd.free_rid(grade_target);_rd.free_rid(bloom_target)
	_finish.call_deferred()

func _finish()->void:
	_report.limitations=["No frame-time measurement or GPU-present timestamps.","No rendered-pixel comparison; run the existing bloom GPU contract separately.","Bounded resource counts cover stable targets and attachment replacement; production multi-view and resize still need a real main-scene check."]
	var file:=FileAccess.open(_output,FileAccess.WRITE)
	if not file:_check("report file written",false)
	_report.structural_pass=(_report.failures as Array).is_empty() and int(_report.checks)>0
	if file:file.store_string(JSON.stringify(_report,"\t"));file.close()
	print("FRAMEBUFFER_CACHE_CONTRACT "+JSON.stringify(_report))
	quit(0 if (_report.failures as Array).is_empty() else 1)
