extends SceneTree
const Stage=preload("res://scripts/world/ink_stage.gd")
var stage: InkStage
var failures:Array[String]=[]
var checks:=0

func _initialize() -> void:
	create_timer(25).timeout.connect(func():push_error("GPU_PAINT_TIMEOUT");quit(2))
	call_deferred("run")

func check(condition: bool,message: String) -> void:
	checks+=1
	if not condition:failures.append(message);push_error(message)

func settle(seconds: float=.08) -> void:
	await create_timer(seconds).timeout
	await RenderingServer.frame_post_draw

func run() -> void:
	check(DisplayServer.get_name()!="headless","GPU test must use the native renderer")
	var quality:="medium"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--quality="):quality=arg.trim_prefix("--quality=")
	stage=Stage.new();root.add_child(stage);stage.build("tidewater","day",[Color("ff3f9e"),Color("18d48c")],quality)
	var camera:=Camera3D.new();stage.add_child(camera);camera.position=Vector3(0,12,-30);camera.look_at(Vector3.ZERO);camera.current=true
	await settle(.2)
	check(stage._gpu!=null and stage._gpu.ready,"native GPU atlas failed to initialize")
	var point:=Vector3(0,stage.ground_height(0,-30)+.025,-30)
	var face:Dictionary={}
	for f in stage.faces:
		var delta:Vector3=point-f.origin
		if f.paintable and f.n.y>.99 and absf(delta.dot(f.n))<.1 and delta.dot(f.u)>1.5 and delta.dot(f.u)<f.su-1.5 and delta.dot(f.v)>1.5 and delta.dot(f.v)<f.sv-1.5:face=f;break
	check(not face.is_empty(),"no open floor for GPU test")
	if face.is_empty():quit(1);return
	var delta:Vector3=point-face.origin
	var pixel:=Vector2i(roundi(face.atlas.x+face.atlas.pad+delta.dot(face.u)*face.atlas.ppm),roundi(face.atlas.y+face.atlas.pad+delta.dot(face.v)*face.atlas.ppm))
	stage.paint_splat(point,Vector3.UP,1.4,0,{"seed":.42,"instant":true,"kind":"bomb"});stage.update(.016)
	await settle()
	var first:Color=stage.paint_texture.get_image().get_pixelv(pixel)
	check(first.a>.9,"GPU brush is missing from the source atlas coordinates")
	check(first.r<.05 and first.g>.8,"team A / wetness channels are not premultiplied correctly")
	check(stage.sample_ink(point)==0,"CPU ink query differs from the GPU stamp team")
	stage.paint_splat(point,Vector3.UP,1.4,0,{"seed":.42,"instant":true,"kind":"bomb"});stage.update(.016)
	await settle()
	var repeated:Color=stage.paint_texture.get_image().get_pixelv(pixel)
	check(absf(first.a-repeated.a)<.01,"coverage must use MAX rather than accumulating alpha")
	stage.paint_splat(point,Vector3.UP,1.4,1,{"seed":.42,"instant":true,"kind":"bomb"});stage.update(.016)
	await settle()
	var opposite:Color=stage.paint_texture.get_image().get_pixelv(pixel)
	check(opposite.r>.85 and opposite.a>=first.a-.01,"newer opposing team must replace the pigment and preserve coverage")
	check(stage.sample_ink(point)==1,"opposing stamp failed to transfer CPU ownership")
	stage.update(1.0);await settle()
	var dried:Color=stage.paint_texture.get_image().get_pixelv(pixel)
	check(dried.g<opposite.g-.025 and absf(dried.a-opposite.a)<.01,"wetness subtraction changed persistent ink coverage")
	var report:Dictionary={"passed":failures.is_empty(),"checks":checks,"failures":failures,"atlas":stage.atlas_size,"pixel":[pixel.x,pixel.y],"first":str(first),"opposite":str(opposite),"dried":str(dried)}
	var file:=FileAccess.open("res://shots/gpu_paint_contract.json",FileAccess.WRITE);file.store_string(JSON.stringify(report,"\t"));file.close()
	print("GPU_PAINT_CONTRACT "+JSON.stringify(report));quit(0 if failures.is_empty() else 1)
