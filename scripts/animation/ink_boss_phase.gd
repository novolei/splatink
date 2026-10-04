class_name InkBossPhase
extends RefCounted
## Preserve the original live tear spring across phase-specific sampled clips.
## Call after AnimationPlayer.advance, using BossChannels1.x as baked tear.
var _rig: Skeleton3D
var _left := -1
var _right := -1
var _abdomen := -1

func configure(root: Node3D) -> void:
	var rigs := root.find_children("*","Skeleton3D",true,false)
	_rig = rigs[0] as Skeleton3D if not rigs.is_empty() else null
	if _rig==null: return
	_left = _rig.find_bone("tearL")
	_right = _rig.find_bone("tearR")
	_abdomen = _rig.find_bone("abdomen")

func apply(tear: float, baked_tear: float = 0.0) -> void:
	if _rig==null or _left<0 or _right<0: return
	# bossAnim._apply sets these local bases directly, retaining overshoot.
	_rig.set_bone_pose_rotation(_left,Quaternion(Vector3(0,0,1),-1.9*tear))
	_rig.set_bone_pose_rotation(_right,Quaternion(Vector3(0,0,1),1.9*tear))
	if _abdomen>=0:
		var scale := _rig.get_bone_pose_scale(_abdomen)
		_rig.set_bone_pose_scale(_abdomen,scale+Vector3.ONE*(tear-baked_tear)*0.03)
