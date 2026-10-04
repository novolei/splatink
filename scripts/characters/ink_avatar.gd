class_name InkAvatar
extends Node3D
## Original INKWAVE geometry + source sampled motion. Gameplay drives this visual node.
## Authoring coordinates stay +Z forward (the original character's left is +X).

const MANIFEST_PATH := "res://assets/characters/manifest.json"
const AIM_FRAMES_PATH := "res://assets/characters/aim_frames.json"
const MotionMatcher = preload("res://scripts/animation/ink_motion_matcher.gd")
const NativeMotionMatcher = preload("res://scripts/animation/native_motion_matcher.gd")
const Inertializer = preload("res://scripts/animation/ink_inertializer.gd")
const FootPlant = preload("res://scripts/animation/ink_foot_plant.gd")
const HairSprings = preload("res://scripts/animation/ink_hair_springs.gd")
const CrabletAnimator = preload("res://scripts/animation/ink_crablet_animator.gd")
const ArmAim = preload("res://scripts/animation/ink_arm_aim.gd")
const HitResponse = preload("res://scripts/animation/ink_hit_response.gd")
const CatchStep = preload("res://scripts/animation/ink_catch_step.gd")
const PosePresentation = preload("res://scripts/animation/ink_pose_presentation.gd")
const WEAPONS := ["shooter", "roller", "charger", "blaster", "dualies", "slosher", "splatling"]
const UPPER_BONES := ["spine", "chest", "neck", "head", "clavL", "clavR", "uArmL", "uArmR", "fArmL", "fArmR", "handL", "handR", "tank", "jaw", "cheekL", "cheekR", "earL", "earR", "eyeL", "eyeR", "browL", "browR", "mouth", "mouthO"]
const LOWER_BODY_BONES := ["hips","thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]
const PRESENTATION_LEG_BONES := ["thighL","shinL","footL","toeL","thighR","shinR","footR","toeR"]
const FACE_MATRIX_PARAMETERS := [&"native_face_head",&"native_face_jaw",&"native_face_cheekL",&"native_face_cheekR",&"native_face_neck",&"native_face_chest"]
# Original Character._updateFormScales key times and Catmull-Rom values.
const EM_ST := [0.0, 0.03, 0.07, 0.095]
const EM_SY := [1.0, 0.72, 1.42, 1.6]
const EM_SX := [1.0, 1.18, 0.78, 0.62]
const EM_KT := [0.045, 0.1, 0.16, 0.24, 0.32, 0.42]
const EM_KY := [1.36, 1.13, 0.88, 1.05, 0.985, 1.0]
const EM_KX := [0.68, 0.9, 1.09, 0.975, 1.008, 1.0]
const DV_KT := [0.0, 0.03, 0.07, 0.095]
const DV_KY := [1.0, 0.82, 0.34, 0.16]
const DV_KX := [1.0, 1.1, 1.4, 1.2]
const DV_ST := [0.045, 0.08, 0.13, 0.2, 0.28, 0.38]
const DV_SY := [0.3, 0.72, 1.3, 0.9, 1.045, 1.0]
const DV_SX := [1.5, 1.2, 0.83, 1.07, 0.98, 1.0]

static var _catalog: Dictionary = {}
static var _aim_frames: Dictionary = {}
static var _scene_cache: Dictionary = {}
static var _shader_parameters: Dictionary = {}

var weapon_id: String = "shooter"
var appearance: Dictionary = {"hair": 0, "hat": 0, "brows": 0, "skin": 0, "outfit": 0, "eyes": 0}
var team_color: Color = Color("ff8a14")
var current_action: String = "idle"
## -1 = source screen-size policy; 0/1/2 = original hero/game/far.
@export var force_lod: int = -1
@export var motion_matching := true
## QA opt-in: recovered C++ MM library selects only hips/legs/feet source tracks.
@export var native_locomotion_mm:=false
var _native_motion_active:=false
## Isolated physics experiment. Only an explicitly enabled local native Avatar
## changes reach correction; trace mode retains the original arithmetic.
@export var footplant_continuous_reach:bool=false
var _footplant_reach_trace:=false
var _footplant_reach_active:=false
var footplant_reach_mode:String:
	get:return "legacy" if not _footplant_reach_active else "continuous" if bool(_foot_plant.get("continuous_reach")) else "trace"
## QA opt-in only; physics remains authoritative and global interpolation stays off.
@export var presentation_interpolation:bool=false:
	set(value):
		if presentation_interpolation==value:return
		if _presentation!=null:
			_presentation.restore(self)
			_update_face_materials()
			if _presentation_coherent_root:_presentation.invalidate()
		if _presentation_coherent_root:_presentation_ticks=false
		presentation_interpolation=value
		set_process(value)
		if value and is_instance_valid(_skeleton):_configure_presentation()
var presentation_active:bool:
	get:return presentation_interpolation and _presentation_ticks and _presentation!=null and _presentation.valid
var presentation_profile:Dictionary:
	get:return _presentation.profile if _presentation!=null else {}
var presentation_mode:String:
	get:return "off" if not presentation_interpolation else "coherent-pelvis" if _presentation_coherent_pelvis else "coherent" if _presentation_coherent_root else "lower" if _presentation_lower_only else "local" if _presentation_local_only else "all"
var profile_animation := false
var animation_profile: Dictionary = {}
var uniform_updates := 0
var motion_state: Dictionary:
	get: return _motion.debug_state() if _motion != null else {}
var profile_metrics:Dictionary:
	get:
		var native:=_motion as NativeMotionMatcher
		return {"native_mm_active":1 if _native_motion_active and native!=null else 0,"native_mm_queries":native.native_query_count if native!=null else 0,"native_mm_query_us":native.native_query_microseconds if native!=null else 0,"native_mm_poses_evaluated":native.native_poses_evaluated if native!=null else 0}
var _motion: InkMotionMatcher
var _inertializer: InkInertializer
var _foot_plant: InkFootPlant
var _arm_aim: InkArmAim
var _hit := HitResponse.new()
var _catch_step:=CatchStep.new()
var _presentation:InkPosePresentation
var _presentation_ticks:=false
var _presentation_local_only:=false
var _presentation_lower_only:=false
var _presentation_coherent_root:=false
var _presentation_coherent_pelvis:=false
var _presentation_leg_indices:=PackedInt32Array()
var _presentation_muzzles:=PackedVector3Array([Vector3.ZERO,Vector3.ZERO])
var _presentation_head:=Vector3.ZERO
var _presentation_kid:=Transform3D.IDENTITY
var _motion_clip: AnimationNodeAnimation
var _body: Node3D
var _kid: Node3D
var _skeleton: Skeleton3D
var _animation: AnimationPlayer
var _tree: AnimationTree
var _blend_graph: AnimationNodeBlendTree
var _locomotion: AnimationNodeBlendSpace2D
var _fire_clip: AnimationNodeAnimation
var _air_clip: AnimationNodeAnimation
var _action_clip: AnimationNodeAnimation
var _action_node: AnimationNodeOneShot
var _aim_node: AnimationNodeBlend2
var _hair: Node3D
var _hair_rig: Skeleton3D
var _hair_springs: InkHairSprings
var _brows: Node3D
var _squid: Node3D
var _weapon: Node3D
var _left_weapon: Node3D
var _weapon_r: Node3D
var _weapon_l: Node3D
var _weapon_offset: Node3D
var _left_weapon_offset: Node3D
var _muzzle: Node3D
var _left_muzzle:Node3D
var _tank_fill: Node3D
var _bomb: Node3D
var _modules: Array[Skeleton3D] = []
var _pose_maps: Array[PackedInt32Array] = []
var _module_rest_offsets: Array[PackedVector3Array] = []
var _materials: Array[ShaderMaterial] = []
var _material_entries: Array[Dictionary] = []
var _lighting_theme: Dictionary = {}
var _face_materials: Array[Dictionary] = []
var _face_nodes: Array[Node3D] = []
var _head_parameters:Array[Node3D]=[]
var _face_bones := PackedInt32Array()
var _face_rest: Array[Basis] = []
var _hand_bones := PackedInt32Array()
var _eye_bones := PackedInt32Array()
var _loaded_look: Vector3i = Vector3i(-1, -1, -1)
var _loaded_weapon: String = ""
var _time: float = 0.0
var _form: String = "kid"
var _form_weight: float = 0.0
var _previous_form: String = "kid"
var _form_time: float = 1.0
var _kid_pop: float = 1.0
var _squid_stretch: Vector2 = Vector2.ONE
var _hop_phase: float = 0.0
var _squid_yaw: float = 0.0
var _squid_roll: float = 0.0
var _squid_initialized: bool = false
var _aim_weight: float = 0.0
var _air_weight: float = 0.0
var _flash: float = 0.0
var _ink: float = 1.0
var _recoil: float = 0.0
var _shot_time: float = 99.0
var _shot_hand := [99.0, 99.0]
var _flick_time: float = 99.0
var _release_time: float = 99.0
var _throw_time: float = 99.0
var _charge_flash: float = 0.0
var _special_glow: float = 0.0
var _low_ink: float = 0.0
var _sub_weight: float = 0.0
var _bomb_time: float = 0.0
var _rolling: float = 0.0
var _weapon_motion: Array[Dictionary] = []
var _part_rest: Dictionary = {}
var _dance: String = ""
var _lod: int = -1
var _lod_timer: float = 0.0

func _ready() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument=="--native-locomotion-mm":native_locomotion_mm=true
		if argument=="--footplant-continuous-reach":footplant_continuous_reach=true
		if argument=="--footplant-reach-trace":_footplant_reach_trace=true
		if argument.trim_prefix("--").begins_with("profile-render"): profile_animation = true
		if argument=="--presentation-interpolation":presentation_interpolation=true
		elif argument=="--presentation-interpolation=all":presentation_interpolation=true
		elif argument=="--presentation-interpolation=local":
			_presentation_local_only=true
			presentation_interpolation=true
		elif argument=="--presentation-interpolation=lower":
			_presentation_lower_only=true
			presentation_interpolation=true
		elif argument=="--presentation-interpolation=coherent":
			_presentation_coherent_root=true
			_presentation_lower_only=true
			_presentation_local_only=true
			presentation_interpolation=true
		elif argument=="--presentation-interpolation=coherent-pelvis":
			_presentation_coherent_pelvis=true
			_presentation_coherent_root=true
			_presentation_lower_only=true
			_presentation_local_only=true
			presentation_interpolation=true
	process_priority=-10
	_ensure_built()
	configure(team_color, weapon_id, appearance)
	set_process(presentation_interpolation)

func _process(_delta:float) -> void:
	if presentation_active and is_visible_in_tree():present(Engine.get_physics_interpolation_fraction())

func _ensure_built() -> void:
	if is_instance_valid(_body):
		return
	if _catalog.is_empty():
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if decoded is Dictionary:
			_catalog = decoded
	if _aim_frames.is_empty():
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(AIM_FRAMES_PATH))
		if decoded is Dictionary: _aim_frames = decoded
	_body = _instantiate_asset("body")
	if _body == null:
		return
	add_child(_body)
	_kid = _find_node(_body, "Kid") as Node3D
	_skeleton = _find_type(_body, "Skeleton3D") as Skeleton3D
	_hand_bones = PackedInt32Array([_skeleton.find_bone("handR"),_skeleton.find_bone("handL")])
	_eye_bones = PackedInt32Array([_skeleton.find_bone("eyeL"),_skeleton.find_bone("eyeR")])
	_animation = _find_type(_body, "AnimationPlayer") as AnimationPlayer
	_weapon_r = _find_node(_body, "WeaponR") as Node3D
	_weapon_l = _find_node(_body, "WeaponL") as Node3D
	_arm_aim = ArmAim.new()
	_arm_aim.configure(_skeleton)
	_hit.configure(_skeleton)
	_catch_step.configure(_skeleton)
	_tank_fill = _find_node(_body, "TankFill") as Node3D
	for face_name in ["FaceMouth","FaceExpression","FaceMood","FaceLook","FaceGazeL","FaceGazeR","FaceLid"]:
		_face_nodes.append(_find_node(_body,face_name) as Node3D)
	for parameter_name:String in ["SourceHeadFK","SourceHeadLook","SourceHeadTorso"]:
		_head_parameters.append(_find_node(_body,parameter_name) as Node3D)
	for bone_name in ["head","jaw","cheekL","cheekR","neck","chest"]:
		var index := _skeleton.find_bone(bone_name)
		_face_bones.append(index)
		_face_rest.append(_skeleton.get_bone_global_rest(index).basis.inverse())
	_bomb = _instantiate_asset("bomb")
	if _bomb != null and _skeleton != null:
		var attachment := BoneAttachment3D.new()
		attachment.name = "BombAttachment"
		attachment.bone_name = "handL"
		_skeleton.add_child(attachment)
		attachment.add_child(_bomb)
		var grip: Dictionary = _catalog.assets.bomb.get("inHandL", {})
		if not grip.is_empty():
			var p: Array = grip.pos
			var q: Array = grip.quat
			_bomb.position = Vector3(p[0], p[1], p[2])
			_bomb.quaternion = Quaternion(q[0], q[1], q[2], q[3])
		_bomb.visible = false
	_squid = _instantiate_asset("squid")
	if _squid != null:
		add_child(_squid)
		_squid.visible = false
	if _animation != null:
		for clip in _animation.get_animation_list():
			var key: String = _source_clip_name(String(clip))
			if _catalog.get("animations", {}).has(key):
				var animation: Animation = _animation.get_animation(clip)
				animation.loop_mode = Animation.LOOP_LINEAR if bool(_catalog.animations[key].loop) else Animation.LOOP_NONE
		_build_animation_graph()

func configure(color: Color, equipped_weapon: String, style: Dictionary = {}) -> void:
	restore_presentation()
	team_color = color
	weapon_id = equipped_weapon if equipped_weapon in WEAPONS else "shooter"
	for field in ["hair", "hat", "brows", "skin", "outfit", "eyes"]:
		var count: int = {"hair": 8, "hat": 4, "brows": 4, "skin": 9, "outfit": 10, "eyes": 8}[field]
		appearance[field] = posmod(int(style.get(field, appearance.get(field, 0))), count)
	_ensure_built()
	if _body == null:
		return
	var look := Vector3i(int(appearance.hair), int(appearance.hat), int(appearance.brows))
	if look != _loaded_look:
		_replace_appearance(look)
	if _loaded_weapon != weapon_id:
		_replace_weapon()
	_refresh_material_list()
	_apply_palette()
	_apply_lod(0 if _lod < 0 else _lod)
	if _motion != null:
		_motion.set_weapon(weapon_id)
	if presentation_interpolation:_configure_presentation()

func _replace_appearance(look: Vector3i) -> void:
	for old in [_hair, _brows]:
		if is_instance_valid(old):
			old.get_parent().remove_child(old)
			old.queue_free()
	_hair = _instantiate_asset("hair_%d_%d" % [look.x, look.y])
	_brows = _instantiate_asset("brows_%d" % look.z)
	_modules.clear()
	_pose_maps.clear()
	_module_rest_offsets.clear()
	for part in [_hair, _brows]:
		if part == null:
			continue
		(_kid if _kid != null else _body).add_child(part)
		var rig := _find_type(part, "Skeleton3D") as Skeleton3D
		if rig != null and _skeleton != null:
			var indices := PackedInt32Array()
			var rest_offsets := PackedVector3Array()
			var asset_name := "hair_%d_%d"%[look.x,look.y] if part==_hair else "brows_%d"%look.z
			var used: Array = _catalog.assets[asset_name].get("used_bones",[])
			for i in rig.get_bone_count():
				var name := rig.get_bone_name(i)
				indices.append(_skeleton.find_bone(name) if used.is_empty() or String(name) in used else -1)
				var source_index := indices[i]
				rest_offsets.append(rig.get_bone_rest(i).origin-_skeleton.get_bone_rest(source_index).origin if source_index>=0 else Vector3.ZERO)
			_modules.append(rig)
			_pose_maps.append(indices)
			_module_rest_offsets.append(rest_offsets)
	_hair_rig = _find_type(_hair,"Skeleton3D") as Skeleton3D if _hair!=null else null
	if _hair_rig != null:
		_hair_springs = HairSprings.new()
		_hair_springs.configure(_hair_rig,look.x,look.y,int(get_instance_id()))
	_loaded_look = look

func _replace_weapon() -> void:
	for old in [_weapon, _left_weapon]:
		if is_instance_valid(old):
			old.get_parent().remove_child(old)
			old.queue_free()
	_left_weapon = null
	_left_weapon_offset = null
	_left_muzzle=null
	_weapon = _instantiate_asset("weapon_" + weapon_id)
	_weapon_offset = _find_node(_weapon,"WeaponOffset") as Node3D if _weapon != null else null
	if _weapon != null and _weapon_r != null:
		_weapon_r.add_child(_weapon)
		_muzzle = _find_node(_weapon, "Muzzle") as Node3D
	if weapon_id == "dualies" and _weapon_l != null:
		_left_weapon = _instantiate_asset("weapon_dualies")
		if _left_weapon != null:
			_weapon_l.add_child(_left_weapon)
			_left_muzzle=_find_node(_left_weapon,"Muzzle") as Node3D
			var data: Dictionary = _catalog.assets.weapon_dualies.get("inHandL", {})
			var off := _find_node(_left_weapon, "WeaponOffset") as Node3D
			_left_weapon_offset = off
			if off != null and not data.is_empty():
				var p: Array = data.pos
				var q: Array = data.quat
				off.position = Vector3(float(p[0]), float(p[1]), float(p[2])) - _weapon_l.position
				off.quaternion = Quaternion(float(q[0]), float(q[1]), float(q[2]), float(q[3]))
	_part_rest.clear()
	_weapon_motion.clear()
	for weapon_part in [_weapon, _left_weapon]:
		if weapon_part != null:
			var motion := {"parts": {}, "ps": PackedFloat32Array([1.3, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]), "trigger": 0.0, "heat": 0.0, "drum_speed": 0.0, "drum_angle": 0.0, "spin_speed": 0.0, "spin_angle": 0.0, "drum": _find_node(weapon_part, "Drum")}
			for part in weapon_part.find_children("Part_*", "Node3D", true, false):
				_part_rest[part.get_instance_id()] = {"node": part, "transform": part.transform}
				motion.parts[String(part.name).trim_prefix("Part_")] = part
			_weapon_motion.append(motion)
	_loaded_weapon = weapon_id
	_update_graph_clips()

func _build_animation_graph() -> void:
	_tree = AnimationTree.new()
	_tree.name = "AvatarAnimationTree"
	add_child(_tree)
	_tree.anim_player = _tree.get_path_to(_animation)
	_tree.root_node = _tree.get_path_to(_animation.get_node(_animation.root_node))
	_tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_blend_graph = AnimationNodeBlendTree.new()
	_locomotion = AnimationNodeBlendSpace2D.new()
	_locomotion.min_space = Vector2(-1.0, -1.0)
	_locomotion.max_space = Vector2.ONE
	_locomotion.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_CYCLIC_MUTABLE
	var points := [{"name": "idle", "pos": Vector2.ZERO}, {"name": "walk", "pos": Vector2(0.0, 0.3)}, {"name": "run", "pos": Vector2(0.0, 1.0)}, {"name": "strafe_left", "pos": Vector2(1.0, 0.0)}, {"name": "strafe_right", "pos": Vector2(-1.0, 0.0)}, {"name": "backpedal", "pos": Vector2(0.0, -1.0)}]
	for point in points:
		var clip := AnimationNodeAnimation.new()
		_locomotion.add_blend_point(clip, point.pos, -1, StringName(point.name))
	_blend_graph.add_node(&"Locomotion", _locomotion, Vector2(0, 60))
	_motion_clip = AnimationNodeAnimation.new()
	_blend_graph.add_node(&"MotionClip",_motion_clip,Vector2(-250,-140))
	var motion_seek := AnimationNodeTimeSeek.new()
	_blend_graph.add_node(&"MotionTime",motion_seek,Vector2(0,-140))
	_blend_graph.connect_node(&"MotionTime",0,&"MotionClip")
	var motion_selection := AnimationNodeBlend2.new()
	_native_motion_active=native_locomotion_mm and NativeMotionMatcher.available()
	if native_locomotion_mm and not _native_motion_active:
		push_error("Native locomotion MM requested but native query API unavailable")
	motion_selection.filter_enabled=_native_motion_active
	if _native_motion_active:_set_lower_filters(motion_selection)
	_blend_graph.add_node(&"MotionSelection",motion_selection,Vector2(180,-50))
	_blend_graph.connect_node(&"MotionSelection",0,&"Locomotion")
	_blend_graph.connect_node(&"MotionSelection",1,&"MotionTime")
	_air_clip = AnimationNodeAnimation.new()
	_blend_graph.add_node(&"FallClip", _air_clip, Vector2(0, 260))
	var air := AnimationNodeBlend2.new()
	_blend_graph.add_node(&"Air", air, Vector2(250, 120))
	_blend_graph.connect_node(&"Air", 0, &"MotionSelection")
	_blend_graph.connect_node(&"Air", 1, &"FallClip")
	_fire_clip = AnimationNodeAnimation.new()
	_blend_graph.add_node(&"FireClip", _fire_clip, Vector2(250, 350))
	_aim_node = AnimationNodeBlend2.new()
	_aim_node.filter_enabled = true
	_blend_graph.add_node(&"Aim", _aim_node, Vector2(480, 120))
	_blend_graph.connect_node(&"Aim", 0, &"Air")
	_blend_graph.connect_node(&"Aim", 1, &"FireClip")
	_action_clip = AnimationNodeAnimation.new()
	_blend_graph.add_node(&"ActionClip", _action_clip, Vector2(480, 350))
	_action_node = AnimationNodeOneShot.new()
	_action_node.fadein_time = 0.035
	_action_node.fadeout_time = 0.14
	_blend_graph.add_node(&"Action", _action_node, Vector2(720, 120))
	_blend_graph.connect_node(&"Action", 0, &"Aim")
	_blend_graph.connect_node(&"Action", 1, &"ActionClip")
	_blend_graph.connect_node(&"output", 0, &"Action")
	_tree.tree_root = _blend_graph
	_update_graph_clips()
	_tree.active = true
	_motion = NativeMotionMatcher.new() if _native_motion_active else MotionMatcher.new()
	if not _motion.configure(_skeleton,weapon_id,int(get_instance_id()%3)):
		if _native_motion_active:
			_native_motion_active=false
			motion_selection.filter_enabled=false
			push_error("Native locomotion MM database configuration failed")
		_motion = null
	else:
		_inertializer = Inertializer.new()
		if _native_motion_active:
			var lower_indices:=PackedInt32Array()
			for bone:String in LOWER_BODY_BONES:lower_indices.append(_skeleton.find_bone(bone))
			_inertializer.configure(_skeleton,[],lower_indices)
		else:
			_inertializer.configure(_skeleton,[_find_node(_body,"Model"),_kid,_weapon_r,_weapon_l]+_face_nodes)
		_foot_plant = FootPlant.new()
		_footplant_reach_active=_native_motion_active and (_footplant_reach_trace or footplant_continuous_reach)
		if _footplant_reach_active:
			_foot_plant=load("res://scripts/animation/experiments/ink_foot_plant_continuous_reach.gd").new()
		_foot_plant.configure(_skeleton)

func _update_graph_clips() -> void:
	if _tree == null:
		return
	for i in _locomotion.get_blend_point_count():
		var clip := _locomotion.get_blend_point_node(i) as AnimationNodeAnimation
		clip.animation = _clip(String(_locomotion.get_blend_point_name(i)))
	_fire_clip.animation = _clip("fire")
	_air_clip.animation = _clip("fall")
	_action_clip.animation = _clip("shoot")
	_motion_clip.animation = _clip("idle")
	_set_upper_filters(_aim_node)
	_set_upper_filters(_action_node)

func _set_upper_filters(node: AnimationNode) -> void:
	if _animation == null:
		return
	var name := _clip("fire")
	if not _animation.has_animation(name):
		return
	var animation := _animation.get_animation(name)
	for i in animation.get_track_count():
		var track: NodePath = animation.track_get_path(i)
		var bone: String = String(track.get_subname(0)) if track.get_subname_count() > 0 else ""
		if bone in UPPER_BONES or bone.begins_with("hair") or bone.begins_with("hand") or String(track).contains("Weapon") or String(track).contains("Tank") or String(track).contains("Face") or String(track).contains("SourceHead"):
			node.set_filter_path(track, true)

func _set_lower_filters(node:AnimationNode)->void:
	if _animation==null:return
	var name:=_clip("idle")
	if not _animation.has_animation(name):return
	var animation:=_animation.get_animation(name)
	for i:int in animation.get_track_count():
		var track:NodePath=animation.track_get_path(i)
		var bone:String=String(track.get_subname(0)) if track.get_subname_count()>0 else ""
		if bone in LOWER_BODY_BONES:node.set_filter_path(track,true)

func animate(dt: float, state: Dictionary) -> void:
	restore_presentation()
	if _body == null:
		_ensure_built()
		return
	var profile_tick := Time.get_ticks_usec() if profile_animation else 0
	var profile_start := profile_tick
	if profile_animation: animation_profile.clear()
	uniform_updates = 0
	var delta := clampf(dt, 0.0, 0.1)
	_time += delta
	_lod_timer -= delta
	if _lod_timer <= 0.0:
		_update_lod(state)
		_lod_timer = 0.2
	_shot_time += delta
	for hand in 2:
		_shot_hand[hand] += delta
	_flick_time += delta
	_release_time += delta
	_throw_time += delta
	_charge_flash = maxf(0.0, _charge_flash - delta * 3.5)
	_flash = move_toward(_flash, 0.0, delta * 4.5)
	_recoil = move_toward(_recoil, 0.0, delta * 7.0)
	var speed := float(state.get("speed", 0.0))
	var velocity: Vector3 = state.get("velocity", Vector3.ZERO)
	var local_velocity: Vector3 = global_basis.inverse() * velocity
	var move := Vector2(local_velocity.x, local_velocity.z)
	if move.length_squared() < 0.001 and speed > 0.1:
		move = Vector2(0.0, speed)
	var grounded := bool(state.get("grounded", true))
	var firing := bool(state.get("firing", false))
	var charge := clampf(float(state.get("charge", 0.0)), 0.0, 1.0)
	_special_glow = lerpf(_special_glow, 1.0 if float(state.get("special", 0.0)) >= 0.999 else 0.0, 1.0 - exp(-delta * 6.0))
	_low_ink = lerpf(_low_ink, 1.0 if bool(state.get("lowInk", state.get("low_ink", false))) else 0.0, 1.0 - exp(-delta * 8.0))
	var sub_aim := bool(state.get("subAim", state.get("sub_aim", false)))
	if sub_aim and _sub_weight < 0.01:
		_bomb_time = 0.0
	_bomb_time += delta
	_sub_weight = lerpf(_sub_weight, 1.0 if sub_aim else 0.0, 1.0 - exp(-delta * (14.0 if sub_aim else 9.0)))
	var roll := bool(state.get("rolling", false)) and weapon_id == "roller" and _flick_time > 0.6
	_rolling = lerpf(_rolling, 1.0 if roll else 0.0, 1.0 - exp(-delta * (11.0 if roll else 6.0)))
	var next_form := String(state.get("form", "kid"))
	if next_form == "swimming":
		next_form = "swim"
	if next_form != _form:
		if (next_form == "kid") != (_form == "kid"):
			var previous_time := _form_time
			_previous_form = _form
			_form_time = 0.0
			if previous_time < 0.1:
				if next_form == "kid" and _form_weight < 0.999:
					_form_time = clampf(0.06 + 0.035 * (1.0 - _form_weight), 0.0, 0.095)
				elif next_form != "kid" and _kid_pop < 0.999:
					_form_time = clampf(0.07 + 0.03 * (1.0 - _kid_pop), 0.0, 0.1)
		_form = next_form
	_form_time += delta
	var dry_squid:bool=_form!="kid" and _form!="climb" and not (_form=="swim" and grounded) and not (not grounded and (speed>3.0 or _form=="swim" or _previous_form=="climb"))
	var smooth := 1.0 - exp(-delta * 16.0)
	_update_form_scales()
	_hit.step(delta,dry_squid,_kid.visible)
	var aiming := firing or charge > 0.01 or _shot_time < 0.5 or _release_time < 0.35
	var aim_target := maxf(_sub_weight, _rolling if weapon_id == "roller" else (1.0 if aiming else 0.0))
	_aim_weight = lerpf(_aim_weight, aim_target, 1.0 - exp(-delta * (22.0 if aim_target > _aim_weight else 4.5)))
	_air_weight = lerpf(_air_weight, 0.0 if grounded else 1.0, smooth)
	_ink = lerpf(_ink, clampf(float(state.get("tank", state.get("ink", 1.0))), 0.0, 1.0), 1.0 - exp(-delta * 8.0))
	var ground_sampler: Callable = state.get("ground_sampler",Callable())
	var catch_enabled:bool=grounded and _form=="kid" and _dance.is_empty() and not (bool(_tree.get("parameters/Action/active")) and not _action_node.filter_enabled)
	var catch_hold:Dictionary=_aim_frames.get("weapons",{}).get(weapon_id,{}).get("hold",{})
	var catch_targets:=_catch_step.step(delta,_skeleton,global_transform,ground_sampler,_hit,local_velocity,catch_hold,_aim_weight,catch_enabled)
	if _tree != null:
		profile_tick = _profile_span(&"state",profile_tick)
		var mm_enabled := motion_matching and _motion != null
		_tree.set("parameters/MotionSelection/blend_amount",1.0 if mm_enabled else 0.0)
		if mm_enabled:
			var desired: Vector3 = state.get("desired_velocity",velocity)
			var facing: Vector3 = state.get("desired_facing",global_basis.z)
			_motion.step(delta,_skeleton,local_velocity,global_basis.inverse()*desired,global_basis.inverse()*facing,bool(state.get("is_local",true)),grounded and _form == "kid" and _dance.is_empty())
			_motion_clip.animation = _clip(_motion.clip_name().trim_prefix(weapon_id+"_"))
			_tree.set("parameters/MotionTime/seek_request",_motion.sample_time)
		profile_tick = _profile_span(&"matcher",profile_tick)
		_tree.set("parameters/Locomotion/blend_position", move.limit_length(5.5) / 5.5)
		_tree.set("parameters/Aim/blend_amount", _aim_weight)
		_tree.set("parameters/Air/blend_amount", _air_weight)
		_fire_clip.animation = _clip("sub_aim" if _sub_weight > 0.2 else "roll" if weapon_id == "roller" else "charge" if weapon_id in ["charger", "splatling"] and charge > 0.02 else "fire")
		_tree.advance(delta)
		if _footplant_reach_active:
			_foot_plant.set("raw_pose_hip_y",_skeleton.get_bone_pose_position(_skeleton.find_bone("hips")).y)
			_foot_plant.set("raw_pose_hip_y_available",true)
			_foot_plant.set("continuous_reach",footplant_continuous_reach and _native_motion_active and bool(state.get("is_local",false)))
			_foot_plant.set("collect_reach_diagnostics",bool(state.get("is_local",false)))
		profile_tick = _profile_span(&"tree",profile_tick)
		if _inertializer != null:
			var full_body_action := bool(_tree.get("parameters/Action/active")) and not _action_node.filter_enabled
			var planted_locomotion := mm_enabled and grounded and _form == "kid" and not full_body_action and _dance.is_empty()
			_inertializer.apply(_skeleton,delta,_motion.transitioned,_motion,planted_locomotion)
			profile_tick = _profile_span(&"inertialization",profile_tick)
			if _form=="kid" and _dance.is_empty():_hit.apply(_skeleton,int(appearance.hat),_head_parameters)
			_foot_plant.apply(_skeleton,delta,_motion,global_position,ground_sampler,planted_locomotion,catch_targets)
			profile_tick = _profile_span(&"foot_ik",profile_tick)
		elif _form=="kid" and _dance.is_empty():
			_hit.apply(_skeleton,int(appearance.hat),_head_parameters)
		current_action = "fire" if _aim_weight > 0.5 else "run" if speed > 2.5 else "walk" if speed > 0.25 else "idle"
	if _skeleton != null:
		if _hit.active and _weapon_r!=null:
			_weapon_r.quaternion=Quaternion(Vector3.RIGHT,_hit.sample(HitResponse.Channel.WEAPON_PITCH)*lerpf(1.0,.3,_aim_weight))*_weapon_r.quaternion
		_apply_pitched_aim(state)
		profile_tick = _profile_span(&"arm_ik",profile_tick)
		_copy_module_poses()
		profile_tick = _profile_span(&"modules",profile_tick)
		if _hair_springs != null and _hair_rig != null:
			_hair_springs.apply(_hair_rig,delta,_time,clampf(speed/5.5,0.0,1.0),_air_weight,_form=="kid" and _lod<2 and _kid.visible)
		profile_tick = _profile_span(&"hair",profile_tick)
		_update_face_materials()
		profile_tick = _profile_span(&"face",profile_tick)
	_animate_squid(delta, speed, local_velocity, state)
	if _bomb != null:
		_bomb.visible = sub_aim and _form == "kid" and _sub_weight > 0.2 and _throw_time > 0.32
		var u := clampf(_bomb_time / 0.14, 0.0, 1.0) - 1.0
		_bomb.scale = Vector3.ONE * maxf(0.05, 1.0 + 3.6 * u * u * u + 2.6 * u * u)
	if _left_weapon != null:
		_left_weapon.visible = not sub_aim and _throw_time > 0.32
	if _tank_fill != null:
		_tank_fill.scale.y = maxf(0.004, _ink) * 0.18
		_tank_fill.visible = _ink > 0.005
	var hurt := clampf(float(state.get("hurt", 0.0)), 0.0, 1.0)
	var hurt_color:Variant=state.get("hurt_color",Color("2f5bff"))
	var hurt_rgb:Vector3=_linear(hurt_color) if hurt_color is Color else hurt_color if hurt_color is Vector3 else _linear(Color("2f5bff"))
	var invuln_flash := 0.22 * (0.5 + 0.5 * sin(_time * TAU * 6.0)) if bool(state.get("invuln", false)) else 0.0
	var pulse := 0.5 + 0.5 * sin(_time * TAU * 1.6)
	var glow := _linear(team_color) * _special_glow * (0.35 + 0.45 * pulse)
	var team_linear := _linear(team_color)
	var wig_speed := minf(speed/11.0,1.0)
	for entry in _material_entries:
		if not (entry.mesh as MeshInstance3D).is_visible_in_tree(): continue
		var kind := String(entry.kind)
		# Original setHurt paints enemy ink over the character. White material
		# emission belongs only to the source invulnerability uFlash waveform.
		_set_parameter(entry,&"hit_flash",0.0)
		_set_parameter(entry,&"uTime",_time)
		_set_parameter(entry,&"uHurt",Vector4(hurt_rgb.x,hurt_rgb.y,hurt_rgb.z,hurt))
		_set_parameter(entry,&"uWig",Vector3(0.014+wig_speed*0.028,9.0+wig_speed*12.0,0.0))
		_set_parameter(entry,&"charge",charge)
		if kind == "coil":
			_set_parameter(entry,&"uCharge",charge)
			_set_parameter(entry,&"uFull",1.0 if charge>=0.995 else 0.0)
			_set_parameter(entry,&"uFlash",_charge_flash)
		else:
			_set_parameter(entry,&"uFlash",Vector3.ONE*invuln_flash)
			_set_parameter(entry,&"uGlow",glow)
		if kind == "fill":
			_set_parameter(entry,&"emission_color",team_linear)
			_set_parameter(entry,&"emission_intensity",0.12+0.9*_low_ink*(0.5+0.5*sin(_time*TAU*3.2))+0.3*_special_glow*pulse)
	profile_tick = _profile_span(&"uniforms",profile_tick)
	_animate_weapon(delta, charge, firing, grounded, speed, state)
	_profile_span(&"weapon",profile_tick)
	if presentation_interpolation:
		var previous_ticks:bool=_presentation_ticks
		_presentation_ticks=bool(state.get("presentation_tick",Engine.is_in_physics_frame())) and (not _presentation_local_only or bool(state.get("is_local",false)))
		if _presentation_lower_only:
			var full_body:bool=bool(_tree.get("parameters/Action/active")) and not _action_node.filter_enabled
			_presentation_ticks=_presentation_ticks and _native_motion_active and motion_matching and grounded and _form=="kid" and _form_time>=.45 and _dance.is_empty() and not full_body and not bool(state.get("superJump",state.get("super_jump",false)))
		if _presentation_ticks:
			if _presentation==null:_configure_presentation()
			if _presentation_lower_only and not _presentation_coherent_root:
				# Current support legs keep their exact solved world contact. Only
				# swing legs interpolate; no extra render-time IK or spring step.
				var held:=PackedInt32Array()
				for leg:int in 2:
					if bool(_foot_plant._contact[leg]):
						for part:int in 4:held.append(_presentation_leg_indices[leg*4+part])
				_presentation.set_held_bones(0,held)
			_presentation.capture(self,not previous_ticks)
			_capture_presentation_sockets()
		elif _presentation_lower_only and _presentation!=null:_presentation.invalidate()
	if profile_animation:
		animation_profile[&"total"] = Time.get_ticks_usec()-profile_start
		animation_profile.merge(profile_metrics,true)
		animation_profile[&"uniform_updates"] = uniform_updates
		if presentation_active:
			animation_profile[&"presentation_capture"]=_presentation.profile.get("capture_us",0)
			animation_profile[&"presentation_restore"]=_presentation.profile.get("restore_us",0)
			animation_profile[&"presentation_render"]=_presentation.profile.get("render_us",0)

func _configure_presentation() -> void:
	if _skeleton==null:return
	if _presentation==null:
		if _presentation_coherent_pelvis:_presentation=load("res://scripts/animation/experiments/ink_coherent_pelvis_presentation.gd").new()
		elif _presentation_coherent_root:_presentation=load("res://scripts/animation/experiments/ink_coherent_presentation.gd").new()
		else:_presentation=PosePresentation.new()
	if _presentation_lower_only:
		_presentation_leg_indices.clear()
		for bone:String in PRESENTATION_LEG_BONES:_presentation_leg_indices.append(_skeleton.find_bone(bone))
		if _presentation_leg_indices.has(-1):
			push_error("Lower presentation requires all eight original leg joints")
			_presentation.invalidate()
			return
		var lower_rigs:Array[Skeleton3D]=[_skeleton]
		var lower_indices:Array[PackedInt32Array]=[_presentation_leg_indices]
		var lower_visibility:Array[Node3D]=[_kid]
		var module_bindings:Array[Dictionary]=[]
		if _presentation_coherent_root:
			var transfer_indices:PackedInt32Array=_presentation_leg_indices.duplicate()
			if _presentation_coherent_pelvis:
				var hips:int=_skeleton.find_bone("hips")
				transfer_indices.append(hips)
				for bone:int in _skeleton.get_bone_count():
					if _skeleton.get_bone_parent(bone)==hips and not transfer_indices.has(bone):transfer_indices.append(bone)
			for module_index:int in _modules.size():
				var mapped:=PackedInt32Array()
				var sources:=PackedInt32Array()
				var offsets:=PackedVector3Array()
				for bone:int in _pose_maps[module_index].size():
					var source:int=_pose_maps[module_index][bone]
					if not transfer_indices.has(source):continue
					mapped.append(bone)
					sources.append(source)
					offsets.append(_module_rest_offsets[module_index][bone])
				if mapped.is_empty():continue
				lower_rigs.append(_modules[module_index])
				lower_indices.append(mapped)
				lower_visibility.append(_kid)
				module_bindings.append({"node":_modules[module_index],"indices":mapped,"sources":sources,"offsets":offsets})
		_presentation.configure(lower_rigs,[],[],Callable(),lower_indices,lower_indices,lower_visibility,_presentation_coherent_root)
		if _presentation_coherent_root:_presentation.call("configure_modules",module_bindings)
		_presentation.capture(self,true)
		_capture_presentation_sockets()
		return
	var rigs:Array[Skeleton3D]=[_skeleton]
	var used_indices:Array[PackedInt32Array]=[]
	var visibility:Array[Node3D]=[_kid]
	var body_indices:=PackedInt32Array()
	for bone:int in _skeleton.get_bone_count():body_indices.append(bone)
	used_indices.append(body_indices)
	for i:int in _modules.size():
		var rig:Skeleton3D=_modules[i]
		if rig in rigs:continue
		rigs.append(rig)
		visibility.append(_kid)
		var indices:=PackedInt32Array()
		for bone:int in _pose_maps[i].size():
			if _pose_maps[i][bone]>=0:indices.append(bone)
		used_indices.append(indices)
	var nodes:Array[Node3D]=[]
	for node in [_body,_kid,_find_node(_body,"Model"),_weapon_r,_weapon_l,_weapon,_left_weapon,_weapon_offset,_left_weapon_offset,_tank_fill,_squid,_bomb]+_face_nodes:
		if node is Node3D:nodes.append(node)
	for item:Dictionary in _part_rest.values():nodes.append(item.node)
	for motion:Dictionary in _weapon_motion:
		if motion.drum is Node3D:nodes.append(motion.drum)
	_presentation.configure(rigs,nodes,_material_entries,Callable(self,"_set_parameter"),used_indices,[],visibility)
	_refresh_presentation_bones()
	_presentation.capture(self,true)
	_capture_presentation_sockets()

func _refresh_presentation_bones() -> void:
	if _presentation==null:return
	if _presentation_lower_only:return
	var roots:Array[Node3D]=[_body,_hair,_brows]
	var assets:Array[String]=["body","hair_%d_%d"%[_loaded_look.x,_loaded_look.y],"brows_%d"%_loaded_look.z]
	for rig_index:int in _presentation._rigs.size():
		var rig:Skeleton3D=_presentation._rigs[rig_index].node
		var names:Dictionary={}
		var info:Dictionary=_catalog.assets.get(assets[rig_index],{})
		if roots[rig_index]!=null:
			for mesh:MeshInstance3D in roots[rig_index].find_children("*","MeshInstance3D",true,false):
				# Local visibility is the selected source LOD. Ancestor visibility
				# is checked at render time so a form change needs no mask rebuild.
				if not mesh.visible:continue
				var data:Dictionary=info.get("meshes",{}).get(String(mesh.name),{})
				for bone_name:String in data.get("used_bones",[]):names[bone_name]=true
		if names.is_empty():
			for bone_name:String in info.get("used_bones",[]):names[bone_name]=true
		# These unweighted scale channels drive the source eyelid deformation.
		if rig_index==0:
			names["eyeL"]=true
			names["eyeR"]=true
		var indices:=PackedInt32Array()
		for bone_name:String in names:
			var bone:int=rig.find_bone(bone_name)
			if bone>=0:indices.append(bone)
		_presentation.set_render_bones(rig_index,indices)

func restore_presentation() -> void:
	if _presentation!=null:_presentation.restore(self)

func reset_presentation() -> void:
	if _presentation==null:return
	# The caller has already set a spawn/teleport root. Preserve that new root
	# while restoring all local bone/module/weapon/face state from the tick.
	if _presentation_coherent_root:
		# Actor owns the teleport and sets the new visual Y offset. A displayed
		# interpolation offset in local X/Z must not become the new tick root.
		var spawn_y:float=position.y
		_presentation.restore(self)
		position.y=spawn_y
	else:_presentation.restore(self,true)
	_presentation.capture(self,true)
	_capture_presentation_sockets()
	_update_face_materials()

func presentation_position() -> Vector3:
	# The coherent experiment smooths only the displayed body. Camera springs and
	# the aim camera continue to consume the current authoritative physics target.
	if presentation_active and _presentation_coherent_root:return _presentation.authoritative_root(self).origin
	return _presentation.position_at(Engine.get_physics_interpolation_fraction()) if presentation_active and not _presentation_lower_only else global_position

func present(fraction:float) -> bool:
	if not presentation_active:return false
	var begin:=Time.get_ticks_usec()
	if not _presentation.render(self,fraction):return false
	# Facial shader bases must use the same interpolated bones and hidden face
	# channels as skin deformation, so eyes/mouth cannot lag behind the head.
	if not _presentation_lower_only:_update_face_materials()
	_presentation.profile.render_us=Time.get_ticks_usec()-begin
	return true

func _capture_presentation_sockets() -> void:
	var inv:=global_transform.affine_inverse()
	_presentation_kid=inv*_kid.global_transform
	var head:=_skeleton.find_bone("head")
	_presentation_head=inv*(_skeleton.global_transform*(_skeleton.get_bone_global_pose(head)*Vector3(0.0,.164,.014)))
	for hand:int in 2:
		var marker:Node3D=_muzzle if hand==0 else _left_muzzle
		var pivot:Node3D=_weapon_r if hand==0 else _weapon_l
		if marker==null or pivot==null:
			_presentation_muzzles[hand]=_presentation_muzzles[0] if hand==1 else Vector3(-.16,.9,.4)
			continue
		# BoneAttachment nodes can still contain the preceding render pose until
		# their deferred update. Cancel it and reconstruct from authoritative FK.
		var local_marker:=pivot.global_transform.affine_inverse()*marker.global_position
		_presentation_muzzles[hand]=inv*(_skeleton.global_transform*(_skeleton.get_bone_global_pose(_hand_bones[hand])*pivot.transform*local_marker))

func _profile_span(label: StringName, previous: int) -> int:
	if not profile_animation: return 0
	var tick := Time.get_ticks_usec()
	animation_profile[label] = tick-previous
	return tick

func _set_parameter(entry: Dictionary, name: StringName, value: Variant) -> void:
	# Hidden LODs acquire current values on their first visible update. Only send
	# declared parameters, and avoid repeating unchanged values to RenderingServer.
	if not (entry.parameters as Dictionary).has(name): return
	var sent: Dictionary = entry.sent
	if sent.has(name) and sent[name]==value: return
	(entry.material as ShaderMaterial).set_shader_parameter(name,value)
	sent[name] = value
	uniform_updates += 1

func _apply_pitched_aim(state: Dictionary) -> void:
	if _arm_aim==null or _weapon_offset==null or _form!="kid" or weapon_id=="roller" or _sub_weight>0.1 or not _dance.is_empty(): return
	if bool(_tree.get("parameters/Action/active")) and not _action_node.filter_enabled: return
	var data: Dictionary = _aim_frames.get("weapons",{}).get(weapon_id,{})
	if data.is_empty(): return
	var right := _skeleton.get_bone_global_pose(_hand_bones[0])*_weapon_r.transform*_weapon_offset.transform
	var left := Transform3D.IDENTITY
	if _left_weapon_offset != null:
		left = _skeleton.get_bone_global_pose(_hand_bones[1])*_weapon_l.transform*_left_weapon_offset.transform
	_arm_aim.apply(_skeleton,data,right,left,float(state.get("aim_pitch",state.get("aimPitch",0.0))),_aim_weight,weapon_id=="dualies",_blaster_pump() if weapon_id=="blaster" else 0.0,weapon_id=="slosher")

func _blaster_pump() -> float:
	var u := _shot_time
	if u>=0.6: return 0.0
	return 0.0 if u<0.14 else _minimum_jerk((u-0.14)/0.15) if u<0.29 else 1.0 if u<0.33 else 1.0-_minimum_jerk((u-0.33)/0.13) if u<0.46 else -0.1*sin(PI*minf(1.0,(u-0.46)/0.12))

func _copy_module_poses() -> void:
	for module_index in _modules.size():
		var rig := _modules[module_index]
		var indices := _pose_maps[module_index]
		for bone in indices.size():
			var source: int = indices[bone]
			if source < 0:
				continue
			# Hair/headgear have their own authored rest joints; transfer animation deltas.
			rig.set_bone_pose_position(bone,_skeleton.get_bone_pose_position(source)+_module_rest_offsets[module_index][bone])
			rig.set_bone_pose_rotation(bone, _skeleton.get_bone_pose_rotation(source))
			rig.set_bone_pose_scale(bone, _skeleton.get_bone_pose_scale(source))

func _update_face_materials() -> void:
	if _face_nodes.size()!=7 or _face_nodes[0]==null: return
	var basis: Array[Basis] = []
	for i in _face_bones.size():
		basis.append(_skeleton.get_bone_global_pose(_face_bones[i]).basis*_face_rest[i])
	var open := Vector2(_skeleton.get_bone_pose_scale(_eye_bones[0]).y,_skeleton.get_bone_pose_scale(_eye_bones[1]).y)
	var head_scale := maxf(0.00001,_skeleton.get_bone_pose_scale(_face_bones[0]).y)
	var close := ((Vector2.ONE-open/head_scale)/0.93).clamp(Vector2.ZERO,Vector2.ONE)
	var mouth := _face_nodes[0].position
	var expression := _face_nodes[1].position
	var mood := _face_nodes[2].position
	var look := _face_nodes[3].position
	var gaze_l := _face_nodes[4].position
	var gaze_r := _face_nodes[5].position
	var lid := _face_nodes[6].position
	for entry in _face_materials:
		if not (entry.mesh as MeshInstance3D).is_visible_in_tree(): continue
		_set_parameter(entry,&"native_face_head",basis[0])
		_set_parameter(entry,&"native_eye_close",close)
		_set_parameter(entry,&"uLid",Vector4(gaze_r.y,gaze_r.z,lid.x,lid.y))
		if entry.kind=="skin":
			for i in range(1,6):
				_set_parameter(entry,FACE_MATRIX_PARAMETERS[i],basis[i])
			_set_parameter(entry,&"uMouth",Vector4(mouth.x,mouth.y,mouth.z,expression.x))
			_set_parameter(entry,&"uMouth2",Vector4(mood.x,expression.y,expression.z,mood.y))
		else:
			_set_parameter(entry,&"uLook",Vector2(look.x,look.y))
			_set_parameter(entry,&"uGaze",Vector4(gaze_l.x,gaze_l.y,gaze_l.z,gaze_r.x))
			_set_parameter(entry,&"uPupil",mood.z)

func _update_lod(state: Dictionary) -> void:
	if force_lod >= 0:
		_apply_lod(clampi(force_lod, 0, 2))
		return
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		_apply_lod(0)
		return
	var distance := maxf(0.2, camera.global_position.distance_to(global_position + Vector3.UP * 0.66))
	var projected := 1.32 * get_viewport().get_visible_rect().size.y / (2.0 * distance * tan(deg_to_rad(camera.fov * 0.5)))
	var hero := 150.0 if bool(state.get("is_local", false)) else 430.0
	var wanted := 0 if projected >= hero else 2 if projected < 78.0 else 1
	# Original twelve-percent hysteresis avoids repeated LOD changes at a threshold.
	if _lod == 0 and projected >= hero * 0.88:
		wanted = 0
	elif _lod == 2 and projected <= 78.0 * 1.12:
		wanted = 2
	if OS.has_feature("mobile"):
		wanted = maxi(1, wanted)
	_apply_lod(wanted)

func _apply_lod(tier: int) -> void:
	var changed:bool=_lod!=tier
	_lod = tier
	for root in [_body, _hair]:
		if root == null:
			continue
		for item in root.find_children("*", "MeshInstance3D", true, false):
			var part_name := String(item.name)
			var mesh_tier := 1 if part_name.ends_with("Game") else 2 if part_name.ends_with("Far") else 0
			if part_name.begins_with("Skin") or part_name.begins_with("Cloth") or part_name.begins_with("Eyes") or part_name.begins_with("Hair"):
				item.visible = mesh_tier == tier
				# Original far tier casts only the body's bulk; distant strands
				# do not render into the shadow atlas.
				if part_name.begins_with("Hair") and mesh_tier==2:
					item.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	for weapon_part in [_weapon, _left_weapon]:
		if weapon_part == null:
			continue
		for name in ["WeaponBody", "WeaponInk", "WeaponBodyFar", "WeaponInkFar"]:
			var mesh := _find_node(weapon_part, name) as Node3D
			if mesh != null:
				mesh.visible = name.ends_with("Far") == (tier == 2)
		for part in weapon_part.find_children("Part_*", "Node3D", true, false):
			part.visible = tier != 2
	if _body != null:
		var glass := _find_node(_body, "TankGlass") as Node3D
		if glass != null:
			glass.visible = tier != 2
	if changed and _presentation!=null:_refresh_presentation_bones()

func _update_form_scales() -> void:
	var to_kid := _form == "kid"
	var from_kid := _previous_form == "kid"
	var t := _form_time
	var kid_y := 1.0
	var kid_xz := 1.0
	var squid_y := 1.0
	var squid_xz := 1.0
	var lift := 0.0
	_kid_pop = 1.0 if to_kid else 0.0
	_form_weight = 0.0 if to_kid else 1.0
	if to_kid and not from_kid and t < 0.45:
		_form_weight = 1.0 if t < 0.06 else 1.0 - _ease_in((t - 0.06) / 0.035)
		squid_y = _curve(t, EM_ST, EM_SY)
		squid_xz = _curve(t, EM_ST, EM_SX)
		_kid_pop = 0.0 if t < 0.045 else _ease_out((t - 0.045) / 0.055)
		kid_y = _curve(t, EM_KT, EM_KY)
		kid_xz = _curve(t, EM_KT, EM_KX)
		lift = (-0.3 if _previous_form == "swim" else -0.05 if _previous_form == "climb" else -0.12) * (1.0 - _ease_out((t - 0.045) / 0.1))
	elif not to_kid and from_kid and t < 0.45:
		kid_y = _curve(t, DV_KT, DV_KY)
		kid_xz = _curve(t, DV_KT, DV_KX)
		_kid_pop = 1.0 if t < 0.07 else 1.0 - _ease_in((t - 0.07) / 0.03)
		_form_weight = 0.0 if t < 0.045 else _ease_out((t - 0.045) / 0.035)
		squid_y = _curve(t, DV_ST, DV_SY)
		squid_xz = _curve(t, DV_ST, DV_SX)
	_squid_stretch = Vector2(squid_xz, squid_y)
	_body.scale = Vector3(kid_xz, kid_y, kid_xz) * maxf(0.001, _kid_pop)
	_body.position.y = lift
	_body.visible = _kid_pop > 0.001

static func _ease_in(value: float) -> float:
	return pow(clampf(value, 0.0, 1.0), 2.0)

static func _ease_out(value: float) -> float:
	return 1.0 - pow(1.0 - clampf(value, 0.0, 1.0), 2.0)

static func _curve(t: float, times: Array, values: Array) -> float:
	var count := times.size()
	if t <= float(times[0]):
		return float(values[0])
	if t >= float(times[count - 1]):
		return float(values[count - 1])
	var index := 1
	while float(times[index]) < t:
		index += 1
	var h: float = times[index] - times[index - 1]
	var u: float = (t - times[index - 1]) / h
	var m0: float = (values[index] - values[index - 2]) / (times[index] - times[index - 2]) if index > 1 else 0.0
	var m1: float = (values[index + 1] - values[index - 1]) / (times[index + 1] - times[index - 1]) if index < count - 1 else 0.0
	var u2 := u * u
	var u3 := u2 * u
	return (2.0 * u3 - 3.0 * u2 + 1.0) * values[index - 1] + (u3 - 2.0 * u2 + u) * h * m0 + (-2.0 * u3 + 3.0 * u2) * values[index] + (u3 - u2) * h * m1

func _animate_squid(delta: float, speed: float, local_velocity: Vector3, state: Dictionary) -> void:
	if _squid == null:
		return
	_squid.visible = _form_weight > 0.001
	if not _squid.visible:
		_squid_initialized = false
		return
	var squid_form := _previous_form if _form == "kid" else _form
	var swimming := squid_form == "swim"
	var climbing := squid_form == "climb"
	var stretch := 1.0 + 0.035 * sin(_time * 3.1) + 0.012 * sin(_time * 7.3)
	var pitch := 0.0
	var target_position := Vector3(0.0, 0.165, 0.0)
	var target_rotation := Quaternion.IDENTITY
	var wall: Vector3 = state.get("wall_normal", Vector3.ZERO)
	var airborne := not bool(state.get("grounded", true))
	if climbing and wall.length_squared() > 0.01:
		var n := wall.normalized()
		var up := Vector3.UP - n * Vector3.UP.dot(n)
		if up.length_squared() < 0.0001:
			up = Vector3.BACK
		up = up.normalized()
		var forward := -n
		var side := up.cross(forward).normalized()
		var climb_v := minf(1.0, absf(local_velocity.y) / 5.0 + speed / 6.0)
		var facing := Quaternion(forward, sin(_time * 11.0) * 0.16 * climb_v) * Basis(side, up, forward).get_rotation_quaternion()
		target_rotation = global_basis.orthonormalized().get_rotation_quaternion().inverse() * facing
		var world_point := global_position + Vector3.UP * (0.26 + 0.025 * sin(_time * 14.0) * climb_v) - n * 0.45 + side * (0.022 * sin(_time * 5.5) * climb_v)
		target_position = to_local(world_point)
		stretch = 1.0 + 0.1 * climb_v + 0.05 * sin(_time * 14.0) * climb_v
	elif swimming and not airborne:
		var sv := minf(speed / 11.0, 1.0)
		var und := sin(_time * lerpf(5.0, 14.0, sv))
		if speed > 0.3:
			_squid_yaw = lerp_angle(_squid_yaw, atan2(local_velocity.x, local_velocity.z), 1.0 - exp(-delta * 10.0))
		_squid_roll = lerpf(_squid_roll, clampf(-float(state.get("turnRate", 0.0)) * 0.08, -0.5, 0.5), 1.0 - exp(-delta * 6.0))
		target_rotation = Basis.from_euler(Vector3(PI * 0.5 + 0.06 * und * sv, _squid_yaw + 0.1 * sin(_time * lerpf(4.0, 11.0, sv) + 1.0) * sv, _squid_roll + und * 0.12 * minf(1.0, speed / 4.0)), EULER_ORDER_YXZ).get_rotation_quaternion()
		target_position = Vector3(0.0, -0.085 + 0.012 * sin(_time * 5.0), 0.0) + target_rotation * Vector3(0.0, -0.12, 0.0)
		stretch = 1.0 + 0.2 * sv + 0.03 * und * sv
	elif airborne:
		pitch = PI * 0.5 - atan2(local_velocity.y, maxf(speed, 0.5)) if speed > 2.0 else -local_velocity.y * 0.03
		stretch += clampf(absf(local_velocity.y) * 0.022, 0.0, 0.24)
		target_position.y = 0.22
	elif speed > 0.25:
		_hop_phase += delta * speed / 0.72
		var phase := fmod(_hop_phase, 1.0)
		var k := minf(1.0, speed / 1.5)
		var air_u := clampf((phase - 0.14) / 0.72, 0.0, 1.0)
		var anticipation := sin(PI * phase / 0.14) if phase < 0.14 else 0.0
		var landing := sin(PI * (phase - 0.86) / 0.14) if phase > 0.86 else 0.0
		target_position.y += 0.14 * sin(PI * air_u) * k
		pitch = (0.3 * cos(PI * air_u) - 0.1) * k
		stretch = 1.0 - 0.2 * anticipation * k + 0.16 * sin(PI * air_u) * k - 0.16 * landing * k
	else:
		_hop_phase = 0.0
		_squid_yaw = lerp_angle(_squid_yaw, 0.0, 1.0 - exp(-delta * 3.0))
	if not climbing and not (swimming and not airborne) and not (airborne and (speed>3.0 or swimming or _previous_form=="climb")):
		stretch*=1.0+clampf(_hit.sample(HitResponse.Channel.SQ_Y),-.3,.3)
		pitch+=_hit.sample(HitResponse.Channel.SQ_PITCH)*.3
	if not climbing and not (swimming and not airborne):
		if speed > 0.3:
			_squid_yaw = lerp_angle(_squid_yaw, atan2(local_velocity.x, local_velocity.z), 1.0 - exp(-delta * 10.0))
		target_rotation = Basis.from_euler(Vector3(pitch, _squid_yaw, 0.05 * sin(_time * 2.3)), EULER_ORDER_YXZ).get_rotation_quaternion()
	var squash := 1.0 / sqrt(maxf(stretch, 0.01))
	_squid.scale = Vector3(squash * _squid_stretch.x, stretch * _squid_stretch.y, squash * _squid_stretch.x) * maxf(_form_weight, 0.001)
	if not _squid_initialized:
		_squid.position = target_position
		_squid.quaternion = target_rotation
		_squid_initialized = true
	_squid.position = _squid.position.lerp(target_position, 1.0 - exp(-delta * 26.0))
	_squid.quaternion = _squid.quaternion.slerp(target_rotation, 1.0 - exp(-delta * 26.0))

func _animate_weapon(delta: float, charge: float, firing: bool, grounded: bool, speed: float, state: Dictionary) -> void:
	# Direct port of source character-weapons.js animateWeapon: each hand owns spring/inertia state.
	for item in _part_rest.values():
		var node: Node3D = item.node
		node.transform = item.transform
	for hand in _weapon_motion.size():
		var motion: Dictionary = _weapon_motion[hand]
		var parts: Dictionary = motion.parts
		var ps: PackedFloat32Array = motion.ps
		var ts := float(_shot_hand[hand])
		var u := _shot_time
		var shot := _pulse(ts, 0.006, 30.0)
		if motion.drum != null:
			if _rolling > 0.3 and grounded:
				motion.drum_speed = speed / 0.1
			else:
				motion.drum_speed *= exp(-delta * 2.2)
			if _flick_time >= 0.15 and _flick_time - delta < 0.15:
				motion.drum_speed += 34.0
			motion.drum_angle = fmod(float(motion.drum_angle) + float(motion.drum_speed) * delta, TAU)
			(motion.drum as Node3D).rotation.x = float(motion.drum_angle)
		if _lod == 2:
			continue
		if parts.has("trigger"):
			var want := charge > 0.01 if weapon_id == "charger" else firing or charge > 0.01 if weapon_id == "splatling" else ts < 0.07 if weapon_id in ["blaster", "dualies"] else firing and u < 0.16
			motion.trigger = lerpf(float(motion.trigger), 1.0 if want else 0.0, 1.0 - exp(-delta * (45.0 if want else 22.0)))
			(parts.trigger as Node3D).rotation.x = 0.42 * float(motion.trigger)
		match weapon_id:
			"shooter":
				(parts.bolt as Node3D).position.z -= 0.0095 * shot
				var ck := _pulse(ts, 0.01, 18.0)
				(parts.can as Node3D).scale = Vector3(1.0 + 0.07 * ck, 1.0 + 0.07 * ck, 1.0 - 0.035 * ck)
				_led(parts.led, shot)
			"dualies":
				var slide := _pulse(ts, 0.005, 26.0)
				(parts.slide as Node3D).position.z -= 0.013 * slide
				(parts.slideInk as Node3D).position.z -= 0.013 * slide
				_led(parts.led, slide)
			"blaster":
				var pump := _blaster_pump()
				(parts.pump as Node3D).position.z -= 0.036 * pump
				var depress := u < 0.36
				(parts.needle as Node3D).rotation.z = _weapon_spring(ps, 0, -1.95 if depress else 1.3, 9.0 if depress else 4.2, 0.55 if depress else 0.28, delta) + 0.018 * sin(_time * 41.0) * (1.0 if u > 0.6 else 0.3)
				if ts < delta * 1.5:
					ps[3] -= 7.0
				if u >= 0.33 and u - delta < 0.33:
					ps[3] += 4.5
				var bq := clampf(_weapon_spring(ps, 2, 0.0, 7.0, 0.22, delta), -0.3, 0.3)
				(parts.bulb as Node3D).scale = Vector3(1.0 - 0.35 * bq, 1.0 - 0.35 * bq, 1.0 + 0.9 * bq)
			"charger":
				var target := -0.03 * charge
				var bolt := _weapon_spring(ps, 4, target, 5.0 if target < ps[4] else 16.0, 0.32, delta)
				(parts.bolt as Node3D).position.z += clampf(bolt, -0.034, 0.004)
				var full := 1.0 if charge >= 0.995 else 0.0
				var color := _linear(team_color)
				_lamp(parts.lens, color.lerp(Vector3.ONE, full * 0.25), 0.12 + 3.2 * charge * charge + full * (1.2 + 0.8 * sin(_time * 31.0)) + 5.0 * _charge_flash)
				_lamp(parts.eyepiece, color, 0.04 + 0.9 * charge * charge + 0.6 * full)
				if _release_time < delta * 1.5:
					motion.heat = 1.0
				motion.heat *= exp(-delta * 3.2)
				_lamp(parts.ports, color.lerp(Vector3.ONE, float(motion.heat) * 0.5), 6.0 * float(motion.heat) * float(motion.heat))
			"roller":
				_lamp(parts.led, _linear(team_color), 0.5 + 2.6 * (1.0 if sin(_time * PI * 8.0) > 0.0 else 0.15) if _rolling > 0.3 else 0.45)
			"slosher":
				var root: Node3D = _weapon if hand == 0 else _left_weapon
				var off := _find_node(root, "WeaponOffset") as Node3D
				var world_q := off.global_basis.get_rotation_quaternion()
				var axis := world_q * Vector3.UP
				var world_level := Quaternion(axis, Vector3.UP)
				var level := world_q.inverse() * world_level * world_q
				var direction := Vector3(level.x, level.y, level.z)
				var sn := direction.length()
				var angle := wrapf(2.0 * atan2(sn, level.w), -PI, PI)
				direction = direction / sn if sn > 0.00001 else Vector3.RIGHT
				angle = clampf(angle, -0.6, 0.6)
				(parts.surface as Node3D).rotation = Vector3(_weapon_spring(ps, 6, direction.x * angle, 2.2, 0.16, delta), 0.0, _weapon_spring(ps, 8, direction.z * angle, 2.2, 0.16, delta))
				var drain := (_minimum_jerk(u / 0.16) if u < 0.16 else 1.0 - _minimum_jerk((u - 0.16) / 0.44)) if u < 0.6 else 0.0
				(parts.surface as Node3D).position.y += -0.034 * drain + 0.002 * sin(_time * 7.3)
				var rip := 1.0 + 0.02 * sin(_time * 11.0 + 1.3) * (0.3 + drain)
				(parts.surface as Node3D).scale = Vector3(rip * (1.0 - 0.1 * drain), 1.0, (2.0 - rip) * (1.0 - 0.1 * drain))
				(parts.lever as Node3D).rotation.x = -0.4 * (1.0 - _minimum_jerk(maxf(0.0, u - 0.18) / 0.12)) if u < 0.3 else 0.0
			"splatling":
				var charging := bool(state.get("charging", charge > 0.01))
				var streaming := bool(state.get("streaming", firing and not charging))
				var want := 14.0 + 46.0 * charge if charging else 64.0 if streaming else 0.0
				motion.spin_speed = lerpf(float(motion.spin_speed), want, 1.0 - exp(-delta * (5.0 if want > float(motion.spin_speed) else 1.6)))
				motion.spin_angle = fmod(float(motion.spin_angle) + float(motion.spin_speed) * delta, TAU)
				(parts.barrels as Node3D).rotation.z = float(motion.spin_angle)
				(parts.barrels as Node3D).position.z -= 0.004 * shot
		motion.ps = ps

func _led(part: Node3D, shot: float) -> void:
	if _low_ink > 0.5:
		_lamp(part, Vector3(1.0, 0.16, 0.1), 0.4 + 2.2 * (0.5 + 0.5 * sin(_time * PI * 6.4)))
	else:
		_lamp(part, Vector3(0.24, 1.0, 0.48), 1.1 + 4.0 * shot)

func _lamp(part: Node3D, color: Vector3, intensity: float) -> void:
	for child in part.find_children("*", "MeshInstance3D", true, false):
		var material := (child as MeshInstance3D).material_override as ShaderMaterial
		if material != null:
			material.set_shader_parameter("emission_color", color)
			material.set_shader_parameter("emission_intensity", intensity)

static func _pulse(t: float, attack: float, decay: float) -> float:
	return 0.0 if t < 0.0 else t / attack if t < attack else exp(-(t - attack) * decay)

static func _minimum_jerk(t: float) -> float:
	var u := clampf(t, 0.0, 1.0)
	return u * u * u * (10.0 + u * (6.0 * u - 15.0))

static func _weapon_spring(values: PackedFloat32Array, i: int, target: float, hz: float, damping: float, delta: float) -> float:
	var w := TAU * hz
	var x0 := values[i] - target
	var v0 := values[i + 1]
	var wd := w * sqrt(1.0 - damping * damping)
	var e := exp(-damping * w * delta)
	var c := cos(wd * delta)
	var s := sin(wd * delta)
	var b := (v0 + damping * w * x0) / wd
	values[i] = e * (x0 * c + b * s) + target
	values[i + 1] = e * ((-damping * w * x0 + wd * b) * c + (-damping * w * b - wd * x0) * s)
	return values[i]

func trigger(action: String, arg: Variant = null) -> void:
	_ensure_built()
	var translated := {"fire": "shoot", "damage": "hit", "celebration": "victory", "respawn": "spawn", "release": "charge_release"}.get(action, action) as String
	if translated == "shoot":
		_shot_time = 0.0
		var hand := int(arg.get("hand", 0)) if arg is Dictionary else 0
		_shot_hand[clampi(hand, 0, 1)] = 0.0
		_recoil = 1.0
		if weapon_id == "roller":
			translated = "flick"
		elif weapon_id == "slosher":
			translated = "shoot"
		elif weapon_id == "dualies" and hand == 1:
			translated = "shoot_left"
	if translated == "flick":
		_flick_time = 0.0
		_shot_time = 0.0
	if translated == "charge_release":
		_release_time = 0.0
		_shot_time = 0.0
		_charge_flash = 1.0
		_recoil = 1.0
	if translated == "throw":
		_throw_time = 0.0
	if translated == "dodge" and weapon_id == "dualies" and arg is Dictionary:
		var x := float(arg.get("x", 0.0))
		var z := float(arg.get("z", 1.0))
		if absf(x) > absf(z):
			translated = "dodge_left" if x > 0.0 else "dodge_right"
		elif z < 0.0:
			translated = "dodge_back"
	if translated == "hit":
		_flash = 0.42
		var hair_impulse:=_hit.trigger(arg,_form=="kid")
		if _hair_springs!=null:_hair_springs.kick(hair_impulse)
	if _tree == null:
		return
	var name := _clip(translated)
	if not _animation.has_animation(name):
		return
	_action_clip.animation = name
	_action_node.filter_enabled = translated in ["shoot", "shoot_left", "charge_release", "throw", "hit"]
	_configure_action_filters(translated)
	_tree.set("parameters/Action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	current_action = translated

func _configure_action_filters(action:String) -> void:
	var animation:=_animation.get_animation(_action_clip.animation)
	for track_index:int in animation.get_track_count():
		var track:=animation.track_get_path(track_index)
		var bone:String=String(track.get_subname(0)) if track.get_subname_count()>0 else ""
		var path:=String(track)
		var enabled:bool=bone in UPPER_BONES or bone.begins_with("hair") or bone.begins_with("hand") or path.contains("Weapon") or path.contains("Tank") or path.contains("Face") or path.contains("SourceHead")
		if action=="hit":
			# The sampled source clip supplies the blink/expression only. Its
			# fixed-direction body cannot be added to the live spring reaction.
			enabled=bone in ["eyeL","eyeR"] or (_hit.amplitude>.8 and (bone in ["jaw","cheekL","cheekR","browL","browR","mouth","mouthO"] or path.contains("Face")))
		_action_node.set_filter_path(track,enabled)

func set_dance(action: String) -> void:
	_dance = action
	if not action.is_empty():
		trigger(action)
	elif _tree != null:
		_tree.set("parameters/Action/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)

func aim_ready() -> float:
	return 1.0 if _form != "kid" or _weapon == null or weapon_id == "roller" else _aim_weight

func get_aim_muzzle(pitch: float = 0.0) -> Vector3:
	# Source Character.getAimMuzzle: the first round aims from the complete grip
	# pose while the carried weapon is still springing upward toward that pose.
	if _form != "kid" or _weapon == null or weapon_id == "roller" or _kid == null:
		return get_muzzle()
	var data: Dictionary = _aim_frames.get("weapons",{}).get(weapon_id,{})
	if data.is_empty(): return get_muzzle()
	var aim: Dictionary = data.hold.aim
	var p: Array = aim.p
	var r: Array = aim.r
	var clamped_pitch := clampf(pitch,-1.0,1.15)
	var anchor := Vector3(float(p[0]),float(p[1]),float(p[2])).rotated(Vector3.RIGHT,-clampf(clamped_pitch,-0.8,1.0))+Vector3(-0.03,0.93,0.05)
	var rotation := Basis.from_euler(Vector3(float(r[0])-clamped_pitch,float(r[1]),float(r[2])),EULER_ORDER_YXZ)
	var muzzle: Array = data.muzzle
	var kid_transform:Transform3D=_presentation.authoritative_root(self)*_presentation_kid if presentation_active else _kid.global_transform
	return kid_transform*(rotation*Vector3(float(muzzle[0]),float(muzzle[1]),float(muzzle[2]))+anchor)

func get_muzzle() -> Vector3:
	if presentation_active:return _presentation.authoritative_root(self)*_presentation_muzzles[0]
	if is_instance_valid(_muzzle):
		return _muzzle.global_position
	return global_position + global_basis * Vector3(-0.16, 0.9, 0.4)

func get_muzzle_hand(hand: int = 0) -> Vector3:
	if presentation_active:return _presentation.authoritative_root(self)*_presentation_muzzles[clampi(hand,0,1)]
	if hand == 1 and is_instance_valid(_left_weapon):
		var marker := _find_node(_left_weapon, "Muzzle") as Node3D
		if marker != null:
			return marker.global_position
	return get_muzzle()

func get_head_position() -> Vector3:
	if presentation_active:return _presentation.authoritative_root(self)*_presentation_head
	if _skeleton != null:
		var head := _skeleton.find_bone("head")
		if head >= 0:
			return _skeleton.global_transform * (_skeleton.get_bone_global_pose(head) * Vector3(0.0, 0.164, 0.014))
	return global_position + Vector3.UP * 1.214

func _clip(action: String) -> StringName:
	var key := weapon_id + "_" + action
	if _animation != null:
		if _animation.has_animation(key):
			return StringName(key)
		for name in _animation.get_animation_list():
			if String(name).ends_with(key):
				return name
	return StringName(key)

func _source_clip_name(name: String) -> String:
	return name.get_slice("/", name.get_slice_count("/") - 1)

static func update_source_crablet(root: Node3D, dt: float, speed: float = 0.0, dead: bool = false) -> bool:
	if not root.has_meta("source_crablet_animator"):
		var animator := CrabletAnimator.new()
		animator.configure(root)
		root.set_meta("source_crablet_animator",animator)
	var animator := root.get_meta("source_crablet_animator") as InkCrabletAnimator
	return animator.update(dt,speed,dead)

static func hit_source_crablet(root: Node3D) -> void:
	if not root.has_meta("source_crablet_animator"): update_source_crablet(root,0.0)
	(root.get_meta("source_crablet_animator") as InkCrabletAnimator).hit()

static func create_source_asset(key: String, color: Color = Color("2f5bff"), weak_color: Color = Color("ff8a14")) -> Node3D:
	if _catalog.is_empty():
		var decoded: Variant = JSON.parse_string(FileAccess.get_file_as_string(MANIFEST_PATH))
		if decoded is Dictionary:
			_catalog = decoded
	var node := _instantiate_asset(key)
	if node != null:
		for mesh_node in node.find_children("*", "MeshInstance3D", true, false):
			var material := (mesh_node as MeshInstance3D).material_override as ShaderMaterial
			if material != null:
				material.set_shader_parameter("uInk", _linear(color))
				material.set_shader_parameter("uWeak", _linear(weak_color))
	return node

static func _instantiate_asset(key: String) -> Node3D:
	var info: Dictionary = _catalog.get("assets", {}).get(key, {})
	if info.is_empty():
		push_error("INKWAVE character asset missing: " + key)
		return null
	if not _scene_cache.has(key):
		_scene_cache[key] = load(String(info.path))
	var packed := _scene_cache[key] as PackedScene
	if packed == null:
		return null
	var node := packed.instantiate() as Node3D
	if node != null:
		_assign_materials(node, info.get("meshes", {}))
	return node

static func _assign_materials(root: Node, meshes: Dictionary) -> void:
	for mesh_node in root.find_children("*", "MeshInstance3D", true, false):
		var mesh := mesh_node as MeshInstance3D
		var info: Dictionary = meshes.get(String(mesh.name), {})
		if info.is_empty():
			continue
		var kind := String(info.kind)
		if kind == "glass":
			var glass := StandardMaterial3D.new()
			glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			glass.albedo_color = Color(0.949, 0.984, 1.0, 0.14)
			glass.roughness = 0.04
			glass.cull_mode = BaseMaterial3D.CULL_DISABLED
			mesh.material_override = glass
		elif kind == "dark":
			var dark := StandardMaterial3D.new()
			dark.albedo_color = Color(0.018, 0.02, 0.03)
			dark.roughness = 0.5
			mesh.material_override = dark
		else:
			var shader_kind := "ink" if kind in ["fill", "ink", "glow"] else kind
			var material := ShaderMaterial.new()
			material.shader = load("res://assets/shaders/character_%s.gdshader" % shader_kind) as Shader
			if kind.begins_with("boss_"):
				material.set_shader_parameter("uStencil", load("res://assets/characters/boss_stencil.png"))
			material.set_shader_parameter("source_data", load(String(info.data)))
			for i in info.minima.size():
				var lo: Array = info.minima[i]
				var hi: Array = info.maxima[i]
				material.set_shader_parameter("data_min_%d" % i, Vector4(float(lo[0]), float(lo[1]), float(lo[2]), float(lo[3])))
				material.set_shader_parameter("data_max_%d" % i, Vector4(float(hi[0]), float(hi[1]), float(hi[2]), float(hi[3])))
			material.set_meta("iw_kind", kind)
			if kind in ["glow", "fill"]:
				var source_material: Dictionary = info.get("material", {})
				var source_color: Array = source_material.get("color", [0.015, 0.015, 0.015])
				var emission: Array = source_material.get("emission", [1.0, 1.0, 1.0])
				material.set_shader_parameter("use_base_color", 1.0 if kind == "glow" else 0.0)
				material.set_shader_parameter("base_color", Vector3(source_color[0], source_color[1], source_color[2]))
				material.set_shader_parameter("base_roughness", float(source_material.get("roughness", 0.3)))
				material.set_shader_parameter("emission_color", Vector3(emission[0], emission[1], emission[2]))
				material.set_shader_parameter("emission_intensity", float(source_material.get("intensity", 0.12)))
			mesh.material_override = material
		mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if kind in ["eye", "glass", "fill", "glow"] else GeometryInstance3D.SHADOW_CASTING_SETTING_ON

func _refresh_material_list() -> void:
	_materials.clear()
	_material_entries.clear()
	_face_materials.clear()
	for child in find_children("*", "MeshInstance3D", true, false):
		var material := (child as MeshInstance3D).material_override as ShaderMaterial
		if material != null and not material in _materials:
			_materials.append(material)
			var kind := String(material.get_meta("iw_kind",""))
			var shader_id := material.shader.get_instance_id()
			if not _shader_parameters.has(shader_id):
				var names: Dictionary = {}
				for parameter in material.shader.get_shader_uniform_list(): names[StringName(parameter.name)] = true
				_shader_parameters[shader_id] = names
			var entry := {"mesh":child,"material":material,"kind":kind,"parameters":_shader_parameters[shader_id],"sent":{}}
			_material_entries.append(entry)
			if kind in ["skin","eye"]:
				_face_materials.append(entry)
	configure_lighting(_lighting_theme)

func configure_lighting(theme: Dictionary) -> void:
	# Original HemisphereLight is independent of the frozen sky's IBL. Theme
	# colors are sRGB; exported HemisphereLight color/ground arrays are linear.
	_lighting_theme = theme.duplicate()
	var parameters := _hemi_parameters(theme)
	var rim := _rim_parameters(theme)
	for material in _materials:
		material.set_shader_parameter("hemi_sky",parameters.sky)
		material.set_shader_parameter("hemi_ground",parameters.ground)
		material.set_shader_parameter("uIwRim",rim.color)
		material.set_shader_parameter("uIwRimL",rim.direction)
		material.set_shader_parameter("uIwFill",rim.fill)
		material.set_shader_parameter("native_rim_world",rim.world)
		_configure_pmrem(material,theme)

static func _rim_parameters(theme:Dictionary)->Dictionary:
	# Exact Character._updateRim values; menu directions are already view-space.
	# Match directions are transformed in the shader per camera, so reflections
	# and the overlay do not require another camera-dependent uniform upload.
	var rim:=Vector4(.075,.08125,.09375,3.4)
	var direction:=Vector3(.3,.6,-.75).normalized()
	var fill:=Vector3.ZERO
	var in_world:=theme.has("horizon") and theme.has("sunEl") and theme.has("sunAz")
	if in_world:
		var horizon:=_linear(Color(String(theme.horizon)))
		var sun:=_linear(Color(String(theme.sunColor)))
		var intensity:=minf(1.5,float(theme.get("sunIntensity",2.0))/2.5)
		var night:=1.0-.6*float(theme.get("night",0.0))
		var rgb:Vector3=(horizon*.55+sun*.45*intensity)*.32*1.25*night
		rim=Vector4(rgb.x,rgb.y,rgb.z,3.2)
		var elevation:=deg_to_rad(float(theme.sunEl))
		var azimuth:=deg_to_rad(float(theme.sunAz))
		direction=Vector3(cos(elevation)*cos(azimuth),sin(elevation),cos(elevation)*sin(azimuth)).normalized()
		var low:=1.0-smoothstep(.25,.68,direction.y)
		var luminance:=maxf(.05,horizon.dot(Vector3(.3,.59,.11)))
		var factor:=lerpf(.06,.25,low)*1.4*night/luminance
		fill=horizon.lerp(Vector3.ONE*luminance,.5)*factor
	return {"color":rim,"direction":direction,"fill":fill,"world":in_world}

static func configure_source_lighting(root: Node3D, theme: Dictionary) -> void:
	var parameters := _hemi_parameters(theme)
	for node in root.find_children("*","MeshInstance3D",true,false):
		var material := (node as MeshInstance3D).material_override as ShaderMaterial
		if material != null and material.has_meta("iw_kind"):
			material.set_shader_parameter("hemi_sky",parameters.sky)
			material.set_shader_parameter("hemi_ground",parameters.ground)
			_configure_pmrem(material,theme)

static func _configure_pmrem(material: ShaderMaterial, theme: Dictionary) -> void:
	# Original atlas is already convolved; the material reads the source roughness
	# lobes directly without triggering Godot sky rebakes or a second BRDF.
	var pmrem := theme.get("source_pmrem") as Texture2D
	material.set_shader_parameter("source_pmrem_enabled",pmrem!=null)
	if pmrem!=null:
		material.set_shader_parameter("source_pmrem",pmrem)
		material.set_shader_parameter("source_pmrem_size",Vector2(pmrem.get_width(),pmrem.get_height()))
		material.set_shader_parameter("source_pmrem_max_mip",log(float(pmrem.get_height())/4.0)/log(2.0))
	material.set_shader_parameter("source_env_intensity",float(theme.get("envK",theme.get("source_env_intensity",0.45))))

static func _hemi_parameters(theme: Dictionary) -> Dictionary:
	var sky := Vector3.ZERO
	var ground := Vector3.ZERO
	if theme.has("hemiSky"):
		sky = _linear(Color(String(theme.hemiSky)))*float(theme.get("hemiIntensity",0.0))/PI
		ground = _linear(Color(String(theme.hemiGround)))*float(theme.get("hemiGroundK",1.0))*float(theme.get("hemiIntensity",0.0))/PI
	elif theme.get("type","")=="HemisphereLight":
		var s: Array = theme.color
		var g: Array = theme.ground
		sky = Vector3(float(s[0]),float(s[1]),float(s[2]))*float(theme.intensity)/PI
		ground = Vector3(float(g[0]),float(g[1]),float(g[2]))*float(theme.intensity)/PI
	return {"sky":sky,"ground":ground}

func _apply_palette() -> void:
	var catalog: Dictionary = _catalog.get("catalog", {})
	if catalog.is_empty():
		return
	var outfit: Dictionary = catalog.OUTFITS[int(appearance.outfit)]
	var eyes: Array = catalog.IRIS[int(appearance.eyes)]
	var skin := Color(String(catalog.SKIN_TONES[int(appearance.skin)]))
	var linear_skin := skin.srgb_to_linear()
	var skin_luminance:float=linear_skin.r*.3+linear_skin.g*.59+linear_skin.b*.11
	var scatter_width:=Vector3(.46,.22,.15)*lerpf(1.0,.75,clampf((.62-skin_luminance)/.45,0.0,1.0))
	var scatter_tint:=Vector3(1.0,.38,.26).lerp(Vector3(.75,.3,.2),clampf((.6-skin_luminance)/.4,0.0,1.0))
	for material in _materials:
		material.set_shader_parameter("uTeam", _linear(team_color))
		material.set_shader_parameter("skin_color", _linear(skin))
		material.set_shader_parameter("uSkinLum",skin_luminance)
		material.set_shader_parameter("uSSSW",scatter_width)
		material.set_shader_parameter("uSSSTint",scatter_tint)
		material.set_shader_parameter("uFreckle", 1.0 if int(appearance.skin) == 1 else 0.0)
		material.set_shader_parameter("uPattern", float(outfit.pattern))
		material.set_shader_parameter("uIris", _linear(Color(String(eyes[0]))))
		material.set_shader_parameter("uIris2", _linear(Color(String(eyes[1]))))
		for field in ["shirt", "shorts", "shoe", "sole", "sock", "strap"]:
			material.set_shader_parameter("u" + field.capitalize(), _linear(Color(String(outfit[field]))))
		material.set_shader_parameter("uMouth", Vector4(0.75, 1.0, 0.0, 0.0))
		material.set_shader_parameter("uMouth2", Vector4.ZERO)
		material.set_shader_parameter("uHurtSeed", float(int(appearance.hair) * 17 + int(appearance.skin)) * 0.37)
		if _catalog.has("face"):
			var center: Array = _catalog.face.mouthC
			var forward: Array = _catalog.face.mouthF
			material.set_shader_parameter("uMouthC", Vector3(float(center[0]), float(center[1]), float(center[2])))
			material.set_shader_parameter("uMouthF", Vector3(float(forward[0]), float(forward[1]), float(forward[2])))

static func _linear(color: Color) -> Vector3:
	var c := color.srgb_to_linear()
	return Vector3(c.r, c.g, c.b)

static func _find_node(root: Node, name: String) -> Node:
	if String(root.name) == name:
		return root
	return root.find_child(name, true, false)

static func _find_type(root: Node, type: String) -> Node:
	if root.is_class(type):
		return root
	var matches := root.find_children("*", type, true, false)
	return matches[0] if not matches.is_empty() else null
