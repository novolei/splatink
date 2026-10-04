extends SceneTree
## Run with the root's serialized Godot wrapper after import:
## godot --headless --path splatink --script res://tools/verify_characters.gd
## Functional resource/animation contract checks; no screenshot or FPS claim.

const Avatar = preload("res://scripts/characters/ink_avatar.gd")
const BossPhase = preload("res://scripts/animation/ink_boss_phase.gd")
var checks: Array[Dictionary] = []
var failures: int = 0
var world: Node3D

func _initialize() -> void:
	create_timer(30.0).timeout.connect(_watchdog)
	call_deferred("_run")

func _watchdog() -> void:
	push_error("CHARACTER_CONTRACT timed out after 30 seconds")
	quit(1)

func _check(name: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name": name, "passed": passed, "detail": detail})
	if not passed:
		failures += 1
		push_error("CHARACTER CHECK FAILED: " + name + " " + str(detail))

func _run() -> void:
	world = Node3D.new()
	world.name = "CharacterContractWorld"
	root.add_child(world)
	var camera := Camera3D.new()
	camera.position = Vector3(0, 1.0, 4.0)
	world.add_child(camera)
	camera.current = true
	var avatar := Avatar.new()
	avatar.force_lod = 0
	world.add_child(avatar)
	await process_frame
	var tree := avatar.get_node_or_null("AvatarAnimationTree") as AnimationTree
	_check("animation_tree_created", tree != null)
	if tree == null:
		_finish()
		return
	_check("animation_tree_active", tree.active)
	var body_player := Avatar._find_type(avatar, "AnimationPlayer") as AnimationPlayer
	_check("source_body_animation_count", body_player != null and body_player.get_animation_list().size() >= 187, body_player.get_animation_list().size() if body_player else 0)
	var rig := Avatar._find_type(avatar, "Skeleton3D") as Skeleton3D
	_check("source_body_bone_count", rig != null and rig.get_bone_count() == 87, rig.get_bone_count() if rig else 0)
	_check("seven_source_face_channels",avatar._face_nodes.size()==7 and avatar._face_nodes[0]!=null)
	for wrapper_name:String in ["Skin","Cloth","Hair"]:
		var mesh:=avatar.find_child(wrapper_name,true,false) as MeshInstance3D
		var material:=mesh.material_override as ShaderMaterial
		var rim:Variant=material.get_shader_parameter("uIwRim")
		_check("source_showcase_final_rim_"+wrapper_name,rim is Vector4 and (rim as Vector4).distance_to(Vector4(.075,.08125,.09375,3.4))<.00001)
		_check("source_final_fill_wrapper_"+wrapper_name,material.shader.code.contains("EMISSION+=uIwFill*diffuseColor.rgb*rim_fill*rim_fill"))
	for mesh_name in ["Skin", "Cloth", "Eyes", "SkinGame", "ClothGame", "EyesGame", "SkinFar", "ClothFar", "EyesFar"]:
		var mesh := avatar.find_child(mesh_name, true, false) as MeshInstance3D
		_check("source_attribute_png_" + mesh_name, _attribute_position_matches(mesh))
		_check("source_smooth_normals_" + mesh_name, _attribute_position_matches(mesh,true))
	for weapon in Avatar.WEAPONS:
		avatar.configure(Color("ff8a14"), weapon, {"hair": 0, "hat": 0, "skin": 0, "outfit": 0, "eyes": 0, "brows": 0})
		var state: Dictionary = {"is_local": true, "speed": 4.0, "velocity": Vector3(1.0, 0.0, 4.0), "grounded": true, "firing": true, "rolling": weapon == "roller", "charge": 0.65 if weapon in ["charger", "splatling"] else 0.0, "form": "kid", "aim_pitch": 0.2, "tank": 0.6}
		for tick in 48:
			avatar.animate(1.0 / 60.0, state)
		_check("weapon_" + weapon + "_muzzle_finite", avatar.get_muzzle().is_finite(), str(avatar.get_muzzle()))
		_check("weapon_" + weapon + "_aim_blend", float(tree.get("parameters/Aim/blend_amount")) > 0.95)
		for action in ["shoot", "throw", "jump", "land", "hit", "spawn"]:
			avatar.trigger(action)
			avatar.animate(1.0 / 60.0, state)
			if action == "land":
				# Landing must release the preceding airborne jump and preserve
				# the live gait/stance solver instead of taking over the full body.
				_check("weapon_" + weapon + "_land_live_gait", not bool(tree.get("parameters/Action/active")) and bool(avatar.get("_foot_plant").get("_was_enabled")))
			else:
				_check("weapon_" + weapon + "_" + action, bool(tree.get("parameters/Action/active")))
		_check("weapon_" + weapon + "_skeleton_finite", _finite_rig(rig))
		var weapon_root := avatar.get("_weapon") as Node3D
		_check("weapon_" + weapon + "_original_far_meshes", weapon_root.find_child("WeaponBodyFar", true, false) != null and weapon_root.find_child("WeaponInkFar", true, false) != null)
		if weapon == "splatling":
			var barrels := weapon_root.find_child("Part_barrels", true, false) as Node3D
			_check("splatling_source_barrel_spin", barrels != null and absf(barrels.rotation.z) > 0.01)
		if weapon == "dualies":
			avatar.trigger("shoot", {"hand":1})
			avatar.animate(0.02, state)
			_check("dualies_independent_left_shot", float(avatar.get("_shot_hand")[1]) < 0.04 and float(avatar.get("_shot_hand")[0]) > 0.04)
			for direction in [{"x":1.0,"z":0.0,"t":0.3},{"x":-1.0,"z":0.0,"t":0.3},{"x":0.0,"z":-1.0,"t":0.3}]:
				avatar.trigger("dodge", direction)
				avatar.animate(0.02, state)
				_check("dualies_directional_" + str(direction), bool(tree.get("parameters/Action/active")))
	for form in ["squid", "swim", "climb", "kid"]:
		var state: Dictionary = {"speed": 4.0, "velocity": Vector3(0.0, 0.0, 4.0), "grounded": true, "form": form, "wall_normal": Vector3.BACK}
		for tick in 60:
			avatar.animate(1.0 / 60.0, state)
		_check("form_" + form + "_finite", avatar.get_muzzle().is_finite() and _finite_rig(rig))
	var body := avatar.get("_body") as Node3D
	_check("kid_scale_recovers_after_transform", body != null and body.scale.y > 0.98, str(body.scale) if body else "missing")
	for tier in 3:
		avatar.force_lod = tier
		avatar.animate(0.1, {"speed": 0.0, "form": "kid"})
		var visible := 0
		for child in avatar.find_children("*", "MeshInstance3D", true, false):
			if child.is_visible_in_tree() and String(child.name).begins_with("Skin"):
				visible += 1
		_check("source_lod_%d_one_body_mesh" % tier, visible == 1, visible)
	avatar.force_lod = 1
	for hair in 8:
		for hat in 4:
			avatar.configure(Color("35d1c5"), "shooter", {"hair": hair, "hat": hat, "brows": hair % 4, "skin": hair % 9, "outfit": hair % 10, "eyes": hair % 8})
			avatar.animate(1.0 / 30.0, {"form": "kid", "grounded": true})
			_check("hair_%d_hat_%d_source_meshes" % [hair, hat], avatar.find_children("Hair*", "MeshInstance3D", true, false).size() == 3)
			var hair_bone := avatar._hair_rig.find_bone("hair0_0")
			var body_bone := rig.find_bone("hair0_0")
			var expected := avatar._hair_rig.get_bone_rest(hair_bone).origin+rig.get_bone_pose_position(body_bone)-rig.get_bone_rest(body_bone).origin
			_check("hair_%d_hat_%d_own_rest_joints" % [hair,hat],avatar._hair_rig.get_bone_pose_position(hair_bone).distance_to(expected)<0.00002)
			for frame in 20:
				avatar.position.z += 0.035
				avatar.rotation.y += 0.02
				avatar.animate(1.0/60.0,{"form":"kid","grounded":true,"speed":2.1,"velocity":Vector3(0,0,2.1)})
			_check("hair_%d_hat_%d_native_springs_finite" % [hair,hat],_finite_rig(avatar._hair_rig) and is_finite(avatar._hair_springs.max_bend))
			_check("hair_%d_hat_%d_ribbon_twist_limit" % [hair,hat],avatar._hair_springs.max_twist<=0.12001,avatar._hair_springs.max_twist)
	avatar.position = Vector3.ZERO
	avatar.rotation = Vector3.ZERO
	for outfit in 10:
		avatar.configure(Color("2f5bff"), "shooter", {"outfit": outfit, "skin": outfit % 9, "eyes": outfit % 8, "brows": outfit % 4})
		_check("outfit_%d_shader_palette" % outfit, _has_pattern(avatar, float(outfit)))
	var catalog: Dictionary = Avatar._catalog.catalog
	var skin_reference:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://assets/characters/skin_shading.json"))
	for skin in 9:
		avatar.configure(Color("2f5bff"), "shooter", {"skin":skin})
		_check("skin_%d_actual_shader_color" % skin, _palette_matches(avatar,"Skin","skin_color",Avatar._linear(Color(String(catalog.SKIN_TONES[skin])))))
		var reference:Dictionary=skin_reference.skins[skin]
		var scatter_width:=Vector3(float(reference.width[0]),float(reference.width[1]),float(reference.width[2]))
		var scatter_tint:=Vector3(float(reference.tint[0]),float(reference.tint[1]),float(reference.tint[2]))
		_check("skin_%d_original_scattering_uniforms" % skin,_palette_matches(avatar,"Skin","uSSSW",scatter_width) and _palette_matches(avatar,"Skin","uSSSTint",scatter_tint) and absf(_uniform_float(avatar,"Skin","uSkinLum")-float(reference.lum))<.00001 and is_equal_approx(_uniform_float(avatar,"Skin","uFreckle"),float(reference.freckle)))
	for eyes in 8:
		avatar.configure(Color("2f5bff"), "shooter", {"eyes":eyes})
		_check("iris_%d_actual_shader_gradient" % eyes, _palette_matches(avatar,"Eyes","uIris",Avatar._linear(Color(String(catalog.IRIS[eyes][0])))) and _palette_matches(avatar,"Eyes","uIris2",Avatar._linear(Color(String(catalog.IRIS[eyes][1])))))
	avatar.force_lod = 0
	avatar.configure(Color("35d1c5"), "charger", {})
	var blink_peak := 0.0
	var gaze_peak := 0.0
	for tick in 420:
		avatar.animate(1.0/60.0,{"form":"kid","grounded":true,"speed":0.0})
		var skin_material := (avatar.find_child("Skin",true,false) as MeshInstance3D).material_override as ShaderMaterial
		var eye_material := (avatar.find_child("Eyes",true,false) as MeshInstance3D).material_override as ShaderMaterial
		var close: Vector2 = skin_material.get_shader_parameter("native_eye_close")
		var gaze: Vector2 = eye_material.get_shader_parameter("uLook")
		blink_peak = maxf(blink_peak,maxf(close.x,close.y))
		gaze_peak = maxf(gaze_peak,gaze.length())
	_check("actual_shader_eyelid_blinks",blink_peak>0.7,blink_peak)
	_check("actual_source_gaze_channels",gaze_peak>0.001,gaze_peak)
	avatar.animate(1.0/60.0,{"form":"kid","grounded":true,"hurt":.7,"hurt_color":Color("18d48c")})
	var hurt_material:ShaderMaterial=(avatar.find_child("Skin",true,false) as MeshInstance3D).material_override
	var hurt_uniform:Vector4=hurt_material.get_shader_parameter("uHurt")
	var enemy_linear:=Color("18d48c").srgb_to_linear()
	_check("source_enemy_colour_damage_ink",Vector3(hurt_uniform.x,hurt_uniform.y,hurt_uniform.z).distance_to(Vector3(enemy_linear.r,enemy_linear.g,enemy_linear.b))<.00001 and is_equal_approx(hurt_uniform.w,.7))
	avatar.trigger("hit")
	var mouth_peak := 0.0
	for tick in 20:
		avatar.animate(1.0/60.0,{"form":"kid","grounded":true})
		var material := (avatar.find_child("Skin",true,false) as MeshInstance3D).material_override as ShaderMaterial
		var mouth: Vector4 = material.get_shader_parameter("uMouth")
		mouth_peak = maxf(mouth_peak,mouth.z)
	_check("source_hit_mouth_expression",mouth_peak>0.01,mouth_peak)
	_check("source_hit_no_added_white_emission",is_zero_approx(_uniform_float(avatar,"Skin","hit_flash")))
	for tick in 60:
		avatar.animate(1.0/60.0,{"form":"kid","special":1.0,"invuln":true,"lowInk":true,"charge":1.0,"tank":0.1})
	_check("special_ready_hair_glow", _uniform_nonzero(avatar,"Hair","uGlow"))
	_check("invulnerable_skin_flash", _uniform_nonzero(avatar,"Skin","uFlash"))
	_check("charger_source_segment_charge", _uniform_float(avatar,"Coil","uCharge") > 0.99)
	avatar.trigger("charge_release")
	avatar.animate(0.02,{"form":"kid"})
	_check("charger_release_coil_flash", _uniform_float(avatar,"Coil","uFlash") > 0.9)
	for tick in 40:
		avatar.animate(1.0/60.0,{"form":"kid","subAim":true})
	_check("original_handheld_bomb_sub_aim", (avatar.get("_bomb") as Node3D).visible)
	avatar.trigger("throw")
	avatar.animate(0.02,{"form":"kid","subAim":true})
	_check("handheld_bomb_releases_on_throw", not (avatar.get("_bomb") as Node3D).visible)
	# Visible meshes receive current state; dormant detail tiers catch up immediately
	# when selected without repeatedly submitting their uniforms every frame.
	avatar.force_lod = 1
	avatar._lod_timer = 0.0
	avatar.animate(0.1,{"form":"kid","invuln":true})
	var hero_skin := (avatar.find_child("Skin",true,false) as MeshInstance3D).material_override as ShaderMaterial
	var game_skin := (avatar.find_child("SkinGame",true,false) as MeshInstance3D).material_override as ShaderMaterial
	var dormant_flash: Variant = hero_skin.get_shader_parameter("uFlash")
	avatar.animate(0.05,{"form":"kid","invuln":true})
	_check("dormant_lod_uniforms_stay_dormant",hero_skin.get_shader_parameter("uFlash")==dormant_flash)
	_check("visible_lod_receives_current_flash",(game_skin.get_shader_parameter("uFlash") as Vector3).length()>0.0)
	avatar.force_lod = 0
	avatar._lod_timer = 0.0
	avatar.animate(0.0,{"form":"kid","invuln":true})
	_check("lod_change_updates_uniforms_same_frame",hero_skin.get_shader_parameter("uFlash")==game_skin.get_shader_parameter("uFlash"))
	var boss := Avatar.create_source_asset("boss", Color("2f5bff"), Color("ff8a14"))
	_check("original_boss_scene", boss != null)
	if boss != null:
		world.add_child(boss)
		var player := Avatar._find_type(boss, "AnimationPlayer") as AnimationPlayer
		var boss_rig := Avatar._find_type(boss, "Skeleton3D") as Skeleton3D
		_check("original_boss_100_bones", boss_rig != null and boss_rig.get_bone_count() == 100)
		_check("original_boss_24_clips_per_phase", player != null and player.get_animation_list().size() == 72)
		for index in 2:
			_check("boss_source_channels_"+str(index),boss.find_child("BossChannels"+str(index),true,false)!=null)
		if player != null:
			for clip in player.get_animation_list():
				player.play(clip, 0.0)
				player.advance(player.get_animation(clip).length * 0.45)
				_check("boss_clip_" + String(clip), _finite_rig(boss_rig))
				var channels := [false,false]
				var animation := player.get_animation(clip)
				for track in animation.get_track_count():
					for index in 2:
						if String(animation.track_get_path(track)).contains("BossChannels"+str(index)): channels[index] = true
				_check("boss_clip_live_channels_"+String(clip),channels[0] and channels[1])
			var phase3_clip := ""
			for clip in player.get_animation_list():
				if String(clip).ends_with("boss_p3_idle"): phase3_clip = String(clip)
			_check("phase3_source_locomotion_variant",not phase3_clip.is_empty())
			if not phase3_clip.is_empty():
				player.play(phase3_clip,0.0)
				player.advance(0.3)
				var phase_channels := boss.find_child("BossChannels0",true,false) as Node3D
				_check("phase3_original_belly_visible",phase_channels.position.z>0.95,phase_channels.position.z)
				var overlay := BossPhase.new()
				overlay.configure(boss)
				var channel := boss.find_child("BossChannels1",true,false) as Node3D
				overlay.apply(0.65,channel.position.x)
				var left := boss_rig.get_bone_pose_rotation(boss_rig.find_bone("tearL"))
				var right := boss_rig.get_bone_pose_rotation(boss_rig.find_bone("tearR"))
				_check("phase3_live_tear_spring_bones",left.angle_to(Quaternion(Vector3(0,0,1),-1.9*0.65))<0.0001 and right.angle_to(Quaternion(Vector3(0,0,1),1.9*0.65))<0.0001)
		_check("boss_cannon_socket", boss.find_child("Socket_cannon", true, false) != null)
		for socket in ["shellF","shellR","body"]:
			_check("boss_exact_hit_socket_"+socket,boss.find_child("Socket_"+socket,true,false)!=null)
		_check("boss_body_socket_head_parent",Avatar._catalog.bossSockets.body.bone=="head")
		boss.queue_free()
	var minion := Avatar.create_source_asset("crablet")
	_check("original_crablet_scene", minion != null)
	if minion:
		world.add_child(minion)
		var crab_rig := Avatar._find_type(minion,"Skeleton3D") as Skeleton3D
		_check("crablet_source_13_bones",crab_rig.get_bone_count()==13)
		Avatar.update_source_crablet(minion,0.1,3.0)
		var previous := crab_rig.get_bone_pose_rotation(crab_rig.find_bone("legL0"))
		Avatar.update_source_crablet(minion,0.1,3.0)
		_check("crablet_source_tripod_gait",previous.angle_to(crab_rig.get_bone_pose_rotation(crab_rig.find_bone("legL0")))>0.01)
		Avatar.hit_source_crablet(minion)
		Avatar.update_source_crablet(minion,0.01,0.0)
		_check("crablet_source_flash",float(minion.get_meta("source_crablet_animator").flash)>0.5)
		var completed := false
		for frame in 10: completed = Avatar.update_source_crablet(minion,1.0/60.0,0.0,true)
		_check("crablet_source_140ms_pop",completed and not minion.visible)
		minion.free()
	avatar.queue_free()
	await process_frame
	_finish()

func _has_pattern(avatar: Node, expected: float) -> bool:
	for node in avatar.find_children("Cloth*", "MeshInstance3D", true, false):
		var material := (node as MeshInstance3D).material_override as ShaderMaterial
		if material != null and is_equal_approx(float(material.get_shader_parameter("uPattern")), expected):
			return true
	return false

func _palette_matches(avatar: Node, mesh_name: String, parameter: String, expected: Vector3) -> bool:
	var mesh := avatar.find_child(mesh_name,true,false) as MeshInstance3D
	if mesh == null:return false
	var material := mesh.material_override as ShaderMaterial
	if material == null:return false
	var actual: Variant = material.get_shader_parameter(parameter)
	return actual is Vector3 and actual.distance_to(expected) < 0.00001

func _uniform_float(avatar: Node, mesh_name: String, parameter: String) -> float:
	var mesh := avatar.find_child(mesh_name,true,false) as MeshInstance3D
	if mesh == null:return 0.0
	var material := mesh.material_override as ShaderMaterial
	if material == null:return 0.0
	return float(material.get_shader_parameter(parameter))

func _uniform_nonzero(avatar: Node, mesh_name: String, parameter: String) -> bool:
	var mesh := avatar.find_child(mesh_name,true,false) as MeshInstance3D
	if mesh == null:return false
	var material := mesh.material_override as ShaderMaterial
	if material == null:return false
	var value: Variant = material.get_shader_parameter(parameter)
	return value is Vector3 and value.length_squared() > 0.00001

func _finite_rig(rig: Skeleton3D) -> bool:
	if rig == null:
		return false
	for bone in rig.get_bone_count():
		if not rig.get_bone_pose_position(bone).is_finite() or not rig.get_bone_pose_rotation(bone).is_finite() or not rig.get_bone_pose_scale(bone).is_finite():
			return false
	return true

func _attribute_position_matches(mesh: MeshInstance3D, check_normals: bool = false) -> bool:
	if mesh == null:
		return false
	var material := mesh.material_override as ShaderMaterial
	if material == null:
		return false
	var texture := material.get_shader_parameter("source_data") as Texture2D
	if texture == null:
		return false
	var image := texture.get_image()
	image.convert(Image.FORMAT_RGBA8)
	var arrays := mesh.mesh.surface_get_arrays(0)
	var positions: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL if check_normals else Mesh.ARRAY_VERTEX]
	var coords: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV2]
	var slot := 10 if check_normals else 0
	var lo: Vector4 = material.get_shader_parameter("data_min_%d"%slot)
	var hi: Vector4 = material.get_shader_parameter("data_max_%d"%slot)
	var rows := image.get_height() / 24
	for i in range(0,positions.size(),maxi(1,positions.size()/16)):
		var x := clampi(floori(coords[i].x*image.get_width()),0,image.get_width()-1)
		var y := clampi(floori(coords[i].y*rows),0,rows-1)
		var high := image.get_pixel(x,y+slot*2*rows)
		var low := image.get_pixel(x,y+(slot*2+1)*rows)
		var decoded := Vector3.ZERO
		for component in 3:
			var a: float = high[component]
			var b: float = low[component]
			decoded[component] = lerpf(lo[component],hi[component],(roundf(a*255.0)*256.0+roundf(b*255.0))/65535.0)
		if decoded.distance_to(positions[i]) > 0.001:
			push_error("Imported UV2/data atlas mismatch slot "+str(slot)+" for " + mesh.name + ": " + str(decoded) + " vs " + str(positions[i]))
			return false
	return true

func _finish() -> void:
	var report := {"suite": "source_characters", "passed": failures == 0, "failures": failures, "checks": checks}
	var file := FileAccess.open("res://shots/character_contract.json", FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
	print("CHARACTER_CONTRACT " + JSON.stringify({"passed": failures == 0, "failures": failures, "checks": checks.size()}))
	quit(0 if failures == 0 else 1)
