class_name InkStage
extends Node3D

const MeshLoader = preload("res://scripts/world/source_mesh.gd")
var layout: Dictionary
var bounds: Dictionary
var faces: Array = []
var blocks: Array = []
var stage_id := "tidewater"
var team_colors: Array = [Color("ff3f9e"),Color("18d48c")]
var grid := PackedByteArray()
var dead := PackedByteArray()
var counts := [0,0]
var turf_total := 1
var turf_area := 1.0
var atlas_size := 2048
var quality: String="medium"
var lighting_theme:Dictionary={}
var source_radiance:Cubemap
var source_pmrem:Texture2D
var _paint_layout: Dictionary={}
var _paint_uv: Dictionary={}
var paint_image: Image
var paint_texture: Texture2D
var _gpu: InkPaintGPU
var material: ShaderMaterial
var grate_material: ShaderMaterial
var clock := 0.0
var _upload_time := 0.0
var _dirty := false
var _face_hash: Dictionary = {}
var _growing: Array = []
var _ripples := PackedVector4Array()
var _ripple_params:=PackedVector4Array()
var _wake:=preload("res://scripts/world/ink_swim_wake.gd").new()
var _ripple_cursor := 0
var _minimap: Image
var _minimap_texture: ImageTexture
var _map_acc := 0.0
var _map_dirty := true
var external_minimap:=false
var _decor_materials: Array[ShaderMaterial] = []
var _source_materials:Array[Material]=[]
var environment_detail: InkEnvironment
var grade: InkGrade
var actor_nav:InkActorNav
var level_queries:InkLevelQueries
static var _library_cache: Dictionary = {}

func build(id: String, time_of_day: String = "day", colors: Array = [],quality_preset: String="medium") -> void:
	stage_id=id
	quality=quality_preset
	if not colors.is_empty(): team_colors=colors
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/"+id+".json"))
	layout=data.layout;bounds=layout.bounds;faces=data.faces;blocks=data.blocks
	if quality in ["high","ultra"] and FileAccess.file_exists("res://data/%s_paint_high.json"%id):
		_paint_layout=JSON.parse_string(FileAccess.get_file_as_string("res://data/%s_paint_high.json"%id))
		var paint_file:=FileAccess.open("res://assets/world/%s_paint_high.bin"%id,FileAccess.READ)
		for name in _paint_layout.meshes:
			var record:Dictionary=_paint_layout.meshes[name];paint_file.seek(int(record.offset));_paint_uv[name]=paint_file.get_buffer(int(record.length)*4).to_float32_array()
		paint_file.close();data.atlas_size=_paint_layout.size;data.ppm=_paint_layout.ppm
		for i in faces.size():
			if _paint_layout.faces[i]!=null:faces[i].atlas=_paint_layout.faces[i]
	atlas_size=int(data.atlas_size);turf_total=int(data.turf_total);turf_area=float(data.turf_area)
	grid.resize(int(data.grid_length));grid.fill(0)
	var source := FileAccess.open("res://assets/world/"+id+".bin",FileAccess.READ)
	source.seek(int(data.dead.offset));dead=source.get_buffer(int(data.dead.length))
	paint_image=Image.create(atlas_size,atlas_size,false,Image.FORMAT_RGBA8)
	paint_image.fill(Color(0,0,0,0));paint_texture=ImageTexture.create_from_image(paint_image)
	if DisplayServer.get_name()!="headless" and RenderingServer.get_rendering_device()!=null:
		_gpu=InkPaintGPU.new();_gpu.initialize(atlas_size);paint_texture=_gpu.texture
	_ripples.resize(24)
	_ripple_params.resize(24)
	for i in 24: _ripples[i]=Vector4(0,-999,0,-99);_ripple_params[i]=Vector4(0,.2,1,.01)
	_create_materials(data)
	for record in data.meshes: _add_mesh(source,record)
	source.close()
	for block in blocks:
		block.center=vec3(block.center);block.half=vec3(block.half)
		block.axes=block.axes.map(func(a):return vec3(a))
		if not block.solid: continue
		var body := StaticBody3D.new()
		body.collision_layer=4 if block.grate else 1;body.collision_mask=0
		body.transform=Transform3D(Basis(block.axes[0],block.axes[1],block.axes[2]),block.center)
		body.set_meta("block",int(block.id));body.set_meta("grate",block.grate)
		var shape := CollisionShape3D.new();var box := BoxShape3D.new();box.size=block.half*2.0
		shape.shape=box;body.add_child(shape);add_child(body)
	for f in faces:
		f.n=vec3(f.n);f.u=vec3(f.u);f.v=vec3(f.v);f.origin=vec3(f.origin)
		if not f.paintable: continue
		var center: Vector3=f.origin+f.u*f.su*.5+f.v*f.sv*.5
		var extent: Vector3=f.u.abs()*f.su*.5+f.v.abs()*f.sv*.5+Vector3.ONE*8
		for x in range(floori((center.x-extent.x)/8),ceili((center.x+extent.x)/8)+1):
			for z in range(floori((center.z-extent.z)/8),ceili((center.z+extent.z)/8)+1):
				var key:=Vector2i(x,z)
				if not _face_hash.has(key):_face_hash[key]=[]
				_face_hash[key].append(int(f.id))
	level_queries=preload("res://scripts/game/ink_level_queries.gd").new()
	level_queries.configure(self)
	_build_environment(time_of_day)
	actor_nav=preload("res://scripts/game/ink_actor_nav.gd").new()
	if not actor_nav.configure(stage_id):push_error("Original actor navigation failed to load for "+stage_id)
	_minimap=Image.create(256,256,false,Image.FORMAT_RGBA8);_minimap.fill(Color("dbd4c4"))
	_minimap_texture=ImageTexture.create_from_image(_minimap)

static func vec3(a: Array) -> Vector3: return Vector3(a[0],a[1],a[2])

static func load_texture_library(kind:String,layer_count:int=-1)->Texture2DArray:
	if _library_cache.has(kind):return _library_cache[kind]
	if layer_count<0:
		var library:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/texture_library.json"))
		layer_count=library.names.size()
	var images:Array[Image]=[]
	for layer in layer_count:
		var texture:Texture2D=load("res://assets/textures/library/%s_%02d.png"%[kind,layer])
		var image:=texture.get_image()
		if image.is_compressed():image.decompress()
		image.convert(Image.FORMAT_RGBA8);image.clear_mipmaps()
		var mip_path:String="res://assets/textures/library/%s_%02d.mips.bin"%[kind,layer]
		if FileAccess.file_exists(mip_path):
			# These bytes came from the original SRGB8/linear GPU textures. CPU
			# filtering of encoded PNG RGB would darken small distant patterns.
			var pixels:=image.get_data();pixels.append_array(FileAccess.get_file_as_bytes(mip_path))
			image=Image.create_from_data(image.get_width(),image.get_height(),true,Image.FORMAT_RGBA8,pixels)
		else:image.generate_mipmaps()
		images.append(image)
	var result:=Texture2DArray.new();result.create_from_images(images)
	_library_cache[kind]=result
	return result

func _create_materials(data: Dictionary) -> void:
	var lib: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/texture_library.json"))
	material=ShaderMaterial.new();material.shader=load("res://assets/shaders/ink_surface.gdshader")
	for kind in ["albedo","normal","orm"]:
		load_texture_library(kind,lib.names.size())
		material.set_shader_parameter("t_"+kind,_library_cache[kind])
	for key in ["slots","tints","stairs"]:
		var values:=PackedVector4Array();values.resize(64)
		for i in lib[key].size():var v:Array=lib[key][i];values[i]=Vector4(v[0],v[1],v[2],v[3])
		material.set_shader_parameter(key,values)
	material.set_shader_parameter("paint_atlas",paint_texture)
	material.set_shader_parameter("paint_ppm",data.ppm);material.set_shader_parameter("atlas_size",float(atlas_size))
	material.set_shader_parameter("ao_atlas",load("res://assets/textures/"+stage_id+"_ao.png"))
	material.set_shader_parameter("mural_atlas",load("res://assets/textures/"+stage_id+"_murals.png"))
	material.set_shader_parameter("has_ao",data.source_lightmap_valid)
	var rects:=PackedVector4Array();rects.resize(12)
	var places:=PackedVector4Array();places.resize(12)
	var fx:=PackedVector2Array();fx.resize(12)
	for i in mini(data.murals.size(),12):
		if data.murals[i]==null:continue
		var mr:Array=data.murals[i].rect;var mp:Array=data.murals[i].place;var mf:Array=data.murals[i].fx
		rects[i]=Vector4(mr[0],mr[1],mr[2],mr[3]);places[i]=Vector4(mp[0],mp[1],mp[2],mp[3]);fx[i]=Vector2(mf[0],mf[1])
	material.set_shader_parameter("mural_rect",rects);material.set_shader_parameter("mural_place",places);material.set_shader_parameter("mural_fx",fx)
	material.set_shader_parameter("team_a",team_colors[0]);material.set_shader_parameter("team_b",team_colors[1])
	grate_material=material.duplicate();grate_material.shader=load("res://assets/shaders/ink_grate.gdshader");grate_material.set_shader_parameter("grate",true)

func _add_mesh(file: FileAccess,record: Dictionary) -> void:
	# Source DockProps can be an empty instanced batch on maps without dock props.
	if not record.attributes.has("position"):return
	var mesh:=MeshLoader.build(file,record,_paint_uv.get(str(record.name),PackedFloat32Array()))
	var mat: Material
	if record.name=="level":mat=material
	elif record.name=="grates":mat=grate_material
	elif record.name in ["spawnPad:face","spawnPad:barrier"]:
		var decor:=ShaderMaterial.new()
		decor.shader=load("res://assets/shaders/native_spawn_pad.gdshader" if record.name=="spawnPad:face" else "res://assets/shaders/native_spawn_barrier.gdshader")
		for key in record.material.uniforms:decor.set_shader_parameter(key,record.material.uniforms[key] if key!="uColor" else team_colors[0 if vec3(record.transform.slice(12,15)).distance_to(vec3(layout.spawnPads[0]))<5 else 1].srgb_to_linear())
		for key in record.material.get("texture_uniforms",{}):
			if record.material.texture_uniforms[key]!=null:decor.set_shader_parameter(key,load("res://assets/textures/"+record.material.texture_uniforms[key]))
		_decor_materials.append(decor);mat=decor
	else:
		mat=InkSourceLighting.make(record.material,lighting_theme)
		_source_materials.append(mat)
	if record.has("instances"):
		var multimesh:=MultiMesh.new();multimesh.transform_format=MultiMesh.TRANSFORM_3D;multimesh.use_colors=true
		multimesh.mesh=mesh;multimesh.instance_count=record.instances.size()
		for i in record.instances.size():
			var r:Dictionary=record.instances[i];multimesh.set_instance_transform(i,MeshLoader.transform_matrix(r.transform))
			var c:Array=r.color;multimesh.set_instance_color(i,Color(c[0],c[1],c[2]))
		var instance:=MultiMeshInstance3D.new();instance.name=str(record.name).replace(":","_");instance.set_meta("source_name",record.name);instance.multimesh=multimesh;instance.material_override=mat;instance.transform=MeshLoader.transform_matrix(record.transform);add_child(instance)
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if record.get("cast_shadow",true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	else:
		var instance:=MeshInstance3D.new();instance.mesh=mesh;instance.material_override=mat;instance.transform=MeshLoader.transform_matrix(record.transform)
		instance.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_ON if record.get("cast_shadow",true) else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		instance.name=str(record.name).replace(":","_");instance.set_meta("source_name",record.name);add_child(instance)

func _build_environment(time_of_day: String) -> void:
	var data: Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/"+stage_id+"_env.json"))
	var theme:Dictionary=data.themes["sunset" if time_of_day=="dusk" else "golden" if stage_id=="halyard" else "day"]
	lighting_theme=theme.duplicate(true)
	for source_material in _source_materials:InkSourceLighting.configure(source_material,lighting_theme)
	var sun:=DirectionalLight3D.new();sun.name="SourceSun";sun.light_color=Color(theme.sunColor);sun.light_energy=float(theme.sunIntensity)/PI;sun.shadow_enabled=true
	if not OS.has_feature("mobile") and DisplayServer.get_name()!="headless":
		RenderingServer.directional_soft_shadow_filter_set_quality(RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM if quality in ["high","ultra"] else RenderingServer.SHADOW_QUALITY_SOFT_LOW)
		sun.shadow_blur=.65
	var el:=deg_to_rad(float(theme.sunEl));var az:=deg_to_rad(float(theme.sunAz));var sun_dir:=Vector3(cos(el)*cos(az),sin(el),cos(el)*sin(az))
	sun.directional_shadow_max_distance=150;sun.directional_shadow_mode=DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.shadow_bias=.1;sun.shadow_normal_bias=1.4;add_child(sun);sun.look_at(-sun_dir)
	material.set_shader_parameter("sun_direction",sun_dir);grate_material.set_shader_parameter("sun_direction",sun_dir)
	# The original hemisphere light is separate from its sky environment map.
	var hemi:Dictionary=InkAvatar._hemi_parameters(theme)
	for target in [material,grate_material]:
		target.set_shader_parameter("hemi_sky",hemi.sky)
		target.set_shader_parameter("hemi_ground",hemi.ground)
	_configure_lamps(float(theme.get("night",0.0)))
	var sky_images:Array[Image]=[]
	for i in 6:
		var tex:Texture2D=load("res://assets/textures/sky/%s_%s_%d.png"%[stage_id,time_of_day,i]);var im:=tex.get_image();im.convert(Image.FORMAT_RGBA8);im.flip_y();im.generate_mipmaps();sky_images.append(im)
	var cube:=Cubemap.new();cube.create_from_images(sky_images)
	var sky_mat:=ShaderMaterial.new();sky_mat.shader=load("res://assets/shaders/native_sky.gdshader");sky_mat.set_shader_parameter("source_sky",cube)
	# The source uses a separate HDR ENV_PASS with a soft sun for material IBL.
	# Keeping it frozen avoids rebaking radiance while the visible world animates.
	var radiance_theme:String="sunset" if time_of_day=="dusk" else "golden" if stage_id=="halyard" else "day"
	var radiance_key:String="radiance:"+radiance_theme
	if not _library_cache.has(radiance_key):
		var radiance_images:Array[Image]=[]
		for i in 6:
			var texture:Texture2D=load("res://assets/textures/radiance/%s_%d.hdr"%[radiance_theme,i])
			var radiance_image:Image=texture.get_image()
			if radiance_image.is_compressed():radiance_image.decompress()
			radiance_image.convert(Image.FORMAT_RGBAH);radiance_image.flip_y();radiance_image.generate_mipmaps();radiance_images.append(radiance_image)
		var radiance_cube:=Cubemap.new();radiance_cube.create_from_images(radiance_images);_library_cache[radiance_key]=radiance_cube
	source_radiance=_library_cache[radiance_key]
	var pmrem_key:String="pmrem:"+radiance_theme
	if not _library_cache.has(pmrem_key):
		var pixels:=FileAccess.get_file_as_bytes("res://assets/textures/radiance/%s_pmrem.bin"%radiance_theme)
		var filtered:=Image.create_from_data(768,1024,false,Image.FORMAT_RGBAH,pixels)
		_library_cache[pmrem_key]=ImageTexture.create_from_image(filtered)
	source_pmrem=_library_cache[pmrem_key]
	lighting_theme.source_pmrem=source_pmrem
	for source_material in _source_materials:InkSourceLighting.configure(source_material,lighting_theme)
	for target:ShaderMaterial in [material,grate_material]:
		target.set_shader_parameter("source_pmrem",source_pmrem)
		target.set_shader_parameter("source_pmrem_enabled",true)
		target.set_shader_parameter("source_env_intensity",float(theme.get("envK",.45))*.9)
	sky_mat.set_shader_parameter("source_radiance",source_radiance)
	var sky:=Sky.new();sky.sky_material=sky_mat;sky.radiance_size=Sky.RADIANCE_SIZE_256
	sky.set_meta("source_pmrem",source_pmrem)
	var env:=Environment.new();env.background_mode=Environment.BG_SKY;env.sky=sky;env.ambient_light_source=Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy=float(theme.get("envK",.45));env.tonemap_mode=Environment.TONE_MAPPER_LINEAR;env.tonemap_exposure=1.0
	env.glow_enabled=false
	env.fog_enabled=true;env.fog_light_color=Color(theme.horizon);env.fog_density=.0007;env.fog_sky_affect=0.0
	var world:=WorldEnvironment.new();world.name="WorldEnvironment";world.environment=env;add_child(world)
	if DisplayServer.get_name()!="headless" and RenderingServer.get_rendering_device()!=null:
		grade=preload("res://scripts/world/ink_grade.gd").new();grade.configure(theme)
		grade.bloom_enabled=quality!="low"
		var compositor:=Compositor.new();compositor.compositor_effects=[grade];world.compositor=compositor
	environment_detail=preload("res://scripts/world/ink_environment.gd").new();environment_detail.quality=quality;environment_detail.name="OriginalEnvironment";add_child(environment_detail)
	environment_detail.configure(stage_id,time_of_day,self)

func _configure_lamps(night:float) -> void:
	var positions:=PackedVector3Array()
	var authored:Array=layout.get("decor",{}).get("lamps",[])
	var mirrored:Array=authored.duplicate()
	for point:Array in authored:mirrored.append([-float(point[0]),-float(point[1])])
	if night>.01:
		for point:Array in mirrored.slice(0,12):
			var x:float=point[0];var z:float=point[1]
			positions.append(Vector3(x+.92*(-1.0 if x>0.0 else 1.0),maxf(0.0,ground_height(x,z))+4.9,z))
	var count:int=positions.size()
	positions.resize(12)
	var lamp:Color=Color("ffc48a").srgb_to_linear()*16.0*night
	for target:ShaderMaterial in [material,grate_material]:
		target.set_shader_parameter("lamp_count",count)
		target.set_shader_parameter("lamp_positions",positions)
		target.set_shader_parameter("lamp_color",Vector3(lamp.r,lamp.g,lamp.b))

func cast(from: Vector3,to: Vector3,exclude: Array = [],mask: int = 1) -> Dictionary:
	var query:=PhysicsRayQueryParameters3D.create(from,to,mask)
	var rids:Array[RID]=[]
	for item in exclude:
		if item is RID:rids.append(item)
		elif item is CollisionObject3D:rids.append(item.get_rid())
	query.exclude=rids
	return get_world_3d().direct_space_state.intersect_ray(query)

func ground_height(x: float,z: float,y_max: float=50.0) -> float:
	return level_queries.ground_height(x,z,y_max) if level_queries else -INF

func _near_faces(p: Vector3) -> Array: return _face_hash.get(Vector2i(floori(p.x/8),floori(p.z/8)),[])

func sample_ink(p: Vector3,normal: Vector3=Vector3.UP) -> int:
	var best_dist:=.28;var result:=-1
	for id in _near_faces(p):
		var f:Dictionary=faces[id]
		if f.n.dot(normal)<.45:continue
		var rel:Vector3=p-f.origin;var distance:float=absf(rel.dot(f.n))
		if distance>best_dist:continue
		var u:float=rel.dot(f.u);var v:float=rel.dot(f.v)
		if u<0 or u>f.su or v<0 or v>f.sv:continue
		var k:int=int(f.grid)+clampi(int(v/f.cv),0,int(f.nv)-1)*int(f.nu)+clampi(int(u/f.cu),0,int(f.nu)-1)
		if dead[k]==0:result=int(grid[k])-1;best_dist=distance
	return result

func paint_splat(p: Vector3,normal: Vector3,radius: float,team: int,options: Dictionary={}) -> float:
	if radius<=0 or team<0 or team>1:return 0
	var area:=0.0;var seed:float=options.get("seed",randf())
	var stretch:Vector3=options.get("stretch",Vector3.ZERO)
	var smear:float=float(options.get("stretchAmt",1.0)) if stretch.length_squared()>.001 else 0.0
	var cosmetic:bool=options.get("cosmetic",false)
	var kind:=str(options.get("kind","speck" if cosmetic else "line" if smear>=1 else "shot" if smear>0 else "bomb" if radius>=1.9 else "blast" if radius>=1.05 else "drop" if radius<.3 else "trail"))
	if kind=="roll":smear=0
	for id in _near_faces(p):
		var f:Dictionary=faces[id];var rel:Vector3=p-f.origin;var distance:float=rel.dot(f.n)
		# Identical source sphere/face acceptance: no paint through a wall's back.
		if distance>radius or distance<-.12:continue
		var r:float=sqrt(maxf(0,radius*radius-distance*distance))
		if r<=.02:continue
		var u:float=rel.dot(f.u);var v:float=rel.dot(f.v)
		var direction:=Vector2(stretch.dot(f.u),stretch.dot(f.v));var projection:=direction.length();var sa:=0.0
		if projection>.2:direction/=projection;sa=smear*projection
		elif kind=="roll":direction=Vector2.RIGHT
		else:direction=Vector2.ZERO
		var reach:float=r*(1+sa)*1.5 if kind!="roll" else r*(Vector2(.55,.62).length()+.15)
		var extent:float=r*(2.75+1.4*sa)
		if u+extent<0 or v+extent<0 or u-extent>f.su or v-extent>f.sv:continue
		var x0:=maxi(0,floori((u-reach)/f.cu));var x1:=mini(int(f.nu)-1,floori((u+reach)/f.cu))
		var y0:=maxi(0,floori((v-reach)/f.cv));var y1:=mini(int(f.nv)-1,floori((v+reach)/f.cv))
		if not cosmetic:
			for y in range(y0,y1+1):
				for x in range(x0,x1+1):
					var q:=Vector2((x+.5)*f.cu-u,(y+.5)*f.cv-v)
					if kind=="roll":
						var band:=Vector2(absf(q.dot(direction))-r*.55,absf(q.dot(Vector2(-direction.y,direction.x)))-r*.62)
						if band.max(Vector2.ZERO).length()+minf(maxf(band.x,band.y),0)-r*.1>-.03*r:continue
					else:
						if sa>0:
							var along:=q.dot(direction);q+=direction*(along/(1+sa if along>0 else 1+.25*sa)-along)
						if q.length()>.97*r*_wobble(atan2(q.y,q.x),seed):continue
					var k:int=int(f.grid)+y*int(f.nu)+x;var old:int=grid[k]
					if old==team+1:continue
					grid[k]=team+1;area+=float(f.cu)*float(f.cv)
					if f.turf and dead[k]==0:
						if old>0:counts[old-1]-=1
						counts[team]+=1
		if not cosmetic:
			for pending in range(_growing.size()-1,-1,-1):
				var old_stamp:Dictionary=_growing[pending]
				if old_stamp.face!=id or old_stamp.team==team:continue
				if Vector2(old_stamp.u-u,old_stamp.v-v).length()>r*2.75+old_stamp.radius*3.9:continue
				if _gpu:_gpu.stamp(f,old_stamp,3,1,false)
				else:_stamp(old_stamp,1)
				_growing.remove_at(pending)
		var stamp:Dictionary={"face":id,"u":u,"v":v,"radius":r,"R":radius,"dn":distance,"team":team,"seed":seed,"age":0.0,"last":0.0,"time":clock,"kind":kind,"direction":direction,"smear":sa,"dur":.05 if kind=="speck" else .085+minf(.22,radius*.075),"drip_dur":1.1+minf(2.2,radius*1.5) if f.wall and kind not in ["speck","roll"] else 0.0}
		if options.get("instant",false):
			if _gpu:_gpu.stamp(f,stamp,3,1,false)
			else:_stamp(stamp,1)
		else:_growing.append(stamp)
	_map_dirty=true;ripple(p)
	return area

static func _wobble(angle: float,seed: float) -> float:
	return 1+.12*sin(3*angle+seed*TAU)+.08*sin(5*angle+seed*17)+.05*sin(7*angle+seed*41)+.03*sin(11*angle+seed*73)+.018*sin(17*angle+seed*29)+.17*pow(maxf(cos(angle-seed*37.7),0),28)+.12*pow(maxf(cos(angle-seed*53.3-2.1),0),36)

func _stamp(s: Dictionary,scale: float,drip: float=0.0) -> void:
	var f:Dictionary=faces[s.face];var a:Dictionary=f.atlas;var ppm:float=a.ppm;var r:float=s.radius*scale
	var px:float=a.x+a.pad+s.u*ppm;var py:float=a.y+a.pad+s.v*ppm
	var rad:float=r*ppm
	var color:=Color(float(s.team),minf(s.time/255.0,1.0),s.seed,1.0)
	var xmin:=maxi(int(a.x),floori(px-rad*1.5));var xmax:=mini(int(a.x+a.w)-1,ceili(px+rad*1.5))
	var ymin:=maxi(int(a.y),floori(py-rad*1.5-drip*ppm));var ymax:=mini(int(a.y+a.h)-1,ceili(py+rad*1.5))
	for y in range(ymin,ymax+1):
		for x in range(xmin,xmax+1):
			var dx:float=(x+.5-px)/ppm;var dy:float=(y+.5-py)/ppm
			var q:=Vector2(dx,dy);var dir:Vector2=s.get("direction",Vector2.ZERO);var smear:float=s.get("smear",0.0)
			var distance:float
			if s.get("kind","")=="roll":
				var band:=Vector2(absf(q.dot(dir))-r*.55,absf(q.dot(Vector2(-dir.y,dir.x)))-s.radius*.62)
				distance=band.max(Vector2.ZERO).length()+minf(maxf(band.x,band.y),0)-s.radius*.1
			else:
				if smear>0:
					var along:=q.dot(dir);q+=dir*(along/(1+smear if along>0 else 1+.25*smear)-along)
				distance=q.length()-r*_wobble(atan2(q.y,q.x),s.seed)
			if f.wall and drip>0:
				for k in 3:
					var shift:float=sin(s.seed*13.7+k*31.3)*r*.65
					var len:float=drip*(.3+absf(sin(s.seed*21+k*5))*.7)
					if dy<-.4*r and dy>-.4*r-len:distance=minf(distance,absf(dx-shift)-r*.045)
			if distance>1.0/ppm:continue
			var alpha:float=clampf(.5-distance*ppm*.65,0,1)
			var old:=paint_image.get_pixel(x,y)
			if old.a>0 and old.g>color.g+.003:continue
			var c:=color;c.a=maxf(old.a,alpha)
			paint_image.set_pixel(x,y,c)
	_dirty=true

func update(dt: float,actors: Array = []) -> void:
	clock+=dt;_upload_time+=dt;_map_acc+=dt
	for decor in _decor_materials:decor.set_shader_parameter("uTime",clock)
	for i in range(_growing.size()-1,-1,-1):
		var s:Dictionary=_growing[i];s.age+=dt
		if _gpu:
			var tn:float=s.age/s.dur;var td:float=clampf(s.age/s.drip_dur,0,1) if s.drip_dur>0 else 1.0
			var done:bool=tn>=1.75
			_gpu.stamp(faces[s.face],s,minf(tn,3),1-pow(1-td,2.2),done and s.drip_dur>0)
			if done and td>=1:_growing.remove_at(i)
			continue
		var t:float=clampf(s.age/s.dur,0,1);var scale:float=lerpf(.4,1.0,1-pow(1-t,4))
		if scale>s.last+.12 or t==1 and s.last<1:
			_stamp(s,scale);s.last=scale
		if s.drip_dur>0 and s.age>.2 and s.age<s.drip_dur and fmod(s.age,.16)<dt:_stamp(s,1.0,s.radius*(1-pow(1-clampf(s.age/s.drip_dur,0,1),2.2))*2.8)
		if s.age>maxf(s.dur*1.75,s.drip_dur):_growing.remove_at(i)
	if _gpu:_gpu.flush(dt)
	elif _dirty and _upload_time>.05:
		paint_texture.update(paint_image);_dirty=false;_upload_time=0
	material.set_shader_parameter("clock",clock);material.set_shader_parameter("ripples",_ripples);material.set_shader_parameter("ripple_params",_ripple_params)
	var camera:=get_viewport().get_camera_3d();var camera_position:=camera.global_position if camera else Vector3.ZERO
	var wake:Dictionary=_wake.update(dt,clock,actors,camera_position)
	for key in wake:material.set_shader_parameter(key,wake[key])
	if not external_minimap and _map_dirty and _map_acc>1.0:_update_minimap();_map_acc=0;_map_dirty=false

func _exit_tree() -> void:
	if _gpu:_gpu.release()

func ripple(p: Vector3,amplitude: float=.006,wavelength: float=.14,speed: float=1.2,life: float=.7) -> void:
	_ripples[_ripple_cursor]=Vector4(p.x,p.y,p.z,clock);_ripple_params[_ripple_cursor]=Vector4(amplitude,wavelength,speed,life);_ripple_cursor=(_ripple_cursor+1)%24

func coverage() -> Vector2: return Vector2(float(counts[0])/turf_total,float(counts[1])/turf_total)

func minimap_texture() -> Texture2D: return _minimap_texture

func _update_minimap() -> void:
	_minimap.fill(Color("c9d8de"))
	for f in faces:
		if not f.paintable or not f.turf:continue
		for y in int(f.nv):
			for x in int(f.nu):
				var k:int=int(f.grid)+y*int(f.nu)+x
				if dead[k]>0:continue
				var p:Vector3=f.origin+f.u*(x+.5)*f.cu+f.v*(y+.5)*f.cv
				var mx:=clampi(int((p.x-bounds.minX)/(bounds.maxX-bounds.minX)*255),0,255)
				var my:=clampi(int((p.z-bounds.minZ)/(bounds.maxZ-bounds.minZ)*255),0,255)
				_minimap.set_pixel(mx,my,team_colors[grid[k]-1] if grid[k]>0 else Color("eee8d6"))
	_minimap_texture.update(_minimap)

func find_path(from: Vector3,to: Vector3,team:int=0) -> PackedVector3Array:
	return actor_nav.find_path(from,to,team) if actor_nav else PackedVector3Array()
