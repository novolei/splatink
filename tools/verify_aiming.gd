extends SceneTree
## Root's serialized PC check: source pitch limits and actual hand grip errors.
const Avatar = preload("res://scripts/characters/ink_avatar.gd")
var checks := 0
var failures := 0
func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("AIM_CONTRACT watchdog"); quit(1))
	call_deferred("_run")
func _check(label: String, passed: bool, detail: Variant = null) -> void:
	checks += 1
	if not passed:
		failures += 1
		push_error("AIM_CONTRACT "+label+" "+str(detail))
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var avatar := Avatar.new()
	avatar.force_lod = 0
	world.add_child(avatar)
	await process_frame
	var max_right := 0.0
	var max_left := 0.0
	for weapon in Avatar.WEAPONS:
		avatar.configure(Color("ff8a14"),weapon,{"hair":1,"outfit":2})
		for pitch in [-1.0,0.0,1.15]:
			for frame in 90:
				avatar.animate(1.0/60.0,{"grounded":true,"form":"kid","firing":true,"rolling":weapon=="roller","aim_pitch":pitch,"speed":0.0,"velocity":Vector3.ZERO,"is_local":true})
			_check("finite virtual muzzle "+weapon+str(pitch),avatar.get_aim_muzzle(pitch).is_finite())
			_check("finite aimed rig "+weapon+str(pitch),_finite(avatar._skeleton))
			if weapon!="roller" and pitch!=0.0:
				_check("pitched arm solver "+weapon+str(pitch),avatar._arm_aim.enabled)
				var right := avatar._skeleton.get_bone_global_pose(avatar._skeleton.find_bone("handR")).origin.distance_to(avatar._arm_aim.target_right.origin)
				max_right = maxf(max_right,right)
				_check("source right grip below 1cm "+weapon+str(pitch),right<0.01,right)
				var data: Dictionary = avatar._aim_frames.weapons[weapon]
				if weapon=="slosher": print("AIM_SLOSHER ",JSON.stringify({"pitch":pitch,"right_error":right,"right_target":avatar._arm_aim.target_right.origin,"right_hand":avatar._skeleton.get_bone_global_pose(avatar._skeleton.find_bone("handR")).origin,"right_shoulder":avatar._skeleton.get_bone_global_pose(avatar._skeleton.find_bone("uArmR")).origin,"weapon_pivot":avatar._weapon_r.transform,"weapon_offset":avatar._weapon_offset.transform,"arm":avatar._arm_aim._arms[0],"parent_class":avatar._weapon_r.get_class(),"parent":avatar._weapon_r.get_parent().name}))
				if weapon=="dualies" or int(data.hold.twoAim)==1:
					var left := avatar._skeleton.get_bone_global_pose(avatar._skeleton.find_bone("handL")).origin.distance_to(avatar._arm_aim.target_left.origin)
					max_left = maxf(max_left,left)
					_check("source support grip below 1cm "+weapon+str(pitch),left<0.01,left)
	print("AIM_CONTRACT ",checks," checks; ",failures," failures; max_right_grip_m=",max_right," max_left_grip_m=",max_left)
	quit(1 if failures else 0)
func _finite(skeleton: Skeleton3D) -> bool:
	for index in skeleton.get_bone_count():
		if not skeleton.get_bone_pose_position(index).is_finite() or not skeleton.get_bone_pose_rotation(index).is_finite(): return false
	return true
