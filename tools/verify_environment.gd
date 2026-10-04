extends SceneTree
const NativeEnvironment = preload("res://scripts/world/ink_environment.gd")
const Stage = preload("res://scripts/world/ink_stage.gd")
var failures := 0
var checks: Array[Dictionary] = []

func _initialize() -> void:
	create_timer(30.0).timeout.connect(func():push_error("ENVIRONMENT_CONTRACT timeout");quit(1))
	call_deferred("_run")

func _check(name: String, passed: bool, detail: Variant = null) -> void:
	checks.append({"name":name,"passed":passed,"detail":detail})
	if not passed:
		failures += 1
		push_error("ENVIRONMENT_CONTRACT FAILED " + name)

func _run() -> void:
	for id in ["tidewater","kelpline","halyard","cargo"]:
		var stage := Stage.new()
		root.add_child(stage)
		var world := WorldEnvironment.new()
		world.environment = Environment.new()
		stage.add_child(world)
		var camera := Camera3D.new()
		camera.position = Vector3(0,6,18)
		stage.add_child(camera)
		camera.current = true
		var environment := NativeEnvironment.new()
		environment.reflections_enabled = false
		stage.add_child(environment)
		environment.configure(id,"day",stage)
		environment.set_process(false)
		_check(id+"_source_mesh_count", environment.get("_nodes").size()==environment.data.meshes.size(),environment.get("_nodes").size())
		_check(id+"_original_polar_sea", (environment.get("_sea") as MeshInstance3D).mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX].size()>8000)
		_check(id+"_source_wave_trilinear_mips", (environment.get("_textures").uWaveTex as Texture2D).get_image().has_mipmaps())
		var gulls := environment.get("_nodes").get("Gulls") as MultiMeshInstance3D
		_check(id+"_gull_per_instance_phase", gulls != null and gulls.multimesh.use_custom_data and gulls.multimesh.get_instance_custom_data(0).r != gulls.multimesh.get_instance_custom_data(1).r)
		for period in ["day","dusk"]:
			environment.set_time_of_day(period)
			_check(id+"_"+period+"_source_cloud_hdr", (environment.get("_theme_cache")[period].cloud as Texture2D).get_image().get_format()==Image.FORMAT_RGBAH)
		for t in [0.0,0.5,3.0,19.0]:
			environment.clock=t
			environment._animate_motion()
			for node in environment.get("_nodes").values():
				_check(id+"_"+str(t)+"_"+node.name+"_finite",node.global_transform.origin.is_finite() and node.global_basis.x.is_finite())
			_check(id+"_water_height_finite_"+str(t),is_finite(environment.water_height_at(0,0,t)))
		stage.queue_free()
		await process_frame
	var report := {"suite":"source_environment","passed":failures==0,"failures":failures,"checks":checks}
	var file := FileAccess.open("res://shots/environment_contract.json",FileAccess.WRITE)
	if file:file.store_string(JSON.stringify(report,"\t"))
	print("ENVIRONMENT_CONTRACT "+JSON.stringify({"checks":checks.size(),"failures":failures,"passed":failures==0}))
	quit(0 if failures==0 else 1)
