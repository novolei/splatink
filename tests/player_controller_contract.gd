extends SceneTree
const Controller=preload("res://scripts/game/ink_player_controller.gd")
class Body:
	extends Node3D
	var team_id:int=1
	var alive:bool=true
	var form:String="kid"
	var submerged:bool=false
	var invuln:float=0.0
	var smooth_y:float=0.0
	var weapon_id:String="shooter"
	var aim_point:Vector3=Vector3.ZERO
	var firing:bool=false
	var _prev:Dictionary={"fire":false}
	var world_distance:float=70.0
	var blocked:bool=false
	func visual_position()->Vector3:return global_position+Vector3.UP*smooth_y
	func controller_cast(begin:Vector3,end:Vector3,_skip:bool)->Dictionary:
		var distance:float=begin.distance_to(end)
		if distance>69.9:return {"position":begin+(end-begin).normalized()*world_distance} if world_distance<70.0 else {}
		return {"position":begin.lerp(end,.5)} if blocked else {}
class Boss:
	extends Node3D
	var distance:float=-1.0
	func ray_distance(_begin:Vector3,_direction:Vector3,maximum:float)->float:return distance if distance>0.0 and distance<maximum else -1.0
class Rig:
	extends Node
	var aim_camera:Camera3D
class Arena:
	extends Node3D
	var local_player:Node3D
	var camera:Camera3D
	var camera_rig:Node
	var actors:Array=[]
	var boss:Node3D
	var settings:Dictionary={}
	var _yaw:float=0.0
	var _pitch:float=0.0
var checks:int=0
var failures:Array[String]=[]
func _initialize()->void:call_deferred("run")
func vec(data:Array)->Vector3:return Vector3(data[0],data[1],data[2])
func vec2(data:Array)->Vector2:return Vector2(data[0],data[1])
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:
		failures.append(label)
		if failures.size()<=16:push_error(label)
func near(actual:float,wanted:float,label:String,tolerance:float=.0005)->void:check(absf(actual-wanted)<tolerance,label+" actual="+str(actual)+" source="+str(wanted))
func near3(actual:Vector3,wanted:Array,label:String)->void:
	near(actual.x,wanted[0],label+" x");near(actual.y,wanted[1],label+" y");near(actual.z,wanted[2],label+" z")
func run()->void:
	var source:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://data/player_controller.json"))
	for row:Dictionary in source.capsules:
		var result:Vector2=Controller.segment_capsule_distance(vec(row.a),vec(row.b),vec(row.base),.38,row.height)
		near(result.x,row.t,"capsule segment parameter",.002)
		near(result.y,row.distance,"capsule axis distance")
	var arena:=Arena.new();root.add_child(arena)
	var body:=Body.new();body.team_id=0;arena.add_child(body);arena.local_player=body
	var camera:=Camera3D.new();arena.add_child(camera);arena.camera=camera
	var rig:=Rig.new();rig.aim_camera=camera;arena.add_child(rig);arena.camera_rig=rig
	var boss:=Boss.new();arena.add_child(boss)
	var enemies:Array[Body]=[]
	for i in 5:
		var enemy:=Body.new();arena.add_child(enemy);enemies.append(enemy)
	var controller:=Controller.new();controller.configure(arena)
	for row:Dictionary in source.aimCases:
		camera.global_position=vec(row.camera);camera.look_at(camera.global_position+vec(row.direction))
		body.global_position=vec(row.local);body.weapon_id=row.weapon;body.world_distance=row.worldDistance
		boss.distance=row.bossDistance;arena.boss=boss if boss.distance>0.0 else null
		arena.actors=[body]
		for i in 5:
			var wanted:Dictionary=row.enemies[i];var enemy:Body=enemies[i]
			enemy.global_position=vec(wanted.position);enemy.team_id=int(wanted.team);enemy.alive=wanted.alive
			enemy.form=wanted.form;enemy.smooth_y=wanted.smoothY;enemy.submerged=wanted.submerged
			arena.actors.append(enemy)
		var point:Vector3=controller.compute_aim()
		near3(point,row.point,"production camera aim")
		check(controller.on_target==boss if row.bossTarget else arena.actors.find(controller.on_target)==int(row.target),"nearest visible body or Boss")
		check(controller.in_range==bool(row.inRange),"weapon effective range")
	for scenario:Dictionary in source.lookCases:
		controller.reset();arena._yaw=0.0;arena._pitch=0.0;body.global_position=Vector3.ZERO;body.weapon_id="shooter";body.world_distance=70.0;arena.boss=null
		var enemy:Body=enemies[0];enemy.team_id=1;enemy.alive=true;enemy.form="kid";enemy.submerged=false
		arena.actors=[body,enemy]
		for i in scenario.frames.size():
			var row:Dictionary=scenario.frames[i];var label:String=str(scenario.scenario)+" "+str(i)
			arena.settings=row.settings;camera.global_position=vec(row.camera);camera.look_at(camera.global_position+vec(row.direction))
			enemy.global_position=vec(row.enemy);enemy.smooth_y=row.smoothY;body.blocked=row.blocked
			controller.queue_mouse(vec2(row.mouse));controller.last_device=row.lastDevice
			var command:Dictionary=controller.update(row.dt,{"move":vec2(row.move),"left":vec2(row.left),"right":vec2(row.right),"has_pad":row.hasPad,"map_up":row.mapUp})
			near(arena._yaw,row.yaw,label+" yaw");near(arena._pitch,row.pitch,label+" pitch")
			near(controller.pad_look.x,row.padLook[0],label+" stick x");near(controller.pad_look.y,row.padLook[1],label+" stick y")
			near(controller.edge_time,row.edgeTime,label+" edge boost")
			near3(command.move,row.movement,label+" world movement");near3(command.aim_point,row.point,label+" point")
			check((controller.on_target==enemy)==bool(row.target),label+" target");check(controller.in_range==bool(row.inRange),label+" range")
	controller.reset();arena.settings={"sensitivity":1.1};arena._yaw=0.0;arena._pitch=0.0
	controller.apply_mouse(Vector2(24,18))
	near(arena._yaw,-24*.0021*1.1,"raw mouse reaches render yaw immediately",.000001)
	near(arena._pitch,-18*.0021*1.1,"raw mouse reaches render pitch immediately",.000001)
	var mouse_yaw:float=arena._yaw
	controller.update(1.0/60.0,{})
	near(arena._yaw,mouse_yaw,"raw delta consumed once",.000001)
	check(not controller.mouse_active and controller.mouse_delta==Vector2.ZERO,"raw look activity consumed by tracking")
	arena.settings={"invertY":true};arena._pitch=0.0;controller.apply_mouse(Vector2(0,10))
	near(arena._pitch,.021,"raw mouse invertY",.000001)
	controller.apply_mouse(Vector2(0,10000));near(arena._pitch,1.15,"source raw pitch upper clamp",.000001)
	print("SPLATINK_PLAYER_CONTROLLER ",JSON.stringify({"checks":checks,"failures":failures.size(),"source_aim_cases":source.aimCases.size(),"source_capsules":source.capsules.size(),"source_look_frames":900}))
	if failures.is_empty():arena.free();quit(0)
	else:arena.free();quit(1)
