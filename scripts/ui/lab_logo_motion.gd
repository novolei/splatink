extends Control
var letters:Array[Dictionary]=[]
var clock:float=0
var font_pixels:float=43.52
func _process(dt:float)->void:
	clock+=dt
	for index:int in letters.size():
		var item:Dictionary=letters[index];var node:Label=item.node as Label
		var phase:float=(1-cos((clock+index*.27)*TAU/3.4))*.5
		node.position=item.position+Vector2(0,-font_pixels*.045*phase);node.rotation=float(item.rotation)+deg_to_rad(2.5)*phase
