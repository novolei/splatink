extends "res://tools/locomotion_quiet_bots.gd"
## One prepared target fires through the ordinary production bot command path.
var shooter:Node3D
var victim:Node3D
var incoming:bool=false

func command_for(actor,_dt:float)->Dictionary:
	var direction:Vector3=actor.aim_dir
	if actor==shooter and is_instance_valid(victim):
		direction=(victim.global_position+Vector3.UP*1.0-actor.global_position-Vector3.UP*1.05).normalized()
	return {"move":Vector3.ZERO,"aim_dir":direction,"aim_yaw":atan2(direction.x,direction.z),"aim_pitch":asin(clampf(direction.y,-1,1)),"fire":incoming and actor==shooter,"sub":false,"swim":false,"jump":false,"special":false}
