class_name InkLevelQueries
extends RefCounted

## Source Level.queryBlocks broadphase + PaintSystem.regionStats. Geometry is
## immutable; paint ownership/dead cells are read from the live authoritative stage.
var stage:Node
var blocks:Array=[]
var faces:Array=[]
var _hash:Array[PackedInt32Array]=[]
var _block_faces:Array[PackedInt32Array]=[]
var _marks:PackedInt32Array=[]
var _query:PackedInt32Array=[]
var _stamp:int=0
var _x0:float
var _z0:float
var _width:int
var _depth:int
var _stats:Dictionary={"own":0.0,"enemy":0.0,"empty":0.0,"n":0}

func configure(level:Node) -> void:
	stage=level;blocks=stage.get("blocks");faces=stage.get("faces")
	var bounds:Dictionary=stage.get("bounds")
	_x0=float(bounds.minX)-8;_z0=float(bounds.minZ)-8
	_width=ceili((float(bounds.maxX)-float(bounds.minX)+16)/4);_depth=ceili((float(bounds.maxZ)-float(bounds.minZ)+16)/4)
	_hash.clear();_block_faces.clear();_marks.resize(blocks.size());_marks.fill(0)
	for index in _width*_depth:_hash.append(PackedInt32Array())
	for index in blocks.size():_block_faces.append(PackedInt32Array())
	for block:Dictionary in blocks:
		var half:Vector3=block.half
		var extent:Vector3=Vector3(block.axes[0]).abs()*half.x+Vector3(block.axes[1]).abs()*half.y+Vector3(block.axes[2]).abs()*half.z
		var low:Vector3=Vector3(block.center)-extent;var high:Vector3=Vector3(block.center)+extent
		for z in range(_zi(low.z),_zi(high.z)+1):
			for x in range(_xi(low.x),_xi(high.x)+1):
				var cell:int=z*_width+x;var ids:PackedInt32Array=_hash[cell]
				ids.append(int(block.id));_hash[cell]=ids
	for face:Dictionary in faces:
		var block:int=int(face.block);var ids:PackedInt32Array=_block_faces[block]
		ids.append(int(face.id));_block_faces[block]=ids

func _xi(x:float) -> int:return clampi(floori((x-_x0)/4),0,_width-1)
func _zi(z:float) -> int:return clampi(floori((z-_z0)/4),0,_depth-1)

func query_blocks(min_x:float,min_z:float,max_x:float,max_z:float) -> PackedInt32Array:
	_query.clear();_stamp+=1
	for z in range(_zi(min_z),_zi(max_z)+1):
		for x in range(_xi(min_x),_xi(max_x)+1):
			for id in _hash[z*_width+x]:
				if _marks[id]!=_stamp:_marks[id]=_stamp;_query.append(id)
	return _query

func ground_height(x:float,z:float,max_y:float=50) -> float:
	var best:float=-INF
	for id in query_blocks(x-.01,z-.01,x+.01,z+.01):
		var block:Dictionary=blocks[id]
		if not block.solid:continue
		var normal:Vector3=block.axes[1]
		if normal.y<.5:continue
		var top:Vector3=Vector3(block.center)+normal*float(block.half.y)
		var y:float=top.y-(normal.x*(x-top.x)+normal.z*(z-top.z))/normal.y
		if y>max_y or y<=best:continue
		var local:Vector3=Vector3(x,y-.01,z)-Vector3(block.center)
		if absf(local.dot(block.axes[0]))<float(block.half.x)+.001 and absf(local.dot(block.axes[1]))<float(block.half.y)+.001 and absf(local.dot(block.axes[2]))<float(block.half.z)+.001:best=y
	return best

func region_stats(point:Vector3,radius:float,team:int) -> Dictionary:
	_stats.own=0.0;_stats.enemy=0.0;_stats.empty=0.0;_stats.n=0
	var ownership:PackedByteArray=stage.get("grid");var dead:PackedByteArray=stage.get("dead")
	var squared:float=radius*radius
	for block_id in query_blocks(point.x-radius,point.z-radius,point.x+radius,point.z+radius):
		for id in _block_faces[block_id]:
			var face:Dictionary=faces[id]
			if not bool(face.turf) or face.get("atlas")==null or absf(Vector3(face.origin).y-point.y)>2.5:continue
			var relative:Vector3=point-Vector3(face.origin)
			var u:float=relative.dot(face.u);var v:float=relative.dot(face.v)
			var cu:float=float(face.cu);var cv:float=float(face.cv)
			var x0:int=maxi(0,floori((u-radius)/cu));var x1:int=mini(int(face.nu)-1,floori((u+radius)/cu))
			var y0:int=maxi(0,floori((v-radius)/cv));var y1:int=mini(int(face.nv)-1,floori((v+radius)/cv))
			for row in range(y0,y1+1,2):
				for column in range(x0,x1+1,2):
					var du:float=(column+.5)*cu-u;var dv:float=(row+.5)*cv-v
					if du*du+dv*dv>squared:continue
					var cell:int=int(face.grid)+row*int(face.nu)+column
					if dead[cell]:continue
					_stats.n+=1
					if ownership[cell]==team+1:_stats.own+=1
					elif ownership[cell]:_stats.enemy+=1
					else:_stats.empty+=1
	if int(_stats.n)>0:
		_stats.own/=float(_stats.n);_stats.enemy/=float(_stats.n);_stats.empty/=float(_stats.n)
	return _stats
