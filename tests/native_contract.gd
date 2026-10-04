extends SceneTree
const Stage=preload("res://scripts/world/ink_stage.gd")
var failures: Array[String]=[]
func _initialize() -> void:call_deferred("run")
func check(value: bool,message: String) -> void:
	if not value:failures.append(message);push_error(message)
func run() -> void:
	var reports:Array=[]
	for id in ["tidewater","kelpline","halyard","cargo"]:
		var stage:=Stage.new();root.add_child(stage);stage.build(id,"day")
		check(stage.faces.size()>200,id+" source faces missing")
		check(stage.blocks.size()>100,id+" source colliders missing")
		check(stage.turf_total>1000,id+" playable turf mask missing")
		check(stage.coverage()==Vector2.ZERO,id+" fresh paint is not neutral")
		var found:=false;var pos:=Vector3.ZERO;var normal:=Vector3.UP
		for f in stage.faces:
			if found:break
			if not f.paintable or not f.turf:continue
			for i in int(f.nu)*int(f.nv):
				if stage.dead[int(f.grid)+i]!=0:continue
				pos=f.origin+f.u*(i%int(f.nu)+.5)*f.cu+f.v*(floori(float(i)/int(f.nu))+.5)*f.cv;normal=f.n;found=true;break
		check(found,id+" no live floor")
		var area:=stage.paint_splat(pos,normal,1.5,0,{"seed":.42})
		check(area>0,id+" paint failed to award area")
		check(stage.sample_ink(pos,normal)==0,id+" paint sampling does not match scoring")
		var first:=stage.coverage()
		var repeated:=stage.paint_splat(pos,normal,1.5,0,{"seed":.42})
		check(repeated==0,id+" repeated paint double counts")
		check(first==stage.coverage(),id+" idempotent turf score changed")
		stage.paint_splat(pos,normal,1.5,1,{"seed":.42})
		check(stage.sample_ink(pos,normal)==1,id+" enemy repaint not sampled")
		check(absf(stage.coverage().x+stage.coverage().y-first.x-first.y)<.0001,id+" coverage not conserved")
		for _i in 10:stage.update(.1)
		var center:=Stage.vec3(stage.layout.spawnPads[0]);check(is_finite(stage.ground_height(center.x,center.z)),id+" spawn has no floor")
		check(stage.find_path(center,-center).size()>0,id+" no navigable route")
		reports.append({"id":id,"blocks":stage.blocks.size(),"faces":stage.faces.size(),"turf_cells":stage.turf_total,"paint_area":area,"grid":stage.grid.size()})
		stage.free();await process_frame
	var output:Dictionary={"passed":failures.is_empty(),"maps":reports,"failures":failures}
	var file:=FileAccess.open("res://shots/native_contract.json",FileAccess.WRITE);file.store_string(JSON.stringify(output,"\t"));file.close()
	print("NATIVE_CONTRACT "+JSON.stringify(output));quit(0 if failures.is_empty() else 1)
