extends SceneTree
## Three production Tidewater ledge scenarios. Deferred main scene, eight real
## actors, original source collision/physics, real Input events, no readbacks.
## spawn_at/follow are documented setup only; all movement is from the controller.

const SOURCE_PATHS := [
	"res://scenes/main.tscn", "res://scripts/ink_game.gd",
	"res://scripts/game/ink_actor.gd", "res://scripts/game/ink_actor_physics.gd",
	"res://scripts/game/ink_player_controller.gd", "res://scripts/characters/ink_avatar.gd",
	"res://scripts/animation/ink_foot_plant.gd", "res://scripts/animation/ink_motion_matcher.gd",
	"res://scripts/animation/ink_landing_response.gd", "res://scripts/animation/ink_hit_recoil.gd",
	"res://scripts/animation/ink_motion_matcher_fast.gd", "res://scripts/animation/native_motion_matcher.gd",
	"res://scripts/game/ink_camera_rig.gd", "res://data/config.json", "res://data/tidewater.json",
	"res://data/actor_physics/tidewater.json", "res://data/motion_matching.json",
	"res://assets/actor_physics/tidewater.bin",
	"res://assets/animation/locomotion.features.bin", "res://assets/animation/locomotion.poses.bin",
	"res://tools/locomotion_physics_observer.gd", "res://tools/verify_locomotion_real_chain.gd",
	"res://tools/landing_physics_observer.gd", "res://tools/verify_landing_real_chain.gd",
]

var output: String = "res://shots/landing-real-144-baseline.json"
var fps: int = 144
var quality: String = "low"
var pulse: float = 0.10
var finish_time: float = 12.0
var game: Node
var actor: Node3D
var avatar: Node3D
var rig: Skeleton3D
var observer: Node
var stage: Node
var spawn_point := Vector3.ZERO
var forward := Vector3.BACK
var setup_geometry: Dictionary = {}
var source_before: Dictionary = {}
var events: Array[Dictionary] = []
var held: Array = []
var phase: String = "setup"
var case_id: String = "walk_off"
var event_index: int = 0
var start_clock: float = 0.0
var start_wall: int = 0
var last_wall: int = 0
var last_render_tick: int = -1
var live: bool = false
var finishing: bool = false
var checks: int = 0
var failures: Array[String] = []
var physics_rows: Array[Dictionary] = []
var render_rows: Array[Dictionary] = []
var input_events: Array[Dictionary] = []
var setups: Array[Dictionary] = []
var frame_intervals: Array[float] = []
var latest_physics: Dictionary = {}

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--landing-output="): output = arg.trim_prefix("--landing-output=")
		elif arg.begins_with("--landing-fps="): fps = clampi(int(arg.trim_prefix("--landing-fps=")), 15, 240)
		elif arg.begins_with("--landing-quality="): quality = arg.trim_prefix("--landing-quality=")
		elif arg.begins_with("--landing-pulse="): pulse = clampf(float(arg.trim_prefix("--landing-pulse=")), 0.05, 0.18)
	create_timer(50.0).timeout.connect(_watchdog)
	_run.call_deferred()

func _check(label: String, passed: bool) -> void:
	checks += 1
	if passed: return
	failures.append(label)
	push_error("LANDING_REAL " + label)

func _hash_sources() -> Dictionary:
	var result: Dictionary = {}
	for path: String in SOURCE_PATHS:
		# New reaction helpers are absent in the committed pre-fix worktree.
		# Absence is represented in the manifest, without a spurious file error.
		if not FileAccess.file_exists(path):continue
		var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
		var hash := HashingContext.new()
		hash.start(HashingContext.HASH_SHA256)
		hash.update(bytes)
		result[path] = {"bytes": bytes.size(), "sha256": hash.finish().hex_encode()}
	return result

func _run() -> void:
	_check("windowed renderer required", DisplayServer.get_name() != "headless")
	_check("ordinary 60Hz source simulation", Engine.physics_ticks_per_second == 60)
	_check("ordinary time scale", Engine.time_scale == 1.0)
	if not failures.is_empty(): _finish.call_deferred(); return
	source_before = _hash_sources()
	root.size = Vector2i(1280, 720)
	seed(37)
	game = load("res://scenes/main.tscn").instantiate()
	game.set("_args", {"nonpersistent": true, "benchmark-background": true, "page": "online", "benchmark-fps": str(fps)})
	root.add_child(game)
	current_scene = game
	# This fixture exercises W/S/Space with a fixed look. Native desktop pointer
	# motion can otherwise turn the camera while the real key timeline runs.
	# Keyboard actions still pass through Input and the production controller;
	# pointer look is explicitly excluded, not accepted by this landing probe.
	game.set_process_unhandled_input(false)
	game.call("apply_settings", {"quality": quality, "cameraShake": 0.0, "sensitivity": 1.0, "invertY": false, "aimAssist": 0.0, "aimAssistMouse": false})
	game.call("start_match", {"map": "tidewater", "mode": "turf", "duration": 180, "time_of_day": "day", "weapon": "shooter", "palette": 0,
		"style": {"hair": 2, "skin": 3, "outfit": 4, "eyes": 2, "hat": 0, "brows": 1}})
	var quiet: RefCounted = load("res://tools/locomotion_quiet_bots.gd").new()
	quiet.call("configure", game, "normal")
	game.set("bots", quiet)
	await create_timer(4.8).timeout
	_check("real playing scene", game.get("state") == "playing" and current_scene == game)
	_check("eight production actors", game.get("actors").size() == 8)
	actor = game.get("local_player")
	_check("production local player", is_instance_valid(actor) and bool(actor.get("is_local")))
	if not failures.is_empty(): _finish.call_deferred(); return
	avatar = actor.get("avatar")
	rig = avatar.get("_skeleton")
	stage = game.get("stage")
	_check("original 87-bone rig", rig != null and rig.get_bone_count() == 87 and rig.find_bone("hips") >= 0 and rig.find_bone("footL") >= 0 and rig.find_bone("footR") >= 0)
	_check("actual source physics", actor.get("source_physics") != null)
	_check("production mouse capture", Input.mouse_mode == Input.MOUSE_MODE_CAPTURED)
	_check("real Tidewater map", String(stage.get("stage_id")) == "tidewater")
	_check("live local input", not bool(game.get("paused")) and not bool(game.get("_autopilot")) and not bool(game.get("_backgrounded")))
	_prepare_geometry()
	if not failures.is_empty(): _finish.call_deferred(); return
	Engine.max_fps = fps
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	start_clock = float(game.get("match_clock"))
	start_wall = Time.get_ticks_usec()
	last_wall = start_wall
	_prepare_case("walk_off")
	_build_events()
	observer = load("res://tools/landing_physics_observer.gd").new()
	root.add_child(observer)
	observer.call("configure", game, actor, Callable(self, "_sample_physics"))
	observer.call("mark_setup_reset")
	live = true
	RenderingServer.frame_post_draw.connect(_sample_render)
	print("LANDING_REAL_BEGIN ", JSON.stringify({"scene": game.scene_file_path, "fps_limit": fps, "quality": quality, "pulse_s": pulse,
		"setup": setup_geometry, "motion_script": _motion_script(), "native": avatar.get("_native_motion_active"), "presentation_mode": avatar.get("presentation_mode"), "input_scheduler": "after production physics, before the next production tick"}))

func _prepare_geometry() -> void:
	var layout: Dictionary = stage.get("layout")
	var pad: Array = layout.spawnPads[int(actor.get("team_id"))]
	var center := Vector3(float(pad[0]), float(pad[1]), float(pad[2]))
	forward = Vector3.BACK if center.z < 0.0 else Vector3.FORWARD
	var platform: Dictionary = {}
	for block: Dictionary in stage.get("blocks"):
		var c: Vector3 = block.center
		var h: Vector3 = block.half
		var normal: Vector3 = block.axes[1]
		if not bool(block.solid) or normal.y < 0.999: continue
		if absf(c.x - center.x) >= h.x or absf(c.z - center.z) >= h.z: continue
		if absf(c.y + h.y - center.y) > 0.001: continue
		platform = block
		break
	_check("flat production spawn platform found", not platform.is_empty())
	if platform.is_empty(): return
	var c: Vector3 = platform.center
	var h: Vector3 = platform.half
	var edge_z: float = c.z + forward.z * h.z
	spawn_point = Vector3(center.x, center.y, edge_z - forward.z * 0.4)
	var height: float = stage.call("ground_height", spawn_point.x, spawn_point.z, 8.0)
	var below_z: float = edge_z + forward.z * 1.0
	var below: float = stage.call("ground_height", center.x, below_z, 8.0)
	_check("same source spawn platform height 2.2m", is_finite(height) and absf(height - 2.2) < 0.00001 and absf(height - center.y) < 0.00001)
	_check("central edge descends to real floor", is_finite(below) and below <= 0.001 and height - below > 2.0)
	if is_finite(height): spawn_point.y = height
	setup_geometry = {"spawn_pad": _v(center), "platform_block": platform.id, "platform_center": _v(c), "platform_half": _v(h),
		"edge_z": edge_z, "edge_inset_m": 0.4, "prepared_spawn": _v(spawn_point), "forward": _v(forward),
		"queried_spawn_height": height, "queried_below_height": below, "queried_below_z": below_z}

func _prepare_case(id: String) -> void:
	_set_keys([])
	case_id = id
	phase = id + "_wait"
	var yaw: float = atan2(forward.x, forward.z)
	actor.call("spawn_at", spawn_point, yaw)
	# Use the real mouse-look path if a user/device left the production yaw away
	# from the source pad's central exit. No controller field is set directly.
	var difference: float = wrapf(yaw - float(game.get("_yaw")), -PI, PI)
	if absf(difference) > 0.000001:
		var look := InputEventMouseMotion.new()
		look.relative = Vector2(-difference / 0.0021, 0.0)
		Input.parse_input_event(look)
		Input.flush_buffered_events()
	game.get("camera_rig").call("follow", actor, true)
	if observer != null: observer.call("mark_setup_reset")
	_check("legal grounded production setup " + id, bool(actor.call("is_grounded")) and actor.global_position.distance_to(spawn_point) < 0.00001)
	setups.append({"case": id, "t": float(game.get("match_clock")) - start_clock, "tick": Engine.get_physics_frames(),
		"position": _v(actor.global_position), "grounded": actor.call("is_grounded"), "yaw": game.get("_yaw"), "method": "production spawn_at + camera follow"})

func _build_events() -> void:
	events = [
		{"t": 0.4, "phase": "walk_off_forward", "keys": [KEY_W]},
		{"t": 1.4, "phase": "walk_off_stop", "keys": []},
		{"t": 2.1, "phase": "walk_off_reverse", "keys": [KEY_S]},
		{"t": 2.55, "phase": "walk_off_reverse_stop", "keys": []},
		{"t": 4.0, "phase": "jump_off_wait", "keys": [], "reset": "jump_off"},
		{"t": 4.4, "phase": "jump_off_forward_jump", "keys": [KEY_W, KEY_SPACE]},
		{"t": 4.7, "phase": "jump_off_forward_air", "keys": [KEY_W]},
		{"t": 5.5, "phase": "jump_off_stop", "keys": []},
		{"t": 6.2, "phase": "jump_off_reverse", "keys": [KEY_S]},
		{"t": 6.65, "phase": "jump_off_reverse_stop", "keys": []},
		{"t": 8.0, "phase": "air_release_wait", "keys": [], "reset": "air_release"},
		{"t": 8.4, "phase": "air_release_short_forward_jump", "keys": [KEY_W, KEY_SPACE]},
		{"t": 8.4 + pulse, "phase": "air_release_no_keys", "keys": []},
		{"t": 9.9, "phase": "air_release_post_land_forward", "keys": [KEY_W]},
		{"t": 10.25, "phase": "air_release_reverse", "keys": [KEY_S]},
		{"t": 10.75, "phase": "air_release_reverse_stop", "keys": []},
	]

func _set_keys(keys: Array) -> void:
	for key: Key in held:
		if not keys.has(key): _key(key, false)
	for key: Key in keys:
		if not held.has(key): _key(key, true)
	held = keys.duplicate()
	Input.flush_buffered_events()

func _key(key: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.keycode = key
	event.physical_keycode = key
	event.pressed = pressed
	Input.parse_input_event(event)

func _sample_physics(observation: Dictionary) -> void:
	if not live or finishing: return
	var elapsed: float = float(observation.match_clock) - start_clock
	observation["t"] = elapsed
	observation["phase"] = phase
	observation["case"] = case_id
	observation["applied_input_event_count"] = event_index
	physics_rows.append(observation)
	latest_physics = observation
	# The observation records the command that was actually consumed. Changes
	# below enter the ordinary controller on the NEXT tick, even at low render FPS.
	while event_index < events.size() and elapsed + 0.000001 >= float(events[event_index].t):
		var event: Dictionary = events[event_index]
		if event.has("reset"): _prepare_case(String(event.reset))
		phase = String(event.phase)
		_set_keys(event.keys)
		input_events.append({"requested_t": event.t, "applied_after_tick_t": elapsed, "phase": phase, "case": case_id,
			"tick": Engine.get_physics_frames(), "render_frame": Engine.get_process_frames(), "keys": event.keys,
			"pre_grounded": observation.grounded, "pre_velocity": observation.velocity, "pre_root": observation.actor_root_transform.position,
			"next_tick_input": true, "reset": event.get("reset", "")})
		event_index += 1
	if elapsed >= finish_time:
		finishing = true
		_finish.call_deferred()

func _sample_render() -> void:
	if not live or finishing or not is_instance_valid(actor): return
	var wall: int = Time.get_ticks_usec()
	var wall_dt: float = float(wall - last_wall) / 1000000.0
	last_wall = wall
	frame_intervals.append(wall_dt)
	var tick: int = Engine.get_physics_frames()
	var velocity: Vector3 = actor.get("velocity")
	var motion: Dictionary = avatar.get("motion_state")
	var feet: Array = []
	for bone_name: String in ["footL", "footR"]:
		feet.append(_v(rig.global_transform * rig.get_bone_global_pose(rig.find_bone(bone_name)).origin))
	var camera: Camera3D = game.get("camera")
	var hips: Vector3 = rig.global_transform * rig.get_bone_global_pose(rig.find_bone("hips")).origin
	render_rows.append({"t": float(game.get("match_clock")) - start_clock, "wall_us": wall, "wall_dt": wall_dt,
		"render_frame": Engine.get_process_frames(), "tick": tick, "physics_ticks_since_last_render": 0 if last_render_tick < 0 else tick - last_render_tick,
		"alpha": Engine.get_physics_interpolation_fraction(), "phase": phase, "case": case_id,
		"setup_epoch": observer.get("setup_epoch"),
		"root": _v(actor.global_position), "shown_root": _v(avatar.global_position), "velocity": _v(velocity), "speed": Vector2(velocity.x, velocity.z).length(),
		"grounded": actor.call("is_grounded"), "land_time": actor.get("land_time"), "land_speed": actor.get("land_speed"),
		"feet": feet, "hips": _v(hips), "hips_screen": _v2(camera.unproject_position(hips)), "camera": _v(camera.global_position),
		"clip": motion.get("clip", ""), "motion_time": motion.get("time", 0.0), "motion_rate": motion.get("rate", 1.0),
		"current_action": avatar.get("current_action"), "presentation_active": avatar.get("presentation_active"),
		"latest_physics_tick": latest_physics.get("tick", -1), "latest_physics_sample": latest_physics.get("sample_id", -1)})
	last_render_tick = tick

func _coverage() -> Dictionary:
	var result: Dictionary = {}
	var total_descending_lands: int = 0
	var release_input_airborne: bool = false
	for event: Dictionary in input_events:
		if event.phase == "air_release_no_keys" and not bool(event.pre_grounded): release_input_airborne = true
	for id: String in ["walk_off", "jump_off", "air_release"]:
		var count: Dictionary = {"physics_samples": 0, "takeoffs": 0, "descending_floor_lands": 0, "active_jump_air_samples": 0,
			"released_air_samples": 0, "zero_input_stationary_lands": 0, "grounded_reverse_command_samples": 0,
			"grounded_reverse_velocity_samples": 0, "grounded_zero_input_stationary_samples": 0, "fullbody_landing_samples": 0, "lands": []}
		for row: Dictionary in physics_rows:
			if row.case != id: continue
			count.physics_samples += 1
			var command: Dictionary = row.actual_command
			var movement: Array = command.move
			var move_length: float = Vector3(float(movement[0]), float(movement[1]), float(movement[2])).length()
			var position: Array = row.actor_root_transform.position
			var velocity: Array = row.velocity
			if row.grounded_edge == "takeoff": count.takeoffs += 1
			if not bool(row.grounded) and bool(command.jump) and float(velocity[1]) > 4.0 and float(position[1]) > spawn_point.y + 0.05: count.active_jump_air_samples += 1
			if id == "air_release" and row.phase == "air_release_no_keys" and not bool(row.grounded) and move_length < 0.001 and not bool(command.jump): count.released_air_samples += 1
			if bool(row.grounded) and float(row.land_time) < 0.7 and bool(row.action_full_body): count.fullbody_landing_samples += 1
			if row.grounded_edge == "land":
				var previous: Array = row.previous_velocity
				var descending: bool = previous.size() == 3 and float(previous[1]) < -0.5
				var genuine: bool = descending and bool(row.source_landed) and float(row.land_time) <= 0.02 and float(row.land_speed) > 3.0
				genuine = genuine and float(position[1]) <= 0.05 and float(position[1]) < spawn_point.y - 2.0
				if genuine: count.descending_floor_lands += 1; total_descending_lands += 1
				var stationary: bool = genuine and move_length < 0.001 and not bool(command.jump) and float(row.speed) <= 0.25
				if stationary: count.zero_input_stationary_lands += 1
				count.lands.append({"t": row.t, "tick": row.tick, "phase": row.phase, "root": position, "speed": row.speed, "land_speed": row.land_speed,
					"previous_velocity": previous, "actual_command": command, "genuine_descending_floor_land": genuine, "stationary_zero_input": stationary,
					"clip": row.clip, "motion_rate": row.motion_rate, "action_active": row.action_active, "action_full_body": row.action_full_body, "footplant": row.footplant})
			if bool(row.grounded) and float(row.land_time) < 3.5:
				var command_z: float = float(movement[2])
				if command_z * forward.z < -0.5: count.grounded_reverse_command_samples += 1
				if float(velocity[2]) * forward.z < -0.15: count.grounded_reverse_velocity_samples += 1
				if move_length < 0.001 and float(row.speed) <= 0.25: count.grounded_zero_input_stationary_samples += 1
		result[id] = count
		_check("real descending platform-to-floor landing " + id, int(count.descending_floor_lands) >= 1)
		_check("post-land reverse reaches controller and physical motion " + id, int(count.grounded_reverse_command_samples) > 0 and int(count.grounded_reverse_velocity_samples) > 0)
		_check("post-land idle/stop physically observed " + id, int(count.grounded_zero_input_stationary_samples) > 5)
	_check("at least two real descending landings", total_descending_lands >= 2)
	_check("W+Space actually jumps", int(result.jump_off.active_jump_air_samples) > 0)
	_check("W released while actually airborne", release_input_airborne and int(result.air_release.released_air_samples) >= 3)
	_check("air release ends in zero-input stationary floor landing", int(result.air_release.zero_input_stationary_lands) >= 1)
	result["descending_floor_lands"] = total_descending_lands
	result["release_input_applied_while_airborne"] = release_input_airborne
	return result

func _motion_script() -> String:
	if not is_instance_valid(avatar): return ""
	var motion: RefCounted = avatar.get("_motion")
	return motion.get_script().resource_path if motion != null else ""

func _watchdog() -> void:
	if finishing: return
	_check("complete timeline before watchdog", false)
	finishing = true
	_finish.call_deferred()

func _finish() -> void:
	finishing = true
	live = false
	_set_keys([])
	if observer != null: observer.set("enabled", false)
	if RenderingServer.frame_post_draw.is_connected(_sample_render): RenderingServer.frame_post_draw.disconnect(_sample_render)
	_check("all real-input events consumed", event_index == events.size() and events.size() == 16)
	_check("three identical legal spawn setups", setups.size() == 3)
	_check("post-game physics records", physics_rows.size() > 500)
	_check("render records", render_rows.size() > 60)
	if is_instance_valid(actor): _check("player remains alive", bool(actor.get("alive")))
	if is_instance_valid(game): _check("eight actors remain", game.get("actors").size() == 8)
	var coverage: Dictionary = _coverage()
	var source_after: Dictionary = _hash_sources()
	if not source_before.is_empty(): _check("source/algorithm/old-tool snapshots unchanged during run", source_before == source_after)
	var pacing: Dictionary = _stats(frame_intervals)
	var findings: Array[String] = []
	if float(pacing.get("wall_fps", 0.0)) < float(fps) * 0.9: findings.append("Measured render rate is below requested FPS; retain actual intervals, do not call this a 144-FPS result.")
	var path: String = ProjectSettings.globalize_path(output)
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	_check("JSON output writable", file != null)
	var report: Dictionary = {"contract": "landing-real-chain-v4", "landing_filter_schema_required": "pelvis-rate-v4" if FileAccess.file_exists("res://scripts/animation/ink_landing_response.gd") else "unavailable_in_source",
		"diagnostic_only": true, "accepted_for_production": false,
		"scene": game.scene_file_path if is_instance_valid(game) else "unavailable", "current_scene_is_real_app": current_scene == game and game != null,
		"engine": Engine.get_version_info(), "renderer": RenderingServer.get_current_rendering_method(), "platform": OS.get_name(),
		"fps_limit": fps, "quality": quality, "physics_hz": Engine.physics_ticks_per_second, "time_scale": Engine.time_scale,
		"input_scheduler": "post-game physics callback sends real Input key events for next ordinary controller tick",
		"pointer_policy": "fixed look; app unhandled pointer handler disabled; real key actions remain enabled",
		"pointer_handler_enabled": game.is_processing_unhandled_input(),
		"commands": OS.get_cmdline_args(), "user_args": OS.get_cmdline_user_args(), "motion_script": _motion_script(),
		"native_active": avatar.get("_native_motion_active") if is_instance_valid(avatar) else false,
		"presentation_mode": avatar.get("presentation_mode") if is_instance_valid(avatar) else "unavailable",
		"setup_geometry": setup_geometry, "setups": setups, "pulse_s": pulse, "timeline_duration_s": finish_time,
		"physics_sample_count": physics_rows.size(), "render_sample_count": render_rows.size(), "render_wall_intervals": pacing,
		"real_input_events": input_events, "coverage": coverage, "quality_findings": findings, "source_before": source_before, "source_after": source_after,
		"checks": checks, "failure_count": failures.size(), "failures": failures, "physics_samples": physics_rows, "samples": render_rows,
		"limitations": ["Three identical prepared platform positions use production spawn_at and camera follow; no movement/tick/pose/land event is injected.",
			"Eight production actors remain; seven bots use the existing quiet command provider.", "Detailed observers add CPU cost. Actual render pacing is reported, not treated as a production benchmark.",
			"Coverage proves actual source physics landings. Animation/contact fields diagnose sliding; this baseline makes no quality-fix claim.", "No screenshot/image readback is performed."]}
	if file:
		file.store_string(JSON.stringify(report))
		file.flush()
		if file.get_error() != OK: _check("JSON write/flush succeeded", false)
		file.close()
	var brief: Dictionary = {"checks": checks, "failure_count": failures.size(), "failures": failures, "coverage": coverage,
		"render_sample_count": render_rows.size(), "physics_sample_count": physics_rows.size(), "actual_render_pacing": pacing, "quality_findings": findings, "output": output}
	print("LANDING_REAL_REPORT ", JSON.stringify(brief))
	if observer != null: observer.queue_free(); observer = null
	if is_instance_valid(game): game.queue_free()
	game = null
	actor = null
	avatar = null
	rig = null
	await process_frame
	await process_frame
	quit(0 if failures.is_empty() else 1)

func _stats(values: Array[float]) -> Dictionary:
	if values.is_empty(): return {}
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in sorted: total += value
	return {"count": sorted.size(), "wall_fps": float(sorted.size()) / maxf(total, 0.000001), "total_s": total,
		"median_s": sorted[sorted.size() >> 1], "p95_s": sorted[mini(sorted.size() - 1, int(sorted.size() * 0.95))], "max_s": sorted[-1]}

func _v(value: Vector3) -> Array: return [value.x, value.y, value.z]
func _v2(value: Vector2) -> Array: return [value.x, value.y]
