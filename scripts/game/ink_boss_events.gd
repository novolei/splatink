class_name InkBossEvents
extends RefCounted

## The original BossAnimator's discrete hooks sampled beside the source clips.
## Phase time is normalized to the active move, so PACE never desynchronizes the hooks.
static var _clips:Dictionary={}
var clip:String=""
var time:float=0.0
var _starting:bool=true
var duration:float=0.0
var scale:float=1.0
var looping:bool=false
var events:Array=[]

func _init() -> void:
	if _clips.is_empty():
		var parsed=JSON.parse_string(FileAccess.get_file_as_string("res://data/boss_events.json"))
		if parsed is Dictionary:_clips=parsed.get("clips",{})

func play(name:String,actual_duration:float=-1.0,phase:int=1) -> void:
	clip=name;time=0.0;_starting=true;events=[];duration=0.0;scale=1.0
	looping=name.ends_with("_idle") or name.ends_with("_run") or name.ends_with("_stun")
	var record:Dictionary=_clips.get(name,{})
	if record.is_empty():return
	duration=float(record.duration)
	scale=duration/actual_duration if actual_duration>0.0 else 1.0
	var variants:Dictionary=record.get("phase_events",{})
	events=variants.get(str(phase),record.get("events",[]))

func advance(dt:float) -> Array[Dictionary]:
	var fired:Array[Dictionary]=[]
	if duration<=0 or dt<=0:return fired
	var previous:float=-0.000001 if _starting else time
	_starting=false
	time+=dt*scale
	# A bounded dt can cross multiple loop cycles; enumerate the actual crossed intervals.
	while looping and time>=duration:
		_collect(previous,duration,fired)
		time-=duration;previous=-0.000001
	_collect(previous,minf(time,duration),fired)
	return fired

func _collect(begin:float,end:float,output:Array[Dictionary]) -> void:
	for event:Dictionary in events:
		var stamp:float=float(event.time)
		if stamp>begin and stamp<=end:output.append(event)
