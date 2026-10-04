extends SceneTree
## Root-only serialized GPU capture: actual lid geometry, mouth opening and gaze.
const Lobby = preload("res://scripts/world/ink_lobby.gd")
var failures := 0
func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("FACE_VISUAL watchdog"); quit(1))
	call_deferred("_run")
func _run() -> void:
	root.size = Vector2i(960,720)
	RenderingServer.set_default_clear_color(Color(0.17,0.20,0.26))
	var lobby := Lobby.new()
	root.add_child(lobby)
	lobby.configure()
	lobby.show_page("locker")
	lobby.set_style({"hair":1,"hat":0,"brows":0,"skin":0,"outfit":0,"eyes":0},Color("ff6a10"),"shooter")
	for i in 12:
		lobby.update(1.0/60.0)
		await process_frame
	var avatar := lobby.preview
	var rig := avatar._skeleton
	var head := avatar.get_head_position()
	lobby.camera.position = head+Vector3(0.0,0.01,1.1)
	lobby.camera.look_at(head,Vector3.UP)
	lobby.camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	lobby.camera.fov = 31.0
	var reference: Dictionary = {"size":[960,720],"style":avatar.appearance,"team":"#"+avatar.team_color.to_html(false),"poses":{}}
	for pose in ["neutral","blink","open_mouth","gaze"]:
		avatar.animate(1.0/60.0,{"form":"kid","grounded":true})
		if pose=="blink":
			for eye in ["eyeL","eyeR"]: rig.set_bone_pose_scale(rig.find_bone(eye),Vector3(1.0558,0.07,1.0))
		elif pose=="open_mouth":
			avatar._face_nodes[0].position = Vector3(0.75,1.0,0.85)
			rig.set_bone_pose_rotation(rig.find_bone("jaw"),Quaternion(Vector3.RIGHT,0.85*0.35))
		elif pose=="gaze":
			avatar._face_nodes[3].position = Vector3(0.20,0.1,0.0)
			avatar._face_nodes[4].position = Vector3(0.12,0.04,0.12)
			avatar._face_nodes[5].position.x = 0.04
		avatar._update_face_materials()
		var record: Dictionary = {"root":_transform(avatar._kid.global_transform),"camera":_transform(lobby.camera.global_transform),"fov":lobby.camera.fov,"near":lobby.camera.near,"far":lobby.camera.far,"bones":{},"uniforms":{},"lights":[],"hemi":avatar._lighting_theme}
		for index in rig.get_bone_count():
			record.bones[String(rig.get_bone_name(index))] = _transform(rig.get_bone_pose(index))
		if avatar._hair_rig != null:
			for index in avatar._hair_rig.get_bone_count():
				var name := String(avatar._hair_rig.get_bone_name(index))
				if name.begins_with("hair"): record.bones[name] = _transform(avatar._hair_rig.get_bone_pose(index))
		var material := (avatar.find_child("Skin",true,false) as MeshInstance3D).material_override as ShaderMaterial
		var eye_material := (avatar.find_child("Eyes",true,false) as MeshInstance3D).material_override as ShaderMaterial
		var hair_material := (avatar.find_child("Hair",true,false) as MeshInstance3D).material_override as ShaderMaterial
		for name in ["uTeam","uHurt","uHurtSeed","uGlow","uFlash","uIwRim","uIwRimL","uIwFill","uMouth","uMouth2","uLook","uGaze","uLid","uPupil","uIris","uIris2","uFreckle","uSkinLum"]:
			# Eye-only uniforms are not declared on Skin. Capture their actual
			# active material rather than silently using the web's default gaze.
			var owner: ShaderMaterial = eye_material if name in ["uLook","uGaze","uPupil","uIris","uIris2"] else hair_material if name=="uGlow" else material
			var value: Variant = owner.get_shader_parameter(name)
			if value is Vector4: record.uniforms[name] = [value.x,value.y,value.z,value.w]
			elif value is Vector3: record.uniforms[name] = [value.x,value.y,value.z]
			elif value is Vector2: record.uniforms[name] = [value.x,value.y]
			elif value is float: record.uniforms[name] = value
		for name in ["key","rimA","rimB","fill"]:
			var light := lobby._lights["studio_"+name] as DirectionalLight3D
			var color := light.light_color.srgb_to_linear()
			record.lights.append({"name":name,"transform":_transform(light.global_transform),"color":[color.r,color.g,color.b],"intensity":light.light_energy*PI,"shadows":light.shadow_enabled})
		reference.poses[pose] = record
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		var path: String = "res://shots/face_"+pose+".png"
		var error := image.save_png(path)
		if error!=OK:
			failures += 1
			push_error("FACE_VISUAL write "+path+" "+str(error))
	var fixture := FileAccess.open("res://shots/face_reference_pose.json",FileAccess.WRITE)
	fixture.store_string(JSON.stringify(reference))
	fixture.close()
	print("FACE_VISUAL ",4," captures; failures=",failures)
	quit(1 if failures else 0)

func _transform(value: Transform3D) -> Dictionary:
	var q := value.basis.orthonormalized().get_rotation_quaternion()
	var s := value.basis.get_scale()
	return {"p":[value.origin.x,value.origin.y,value.origin.z],"q":[q.x,q.y,q.z,q.w],"s":[s.x,s.y,s.z]}
