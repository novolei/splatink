extends "res://scripts/game/ink_bots.gd"
## A diagnostic match keeps the real eight actors without randomized bot attacks.
func command_for(actor, _dt:float)->Dictionary:
	return {"move":Vector3.ZERO,"aim_dir":actor.aim_dir,"fire":false,"sub":false,"swim":false,"jump":false,"special":false}
