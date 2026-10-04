class_name InkBossNav
extends RefCounted

## Original BossNav geometry baked from Level + dressing. Query and A* algorithms mirror the source.
const WALL_BODY:Array=[Vector2(2.3,2.5),Vector2(-1.8,2.6)]
const FLOOR_BODY:Array=[Vector2(2.2,1.45),Vector2(0,1.5),Vector2(-2.3,1.45)]
static var _cache:Dictionary={}
var metadata:Dictionary={}
var fields:PackedFloat32Array
var plan_ids:PackedInt32Array
var nx:int=0
var nz:int=0
var x0:float=0
var z0:float=0
var step:float=.5
var floor_y:float=0
var pads:Array=[]
var area:float=0
var _g:PackedFloat32Array
var _from:PackedInt32Array
var _seen:PackedInt32Array
var _closed:PackedInt32Array
var _stamp:int=0

class Heap:
	extends RefCounted
	var ids:Array[int]=[]
	var priorities:Array[float]=[]
	func push(id:int,priority:float)->void:
		var index:int=ids.size()
		ids.append(id);priorities.append(priority)
		while index>0:
			var parent:int=(index-1)>>1
			if priorities[parent]<=priority:break
			ids[index]=ids[parent];priorities[index]=priorities[parent];index=parent
		ids[index]=id;priorities[index]=priority
	func pop()->int:
		var top:int=ids[0]
		var last:int=ids.pop_back()
		var priority:float=priorities.pop_back()
		if not ids.is_empty():
			var index:int=0
			while true:
				var left:int=index*2+1
				var right:int=left+1
				var minimum:int=index
				var value:float=priority
				if left<ids.size() and priorities[left]<value:minimum=left;value=priorities[left]
				if right<ids.size() and priorities[right]<value:minimum=right
				if minimum==index:break
				ids[index]=ids[minimum];priorities[index]=priorities[minimum];index=minimum
			ids[index]=last;priorities[index]=priority
		return top

func configure(stage:String)->bool:
	if not _cache.has(stage):
		var filename:String="res://data/boss_nav/%s.json"%stage
		if not FileAccess.file_exists(filename):return false
		var data:Dictionary=JSON.parse_string(FileAccess.get_file_as_string(filename))
		var file:=FileAccess.open(str(data.fields),FileAccess.READ)
		if not file:return false
		_cache[stage]={"metadata":data,"fields":file.get_buffer(file.get_length()).to_float32_array()}
	metadata=_cache[stage].metadata
	fields=_cache[stage].fields
	nx=int(metadata.nx);nz=int(metadata.nz);x0=float(metadata.x0);z0=float(metadata.z0)
	step=float(metadata.step);floor_y=float(metadata.floor_y);pads=metadata.pads;area=float(metadata.area)
	plan_ids.clear()
	for index in nx*nz:
		if fields[index*5+4]>0:plan_ids.append(index)
	_g.resize(nx*nz);_from.resize(nx*nz);_seen.resize(nx*nz);_closed.resize(nx*nz)
	return true

func xz(index:int)->Vector2:
	return Vector2(x0+float(index%nx)*step,z0+float(index/nx)*step)

func cell(x:float,z:float)->int:
	var ix:int=int(floor((x-x0)/step+.5))
	var iz:int=int(floor((z-z0)/step+.5))
	return -1 if ix<0 or iz<0 or ix>=nx or iz>=nz else iz*nx+ix

func wall_clear(x:float,z:float)->float:
	var index:int=cell(x,z)
	return 0.0 if index<0 else fields[index*5+1]

func floor_clear(x:float,z:float)->float:
	var index:int=cell(x,z)
	return 0.0 if index<0 else fields[index*5+2]

func kind_at(x:float,z:float)->int:
	var index:int=cell(x,z)
	return 2 if index<0 else int(fields[index*5+3])

func floor_at(x:float,z:float)->float:
	var index:int=cell(x,z)
	var height:float=floor_y if index<0 or fields[index*5+3]>0 else fields[index*5]
	return height if height-floor_y<.45 else floor_y

func in_pad(x:float,z:float,margin:float=0)->bool:
	for pad in pads:
		if Vector2(x-float(pad.x),z-float(pad.z)).length()<float(pad.r)+margin:return true
	return false

func is_plan(x:float,z:float)->bool:
	var index:int=cell(x,z)
	return index>=0 and fields[index*5+4]>0

func pose_ok(x:float,z:float,yaw:float)->bool:
	var sx:float=sin(yaw);var sz:float=cos(yaw)
	for shape:Vector2 in WALL_BODY:
		if wall_clear(x+sx*shape.x,z+sz*shape.x)<shape.y:return false
	for shape:Vector2 in FLOOR_BODY:
		if floor_clear(x+sx*shape.x,z+sz*shape.x)<shape.y:return false
	return true

func turn_ok(x:float,z:float,yaw:float)->bool:
	var sx:float=sin(yaw);var sz:float=cos(yaw)
	for shape:Vector2 in WALL_BODY:
		if wall_clear(x+sx*shape.x,z+sz*shape.x)<shape.y:return false
	return floor_clear(x,z)>=1.5

func cast(x:float,z:float,yaw:float,maximum:float,increment:float=.25)->Dictionary:
	var sx:float=sin(yaw);var sz:float=cos(yaw)
	var distance:float=0
	while distance+increment<=maximum and pose_ok(x+sx*(distance+increment),z+sz*(distance+increment),yaw):distance+=increment
	var wall:bool=false
	if distance+increment<=maximum:
		var front:Vector2=WALL_BODY[0]
		var fx:float=x+sx*(distance+front.x);var fz:float=z+sz*(distance+front.x)
		for index in 9:
			var angle:float=-.9+float(index)/8.0*1.8
			if kind_at(fx+sin(yaw+angle)*(front.y+.6),fz+cos(yaw+angle)*(front.y+.6))==1:wall=true;break
	return {"dist":distance,"wall":wall}

func _cell_ok(index:int,slack:float=0)->bool:
	return index>=0 and fields[index*5+1]>=2.9-slack and fields[index*5+2]>=1.8-slack

func line_ok(from:Vector2,to:Vector2,slack:float=.3)->bool:
	var count:int=maxi(1,int(ceil(from.distance_to(to)/(step*.8))))
	for index in count+1:
		var point:Vector2=from.lerp(to,float(index)/float(count))
		if not _cell_ok(cell(point.x,point.y),slack):return false
	return true

func nearest_plan(x:float,z:float)->int:
	var ix:int=int(floor((x-x0)/step+.5));var iz:int=int(floor((z-z0)/step+.5))
	for radius in 60:
		var best:int=-1;var squared:int=2147483647
		for dz in range(-radius,radius+1):
			for dx in range(-radius,radius+1):
				if maxi(absi(dx),absi(dz))!=radius:continue
				var jx:int=ix+dx;var jz:int=iz+dz
				if jx<0 or jz<0 or jx>=nx or jz>=nz:continue
				var index:int=jz*nx+jx
				if fields[index*5+4]<=0:continue
				var distance:int=dx*dx+dz*dz
				if distance<squared:squared=distance;best=index
		if best>=0:return best
	return plan_ids[0] if not plan_ids.is_empty() else -1

func find_path(from:Vector2,to:Vector2)->PackedVector2Array:
	var begin:int=nearest_plan(from.x,from.y);var end:int=nearest_plan(to.x,to.y)
	if begin<0 or end<0:return PackedVector2Array()
	_stamp+=1
	var endpoint:Vector2=xz(end)
	var heap:=Heap.new()
	_g[begin]=0;_from[begin]=-1;_seen[begin]=_stamp;heap.push(begin,xz(begin).distance_to(endpoint))
	var iterations:int=0
	while not heap.ids.is_empty() and iterations<40000:
		iterations+=1
		var current:int=heap.pop()
		if current==end:break
		if _closed[current]==_stamp:continue
		_closed[current]=_stamp
		var cx:int=current%nx;var cz:int=current/nx
		for dz in range(-1,2):
			for dx in range(-1,2):
				if dx==0 and dz==0:continue
				var jx:int=cx+dx;var jz:int=cz+dz
				if jx<0 or jz<0 or jx>=nx or jz>=nz:continue
				var index:int=jz*nx+jx
				if fields[index*5+4]<=0:continue
				var cost:float=_g[current]+Vector2(dx,dz).length()*step*(1+maxf(0,5-fields[index*5+1])*.1+maxf(0,3-fields[index*5+2])*.15)
				if _seen[index]!=_stamp or cost<_g[index]:
					_seen[index]=_stamp;_g[index]=cost;_from[index]=current;heap.push(index,cost+xz(index).distance_to(endpoint))
	if _seen[end]!=_stamp:return PackedVector2Array()
	var cells:PackedInt32Array=[]
	var previous:int=end
	while previous!=-1 and cells.size()<=8000:cells.append(previous);previous=_from[previous]
	cells.reverse()
	var result:PackedVector2Array=[xz(cells[0])]
	var index:int=0
	while index<cells.size()-1:
		var last:int=cells.size()-1
		while last>index+1 and not line_ok(xz(cells[index]),xz(cells[last])):last-=1
		result.append(xz(cells[last]));index=last
	return result

func random_point()->Vector2:
	return xz(plan_ids[randi()%plan_ids.size()]) if not plan_ids.is_empty() else Vector2.ZERO
