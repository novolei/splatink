extends SceneTree
const Lobby = preload("res://scripts/world/ink_lobby.gd")
const Avatar = preload("res://scripts/characters/ink_avatar.gd")
var failures := 0
var checks := 0
func _initialize() -> void:
	create_timer(30.0).timeout.connect(func(): push_error("LOBBY_CONTRACT watchdog"); quit(1))
	call_deferred("_run")
func _check(label: String, value: bool) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error("LOBBY_CONTRACT: "+label)
func _run() -> void:
	var world := Node3D.new()
	root.add_child(world)
	var lobby := Lobby.new()
	world.add_child(lobby)
	lobby.quality = "low"
	lobby.configure()
	await process_frame
	_check("28 source meshes",lobby.data.meshes.size()==28)
	_check("19 source material hooks",lobby._materials.size()==19)
	_check("six native decal atlases",lobby.data.textures.size()==6)
	_check("eight source arrival paths",lobby.data.lanes.size()==8)
	_check("Showcase has no world bloom",lobby.grade==null or not lobby.grade.bloom_enabled)
	for info:Dictionary in lobby.data.lights.alley:
		var lamp:=lobby._lights.get("alley_"+String(info.name)) as Light3D
		if lamp is SpotLight3D:_check("source spot decay "+String(info.name),is_equal_approx((lamp as SpotLight3D).spot_attenuation,float(info.decay)))
		elif lamp is OmniLight3D:_check("source point decay "+String(info.name),is_equal_approx((lamp as OmniLight3D).omni_attenuation,float(info.decay)))
	for i in 8:
		_check("arrival path %d"%i,lobby.arrival_path(i).size()>4)
	for mode in ["loadout","locker","hub","lobby","results"]:
		lobby.show_page(mode)
		lobby.set_players([{"style":{"hair":2,"outfit":3,"eyes":5},"weapon":"dualies"},{"weapon":"roller"}])
		for i in 12: lobby.update(1.0/30.0)
		_check("camera finite "+mode,lobby.camera.position.is_finite())
		_check("two dressed players "+mode,lobby.players.size()==2)
		await process_frame
	lobby.show_page("locker")
	var loadout: Dictionary = lobby.data.studio_moods.loadout
	_check("source loadout key energy",is_equal_approx(lobby._lights.studio_key.light_energy,float(loadout.key)/PI))
	_check("source preview hemisphere",lobby.preview._lighting_theme.type=="HemisphereLight" and is_equal_approx(float(lobby.preview._lighting_theme.intensity),float(loadout.hemi)))
	lobby.show_page("results")
	lobby.set_players([{"weapon":"shooter"}],false)
	_check("source losing key",is_equal_approx(lobby._lights.studio_key.light_energy,float(lobby.data.studio_moods.lose.key)/PI))
	_check("source losing player hemisphere",is_equal_approx(float(lobby.players[0]._lighting_theme.intensity),float(lobby.data.studio_moods.lose.hemi)))
	lobby.set_players([{"weapon":"shooter"}],true)
	_check("source winning key",is_equal_approx(lobby._lights.studio_key.light_energy,float(lobby.data.studio_moods.win.key)/PI))
	lobby.show_page("hub")
	_check("source alley preview hemisphere",is_equal_approx(float(lobby.preview._lighting_theme.intensity),0.6))
	lobby.show_page("locker")
	lobby.set_ui_rect(Rect2(500,0,700,720))
	lobby.begin_drag(800)
	lobby.drag_by(35,0.02)
	lobby.end_drag()
	_check("source pixel drag rotation",is_equal_approx(lobby.spin,35*0.011))
	for cause in ["hair","eyes","skin","outfit","random"]:
		lobby.set_style({"hair":3,"hat":2,"outfit":6,"eyes":7},Color("18d48c"),"slosher",cause)
		for i in 60: lobby.update(1.0/30.0)
		_check("style swap "+cause,lobby.preview.appearance.hair==3 and lobby.preview.appearance.outfit==6)
		_check("finite elastic pose "+cause,lobby.preview.position.is_finite() and lobby.preview.scale.is_finite())
	lobby.show_page("hub")
	for i in 180: lobby.update(1.0/30.0)
	_check("source ripple system",lobby._ripple_index>0)
	_check("moth moved",(lobby._nodes["lobbySet:moth"] as Node3D).position.is_finite())
	var body := Avatar._find_type(lobby.preview,"AnimationPlayer") as AnimationPlayer
	_check("source lobby pose clip",body.has_animation(lobby.preview._clip("lobby_pose")))
	print("LOBBY_CONTRACT ",checks," checks; ",failures," failures")
	quit(1 if failures else 0)
