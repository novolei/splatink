extends SceneTree

const Fx=preload("res://scripts/fx/ink_fx.gd")
const Colors=preload("res://scripts/fx/ink_fx_colors.gd")
const Actor=preload("res://scripts/game/ink_actor.gd")
const Hazard=preload("res://scripts/fx/boss_hazard_visuals.gd")

class NetworkStub:
	extends Node
	var active:bool=false
class Arena:
	extends Node3D
	var team_colors:Array=[]
	var settings:Dictionary={"quality":"high","cameraShake":1.0}
	var state:String="playing"
	var time_left:float=180.0
	var camera:Camera3D
	var network:Node
	var local_player
	var projectiles=null
	var stage=null
	var actors:Array=[]
	var paint:Array=[]
	var floor_hit:bool=false
	func cast(from:Vector3,to:Vector3,_exclude:Array=[],_mask:int=1)->Dictionary:
		if floor_hit and from.y>=0 and to.y<0:return {"position":from.lerp(to,from.y/(from.y-to.y)),"normal":Vector3.UP}
		return {}
	func paint_splat(pos:Vector3,normal:Vector3,radius:float,team:int,extra:Dictionary={})->float:
		paint.append({"pos":pos,"normal":normal,"radius":radius,"team":team,"extra":extra});return 0.0
	func notify_event(_kind:String,_data:Dictionary)->void:pass

var checks:int=0
var packet_checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run_contract")
func expect(condition:bool,label:String)->void:
	checks+=1
	if not condition:
		if failures.size()<20:push_error(label)
		failures.append(label)
func near(actual:float,wanted:float,label:String,tolerance:float=.000005)->void:
	expect(absf(actual-wanted)<=tolerance,"%s got %.9f expected %.9f"%[label,actual,wanted])
func rgb(color:Color,wanted:Array,label:String)->void:
	near(color.r,wanted[0],label+" red");near(color.g,wanted[1],label+" green");near(color.b,wanted[2],label+" blue")
func matches(color:Color,wanted:Array)->bool:
	return absf(color.r-float(wanted[0]))<.000005 and absf(color.g-float(wanted[1]))<.000005 and absf(color.b-float(wanted[2]))<.000005
func palette(hex:Array)->Array:return [Color(str(hex[0])),Color(str(hex[1]))]
func submit(fx,camera:Camera3D)->void:
	fx.drops.update(.001,camera);fx.puffs.update(.001,camera);fx.glows.update(.001,camera)
	fx.rings.update(.001);fx.sheets.update(.001);fx.beams.update(.001)

func run_contract()->void:
	var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/fx_colors.json"))
	var arena:=Arena.new();root.add_child(arena)
	arena.team_colors=palette(data.cases[0].hex)
	arena.network=NetworkStub.new();arena.add_child(arena.network)
	arena.camera=Camera3D.new();arena.add_child(arena.camera);arena.camera.position=Vector3(0,5,-8)
	arena.camera.look_at(Vector3(0,1,0));arena.camera.make_current()
	var actor:=Actor.new();arena.add_child(actor);actor.match_node=arena;actor.is_local=true;actor.reset_weapon()
	arena.local_player=actor;arena.actors=[actor]
	var fx:=Fx.new();arena.add_child(fx);fx.configure(arena);fx._camera=arena.camera
	for pool in [fx.drops,fx.puffs,fx.glows,fx.rings,fx.sheets,fx.beams,fx.rounds]:pool.capture_render_packets=true
	await process_frame
	for key in data.constants:
		rgb(Colors.from_srgb(Color(str(data.constants[key].hex))),data.constants[key].linear,"Source hex constant "+key)
	rgb(Fx.DUST,data.constants.DUST.linear,"Dry footstep dust exact source color")
	rgb(Fx.FOAM,data.constants.FOAM.linear,"Sea foam exact source color")
	rgb(Fx.WATER,data.constants.WATER.linear,"Sea water exact source color")
	for row in data.cases:
		arena.team_colors=palette(row.hex);actor.team_id=int(row.team)
		var color:Color=fx._color(actor)
		rgb(color,row.linear,"Palette "+row.palette+" linear actor color")
		rgb(fx._color(null,actor.team_id),row.linear,"Palette "+row.palette+" linear team color")
		for name in row.recipes:
			fx.clear();actor.weapon_id="charger";actor.charge=.7
			var p:=Vector3(0,1,0)
			match name:
				"mist":fx._mist(p,Vector3.BACK,color)
				"form":fx._form_pop(p,color,true,false)
				"explosion":fx.explosion(p,color,3.0)
				"spawn":fx._spawn_flash(p,color)
				"storm":fx._storm_start(p,color,3.4)
				"shooter","blaster","charger":fx.muzzle(p,Vector3.BACK,color,name)
				"bubbles":fx._bubbles(p,color,3)
				"charge":fx._charge_effects(actor,p,color,.04,{})
				"water":fx._water_splash(p)
				"dust":fx._footstep(p,color,0,Vector3.BACK,5.0)
				"ghost":fx.on_event("splatted",{"victim":actor,"actor":actor})
				"trail":fx._shot_trail(p,Vector3.BACK,color,false)
				"trailBig":fx._shot_trail(p,Vector3.BACK,color,true)
				"sizzle":fx._enemy_ink_sizzle(p,color)
			submit(fx,arena.camera)
			var submitted:int=0
			for path in ["drops","puffs","glows","rings","sheets","beams"]:
				# Ghost is emitted together with splat flash; this fixture isolates its puff.
				if name=="ghost" and path!="puffs":continue
				var pool=fx.get(path)
				for packet:Dictionary in pool.render_packets:
					var accepted:bool=false
					for original in row.recipes[name]:
						if original.path==path and matches(packet.color,original.color):accepted=true;break
					expect(accepted,"%s team%d %s %s actual GPU COLOR matches original recipe"%[row.palette,row.team,name,path])
					packet_checks+=1
					submitted+=1
			expect(submitted>0,"Recipe "+name+" submits actual render colors")
		# This is the exact dictionary Root InkGrade writes to its raw HDR uniform buffer.
		fx.screen.reset();fx.screen._state="playing"
		# Recipes reuse one native pool; original captures instantiate a fresh ScreenFX.
		# Space independent landing events beyond the original .3 s duplicate guard.
		fx.screen.time+=1.0
		fx.screen.on_event("respawn",{"actor":actor});fx.screen._land(actor);fx.screen.update(0.0)
		for key in row.screen:
			var value=fx.screen.uniforms[key]
			var c:Color=Color(value.x,value.y,value.z)
			rgb(c,row.screen[key],"HDR screen "+row.palette+" "+key)
		for round in row.projectiles:
			var bullet:Dictionary={"kind":round.kind,"team":actor.team_id,"velocity":Vector3(0,0,20),"age":round.age,"life":round.remaining,"pos":Vector3(0,1,5),"start":Vector3(0,1,0),"vis":.12,"tail0":.8,"tail_k":1.3,"wob":.04,"seed":.5,"wob_f":20,"sats":3}
			fx.rounds.render_projectiles([bullet],arena.team_colors)
			expect(fx.rounds.render_packets.size()==round.colors.size(),"Projectile source head/satellite submission count")
			for i in mini(fx.rounds.render_packets.size(),round.colors.size()):rgb(fx.rounds.render_packets[i].color,round.colors[i],"Projectile "+round.kind+" GPU color")
		fx.boss_pool.set_ink(color)
		var standard:Color=fx.boss_pool._material.albedo_color
		rgb(standard.srgb_to_linear(),row.linear,"StandardMaterial decodes palette exactly once")
		var hazard:ShaderMaterial=Hazard.make_material("fan",arena.team_colors[actor.team_id])
		var shader_input:Color=hazard.get_shader_parameter("uColor")
		expect(shader_input.is_equal_approx(arena.team_colors[actor.team_id]),"source_color hazard uniform stays sRGB")
	for row in data.identity:
		arena.team_colors=palette(row.hex)
		var color:=Color(row.color[0],row.color[1],row.color[2])
		expect(Colors.team_of(color,arena.team_colors)==int(row.team),"Source linear L1 turf identity "+row.name)
		fx.clear();arena.paint.clear();arena.floor_hit=true;fx.drops.drop(Vector3(0,.05,0),Vector3.DOWN*3,color,.08,1,1,1,1,0,true,true)
		fx.drops.update(.05,arena.camera)
		expect(arena.paint.size()==(1 if int(row.team)>=0 else 0),"Only original team-color drops can affect offline turf "+row.name)
		if not arena.paint.is_empty():
			expect(arena.paint[0].team==int(row.team),"Paint keeps source first-match team identity")
			near(arena.paint[0].radius,.192,"Source painter radius is size*2.4")
			near(arena.paint[0].pos.y,.05,"Source painter normal offset")
			arena.network.active=true;fx.clear();arena.paint.clear()
			fx.drops.drop(Vector3(0,.05,0),Vector3.DOWN*3,color,.08,1,1,1,1,0,true,true);fx.drops.update(.05,arena.camera)
			expect(arena.paint.is_empty(),"Online source color droplets never modify turf")
			arena.network.active=false
		arena.floor_hit=false
	for row in data.lighting:
		fx.configure_lighting(row.theme)
		for key in ["sun_color","sky_color","ground_color"]:
			rgb(fx.lighting[key],row.expected[key],"Original environment FX light "+row.name+" "+key)
			var uploaded:Color=fx.drops._shader.get_shader_parameter(key)
			rgb(uploaded.srgb_to_linear(),row.expected[key],"Drop shader source_color decodes once "+row.name+" "+key)
			if key!="ground_color":
				var sheet_material:ShaderMaterial=fx.sheets.material_override
				var sheet_upload:Color=sheet_material.get_shader_parameter(key)
				rgb(sheet_upload.srgb_to_linear(),row.expected[key],"Sheet shader source_color decodes once "+row.name+" "+key)
		var sun:Vector3=fx.drops._shader.get_shader_parameter("sun_direction")
		for axis in 3:near(sun[axis],row.expected.sun_direction[axis],"Original FX source sun direction "+row.name)
	# A palette swap while a droplet flies must not reuse a stale numeric team ID.
	fx.clear();arena.paint.clear();arena.team_colors=palette(data.cases[0].hex)
	fx.drops.drop(Vector3(0,.05,0),Vector3.DOWN*3,fx._color(null,0),.08,1,1,1,1,0,true,true)
	arena.team_colors=palette(data.cases[2].hex);arena.floor_hit=true;fx.drops.update(.05,arena.camera)
	expect(arena.paint.is_empty(),"In-flight palette change uses current source color identity")
	# Encoded lens RGB contains channel weights, not colors. No gamma conversion there.
	var lens_shader:String=FileAccess.get_file_as_string("res://assets/shaders/fx_lens.gdshader")
	expect(not lens_shader.contains("source_color"),"Lens channel data has no color-space decoding")
	var drop_shader:String=FileAccess.get_file_as_string("res://assets/shaders/fx_ink_drop.gdshader")
	expect(drop_shader.contains("sky_color : source_color") and drop_shader.contains("ground_color : source_color"),"Lighting uniforms retain Godot decoding hints")
	var terrain_shader:String=FileAccess.get_file_as_string("res://assets/shaders/ink_surface.gdshader")
	if not terrain_shader.is_empty():expect(terrain_shader.contains("team_a : source_color"),"Surface painter palette uniform retains source_color decoding")
	print("FX color source contract: %d checks, %d failures"%[checks,failures.size()])
	print("Color checks: %d fixed assertions, %d stochastic submitted-packet assertions"%[checks-packet_checks,packet_checks])
	quit(0 if failures.is_empty() else 1)
