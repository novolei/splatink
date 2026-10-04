class_name InkActorPhysics
extends RefCounted

## Source oriented-box controller queries. Kept independent of Actor's production
## CharacterBody backend until the source probe contract verifies every contact.
const Queries=preload("res://scripts/game/ink_level_queries.gd")
const Rules=preload("res://scripts/game/ink_rules.gd")
const WALKABLE:float=.68
var queries:InkLevelQueries
var blocks:Array=[]
var faces:Array=[]
var _min_y:PackedFloat64Array=[]
var _max_y:PackedFloat64Array=[]
var _boxes:Array[PackedFloat64Array]=[]
var _faces64:Array[PackedFloat64Array]=[]
var _closest:PackedFloat64Array=[0.0,0.0,0.0]
var _face_ids:Array[PackedInt32Array]=[]
var _ring:PackedVector2Array=[]
var _ground_ray:Hit=Hit.new()
var _ring_ray:Hit=Hit.new()

class Hit:
	extends RefCounted
	var hit:bool=false
	var distance:float=0
	var position:Vector3=Vector3.ZERO
	var position64:PackedFloat64Array=[0.0,0.0,0.0]
	var normal:Vector3=Vector3.ZERO
	var normal64:PackedFloat64Array=[0.0,0.0,0.0]
	var block:int=-1
	var face:int=-1
	var u:float=0
	var v:float=0

class GroundHit:
	extends RefCounted
	var hit:bool=false
	var y:float=0
	var normal:Vector3=Vector3.UP
	var normal64:PackedFloat64Array=[0.0,1.0,0.0]
	var block:int=-1
	var face:int=-1
	var u:float=0
	var v:float=0
	var center:bool=false
	var grate:bool=false

class Contacts:
	extends RefCounted
	var position:Vector3=Vector3.ZERO
	var position64:PackedFloat64Array=[0.0,0.0,0.0]
	var ground:bool=false
	var wall:bool=false
	var ceiling:bool=false
	var ground_normal:Vector3=Vector3.UP
	var wall_normal:Vector3=Vector3.ZERO
	var ground_block:int=-1
	var wall_block:int=-1

class Motion:
	extends RefCounted
	var position:Vector3=Vector3.ZERO
	var velocity:Vector3=Vector3.ZERO
	var grounded:bool=false
	var smooth_y:float=0
	var landed:bool=false
	var land_speed:float=0
	var air_time:float=0
	var roof_time:float=0
	var roof_direction:Vector3=Vector3.ZERO
	var roof_position:Vector3=Vector3.ZERO
	var roof_stall:float=0
	var ground:GroundHit=GroundHit.new()
	var contacts:Contacts=Contacts.new()

func configure(stage:Node,source_queries:InkLevelQueries=null,source_geometry:Dictionary={}) -> void:
	queries=source_queries
	if not queries:queries=Queries.new();queries.configure(stage)
	blocks=queries.blocks;faces=queries.faces
	_min_y.resize(blocks.size());_max_y.resize(blocks.size());_face_ids.clear();_boxes.clear()
	var exact_fields:PackedFloat64Array=[]
	if source_geometry.has("physics_fields"):
		var bytes:PackedByteArray=FileAccess.get_file_as_bytes(str(source_geometry.physics_fields))
		if bytes.size()>=8 and int(bytes.decode_u32(0))==blocks.size() and int(bytes.decode_u32(4))==faces.size():exact_fields=bytes.slice(8).to_float64_array()
	for block:Dictionary in blocks:
		var original:Dictionary=source_geometry.blocks[int(block.id)] if source_geometry.has("blocks") else block
		var packed:PackedFloat64Array=[]
		for field in [original.center,original.half]:
			for axis in 3:packed.append(float(field[axis]))
		for axis in original.axes:
			for component in 3:packed.append(float(axis[component]))
		if not exact_fields.is_empty():packed=exact_fields.slice(int(block.id)*17,int(block.id)*17+15)
		_boxes.append(packed)
		var extent_y:float=absf(packed[7])*packed[3]+absf(packed[10])*packed[4]+absf(packed[13])*packed[5]
		_min_y[int(block.id)]=packed[1]-extent_y
		_max_y[int(block.id)]=packed[1]+extent_y
		if not exact_fields.is_empty():
			_min_y[int(block.id)]=exact_fields[int(block.id)*17+15];_max_y[int(block.id)]=exact_fields[int(block.id)*17+16]
		var ids:PackedInt32Array=[];ids.resize(6);ids.fill(-1);_face_ids.append(ids)
	for face:Dictionary in faces:
		var block:Dictionary=blocks[int(face.block)]
		var ids:PackedInt32Array=_face_ids[int(face.block)]
		for axis in 3:
			var dot:float=Vector3(face.n).dot(block.axes[axis])
			if absf(dot)>.9999:ids[axis*2+(0 if dot>0 else 1)]=int(face.id);break
		_face_ids[int(face.block)]=ids
	_faces64.clear()
	for face:Dictionary in faces:
		var original:Dictionary=source_geometry.faces[int(face.id)] if source_geometry.has("faces") else face
		var packed:PackedFloat64Array=[]
		for field in [original.origin,original.u,original.v]:
			for axis in 3:packed.append(float(field[axis]))
		if not exact_fields.is_empty():packed=exact_fields.slice(blocks.size()*17+int(face.id)*9,blocks.size()*17+int(face.id)*9+9)
		_faces64.append(packed)
	_ring.clear()
	for index in 8:
		var angle:float=float(index)/8*TAU
		_ring.append(Vector2(cos(angle),sin(angle)))

func raycast(origin:Vector3,direction:Vector3,max_distance:float,out:Hit=null,skip_grates:bool=false) -> Hit:
	return _raycast64(origin.x,origin.y,origin.z,direction.x,direction.y,direction.z,max_distance,out,skip_grates)

func _raycast64(ox:float,oy:float,oz:float,dx:float,dy:float,dz:float,max_distance:float,out:Hit=null,skip_grates:bool=false) -> Hit:
	if not out:out=Hit.new()
	out.hit=false;out.distance=max_distance;out.block=-1;out.face=-1
	var ex:float=ox+dx*max_distance;var ez:float=oz+dz*max_distance
	var ids:PackedInt32Array=queries.query_blocks(minf(ox,ex),minf(oz,ez),maxf(ox,ex),maxf(oz,ez))
	var best:float=max_distance
	var best_axis:int=-1;var best_sign:float=0;var best_block:int=-1
	for id in ids:
		var block:Dictionary=blocks[id]
		if not bool(block.solid) or (skip_grates and bool(block.grate)):continue
		var b:PackedFloat64Array=_boxes[id]
		var rx:float=ox-b[0];var ry:float=oy-b[1];var rz:float=oz-b[2]
		var low:float=-INF;var high:float=INF;var entry_axis:int=-1;var entry_sign:float=0;var miss:bool=false
		for axis in 3:
			var offset:int=6+axis*3
			var o:float=rx*b[offset]+ry*b[offset+1]+rz*b[offset+2]
			var d:float=dx*b[offset]+dy*b[offset+1]+dz*b[offset+2];var half:float=b[3+axis]
			if absf(d)<.000000001:
				if o< -half or o>half:miss=true;break
				continue
			var t1:float=(-half-o)/d;var t2:float=(half-o)/d;var sign:float=-1
			if t1>t2:
				var swap:float=t1
				t1=t2;t2=swap;sign=1
			if t1>low:low=t1;entry_axis=axis;entry_sign=sign
			if t2<high:high=t2
			if low>high:miss=true;break
		if miss or high<0 or low<0 or low>best:continue
		best=low;best_axis=entry_axis;best_sign=entry_sign;best_block=id
	if best_block<0:return out
	var block:Dictionary=blocks[best_block]
	var b:PackedFloat64Array=_boxes[best_block];var axis_offset:int=6+best_axis*3
	out.hit=true;out.distance=best;out.block=best_block
	out.position64[0]=ox+dx*best;out.position64[1]=oy+dy*best;out.position64[2]=oz+dz*best
	out.normal64[0]=b[axis_offset]*best_sign;out.normal64[1]=b[axis_offset+1]*best_sign;out.normal64[2]=b[axis_offset+2]*best_sign
	out.position=Vector3(out.position64[0],out.position64[1],out.position64[2]);out.normal=Vector3(out.normal64[0],out.normal64[1],out.normal64[2])
	out.face=_face_ids[best_block][best_axis*2+(0 if best_sign>0 else 1)]
	if out.face>=0:
		var face:PackedFloat64Array=_faces64[out.face]
		var fx:float=out.position64[0]-face[0];var fy:float=out.position64[1]-face[1];var fz:float=out.position64[2]-face[2]
		out.u=fx*face[3]+fy*face[4]+fz*face[5];out.v=fx*face[6]+fy*face[7]+fz*face[8]
	return out

func ground_probe(position:Vector3,up:float,down:float,foot:float,out:GroundHit=null,skip_grates:bool=false,step_min:float=.12) -> GroundHit:
	return _ground_probe64(position.x,position.y,position.z,up,down,foot,out,skip_grates,step_min)

func _ground_probe64(x:float,y:float,z:float,up:float,down:float,foot:float,out:GroundHit=null,skip_grates:bool=false,step_min:float=.12) -> GroundHit:
	if not out:out=GroundHit.new()
	out.hit=false;out.center=false
	var hit:Hit=_raycast64(x,y+up,z,0,-1,0,up+down,_ground_ray,skip_grates)
	var center_y:float=-INF;var have_center:bool=false
	if hit.hit and hit.normal64[1]>=WALKABLE:
		have_center=true;center_y=hit.position64[1];_fill_ground(out,hit,true)
	var best_y:float=center_y+step_min if have_center else -INF
	var best_index:int=-1
	for index in _ring.size():
		var angle:float=float(index)/8*TAU
		hit=_raycast64(x+cos(angle)*foot,y+up,z+sin(angle)*foot,0,-1,0,up+down,_ring_ray,skip_grates)
		if not hit.hit or hit.normal64[1]<WALKABLE:continue
		if hit.position64[1]>best_y:best_y=hit.position64[1];best_index=index;_fill_ground(out,hit,false)
	out.hit=have_center or best_index>=0
	return out

func _fill_ground(out:GroundHit,hit:Hit,center:bool) -> void:
	out.y=hit.position64[1];out.normal=hit.normal;out.block=hit.block;out.face=hit.face;out.u=hit.u;out.v=hit.v
	for axis in 3:out.normal64[axis]=hit.normal64[axis]
	out.center=center;out.grate=hit.block>=0 and bool(blocks[hit.block].grate)

func closest_on_block(block:Dictionary,point:Vector3) -> Vector3:
	_closest64(int(block.id),point.x,point.y,point.z)
	return Vector3(_closest[0],_closest[1],_closest[2])

func point_inside(point:Vector3,pad:float=0.0,exclude:int=-1) -> bool:
	for id in queries.query_blocks(point.x-.01,point.z-.01,point.x+.01,point.z+.01):
		if id==exclude or not bool(blocks[id].solid):continue
		var b:PackedFloat64Array=_boxes[id]
		var x:float=point.x-b[0];var y:float=point.y-b[1];var z:float=point.z-b[2]
		var inside:bool=true
		for axis in 3:
			var offset:int=6+axis*3
			if absf(x*b[offset]+y*b[offset+1]+z*b[offset+2])>=b[3+axis]+pad:inside=false;break
		if inside:return true
	return false

func _closest64(id:int,x:float,y:float,z:float) -> void:
	var b:PackedFloat64Array=_boxes[id]
	var rx:float=x-b[0];var ry:float=y-b[1];var rz:float=z-b[2]
	var px:float=b[0];var py:float=b[1];var pz:float=b[2]
	for axis in 3:
		var offset:int=6+axis*3
		var d:float=clampf(rx*b[offset]+ry*b[offset+1]+rz*b[offset+2],-b[3+axis],b[3+axis])
		px+=b[offset]*d;py+=b[offset+1]*d;pz+=b[offset+2]*d
	_closest[0]=px;_closest[1]=py;_closest[2]=pz

func _segment_y64(id:int,x:float,y:float,z:float,bottom:float,top:float) -> float:
	var begin:float=y+bottom;var segment:float=(y+top)-begin
	var length_squared:float=maxf(.000001,segment*segment)
	var t:float=.5
	for iteration in 3:
		_closest64(id,x,begin+segment*t,z)
		t=clampf((_closest[1]-begin)*segment/length_squared,0,1)
	return begin+segment*t

func collide_body(position:Vector3,radius:float,lift:float,height:float,out:Contacts=null,horizontal:bool=false,skip_grates:bool=false,iterations:int=3) -> Contacts:
	if not out:out=Contacts.new()
	out.ground=false;out.wall=false;out.ceiling=false;out.ground_normal=Vector3.UP;out.wall_normal=Vector3.ZERO;out.ground_block=-1;out.wall_block=-1
	var bottom:float=lift+radius;var top:float=maxf(bottom,height-radius)
	var px:float=position.x;var py:float=position.y;var pz:float=position.z
	for iteration in iterations:
		var ids:PackedInt32Array=queries.query_blocks(px-radius-.2,pz-radius-.2,px+radius+.2,pz+radius+.2)
		var moved:bool=false
		for id in ids:
			var block:Dictionary=blocks[id]
			if not bool(block.solid) or (skip_grates and bool(block.grate)):continue
			if py+height<_min_y[id]-.05 or py+lift>_max_y[id]+.05:continue
			var sy:float=_segment_y64(id,px,py,pz,bottom,top)
			_closest64(id,px,sy,pz)
			var nx:float=px-_closest[0];var ny:float=sy-_closest[1];var nz:float=pz-_closest[2]
			var distance:float=sqrt(nx*nx+ny*ny+nz*nz);var penetration:float=0
			if distance>.00001:
				if distance>=radius:continue
				var inverse:float=1.0/distance
				nx*=inverse;ny*=inverse;nz*=inverse;penetration=radius-distance
			else:
				var b:PackedFloat64Array=_boxes[id]
				var rx:float=px-b[0];var ry:float=sy-b[1];var rz:float=pz-b[2]
				var best_penetration:float=INF
				for axis in 3:
					var offset:int=6+axis*3
					var d:float=rx*b[offset]+ry*b[offset+1]+rz*b[offset+2];var depth:float=b[3+axis]-absf(d)
					if depth<best_penetration:
						best_penetration=depth
						var sign:float=1 if d>=0 else -1
						nx=b[offset]*sign;ny=b[offset+1]*sign;nz=b[offset+2]*sign
				penetration=best_penetration+radius
			var length_horizontal:float=sqrt(nx*nx+nz*nz)
			if horizontal and length_horizontal>.3 and ny> -.6:
				var push:float=minf(.45,penetration/length_horizontal)+.0001
				px+=nx/length_horizontal*push;pz+=nz/length_horizontal*push
				out.wall=true;out.wall_normal=Vector3(nx/length_horizontal,0,nz/length_horizontal);out.wall_block=id
			else:
				px+=nx*(penetration+.0001);py+=ny*(penetration+.0001);pz+=nz*(penetration+.0001)
				if ny>.6:out.ground=true;out.ground_normal=Vector3(nx,ny,nz);out.ground_block=id
				elif ny< -.6:out.ceiling=true
				elif absf(ny)<.6:out.wall=true;out.wall_normal=Vector3(nx,ny,nz);out.wall_block=id
			moved=true
		if not moved:break
	out.position=Vector3(px,py,pz);out.position64[0]=px;out.position64[1]=py;out.position64[2]=pz
	return out

func body_fits(position:Vector3,radius:float,lift:float,height:float,skip_grates:bool=false,margin:float=.01) -> bool:
	var bottom:float=lift+radius;var top:float=maxf(bottom,height-radius)
	for id in queries.query_blocks(position.x-radius-.1,position.z-radius-.1,position.x+radius+.1,position.z+radius+.1):
		var block:Dictionary=blocks[id]
		if not bool(block.solid) or (skip_grates and bool(block.grate)):continue
		if position.y+height<_min_y[id] or position.y+lift>_max_y[id]:continue
		var sy:float=_segment_y64(id,position.x,position.y,position.z,bottom,top)
		_closest64(id,position.x,sy,position.z)
		var dx:float=position.x-_closest[0];var dy:float=sy-_closest[1];var dz:float=position.z-_closest[2]
		if dx*dx+dy*dy+dz*dz<(radius-margin)*(radius-margin):return false
	return true

func rail_feet(position:Vector3,foot_radius:float,ground:GroundHit,low:float,high:float) -> void:
	_rail_feet64(position.x,position.y,position.z,foot_radius,ground,low,high)

func _rail_feet64(x:float,_y:float,z:float,foot_radius:float,ground:GroundHit,low:float,high:float) -> void:
	var best_block:int=-1;var best_y:float=ground.y+.001 if ground.hit else -INF
	for id in queries.query_blocks(x-foot_radius-.05,z-foot_radius-.05,x+foot_radius+.05,z+foot_radius+.05):
		var block:Dictionary=blocks[id]
		var b:PackedFloat64Array=_boxes[id]
		if not bool(block.get("rail",false)) or not bool(block.solid) or b[10]<.999:continue
		var top:float=b[1]+b[4]
		if top<low or top>high or top<=best_y:continue
		var rx:float=x-b[0];var rz:float=z-b[2]
		var dx:float=maxf(0,absf(rx*b[6]+rz*b[8])-b[3])
		var dz:float=maxf(0,absf(rx*b[12]+rz*b[14])-b[5])
		if dx*dx+dz*dz>foot_radius*foot_radius:continue
		best_block=id;best_y=top
	if best_block<0:return
	ground.hit=true;ground.y=best_y;ground.normal=Vector3.UP;ground.block=best_block;ground.face=-1;ground.u=0;ground.v=0;ground.center=false;ground.grate=true
	ground.normal64[0]=0;ground.normal64[1]=1;ground.normal64[2]=0

func rail_center(position:Vector3,movement:Vector3,block_id:int,dt:float) -> Vector3:
	var block:Dictionary=blocks[block_id]
	var along_x:bool=float(block.half.x)>=float(block.half.z)
	var axis:Vector3=block.axes[2] if along_x else block.axes[0]
	var half:float=float(block.half.z) if along_x else float(block.half.x)
	var offset:float=(position.x-float(block.center.x))*axis.x+(position.z-float(block.center.z))*axis.z
	var distance:float=absf(offset)-maxf(0,half-.02)
	if distance<=0:return position
	var sign:float=signf(offset)
	if (movement.x*axis.x+movement.z*axis.z)*sign>.25:return position
	var correction:float=minf(distance,1.1*dt)*sign
	position.x-=axis.x*correction;position.z-=axis.z*correction
	return position

func roof_slide(motion:Motion,block_id:int,dt:float) -> void:
	var block:Dictionary=blocks[block_id]
	var normal:Vector3=block.axes[1]
	if motion.roof_direction.length_squared()==0 or motion.roof_time==0:
		motion.roof_stall=0;motion.roof_position=motion.position
		if normal.y<.995:motion.roof_direction=Vector3(normal.x,0,normal.z).normalized()
		else:
			var ax:Vector3=block.axes[0];var az:Vector3=block.axes[2]
			var relative:Vector3=motion.position-Vector3(block.center)
			var x:float=relative.x*ax.x+relative.z*ax.z;var z:float=relative.x*az.x+relative.z*az.z
			var use_x:bool=float(block.half.x)-absf(x)<float(block.half.z)-absf(z)
			var chosen:Vector3=ax if use_x else az
			var side:float=signf(x if use_x else z)
			if side==0:side=1
			motion.roof_direction=Vector3(chosen.x*side,0,chosen.z*side)
	motion.roof_time+=dt
	var delta:Vector3=motion.position-motion.roof_position
	var moved:float=delta.x*motion.roof_direction.x+delta.z*motion.roof_direction.z
	motion.roof_position=motion.position
	motion.roof_stall=motion.roof_stall+dt if motion.roof_time>.1 and moved<.3*dt else 0.0
	if motion.roof_stall>.25:
		motion.roof_direction=Vector3(-motion.roof_direction.z,0,motion.roof_direction.x);motion.roof_stall=0
	var wanted:float=minf(9,3+14*motion.roof_time)
	var along:float=motion.velocity.x*motion.roof_direction.x+motion.velocity.z*motion.roof_direction.z
	if along<wanted:motion.velocity+=motion.roof_direction*(wanted-along)

func integrate(motion:Motion,dt:float,is_squid:bool,jumped:bool=false,climbing:bool=false,movement:Vector3=Vector3.ZERO) -> Motion:
	motion.landed=false;motion.land_speed=0
	if climbing:
		motion.position+=motion.velocity*dt
		collide_body(motion.position,Rules.player("radius",.38),Rules.player("squidBodyLift",.16),Rules.player("squidHeight",.55),motion.contacts,false,true)
		motion.position=motion.contacts.position
		if motion.contacts.ceiling and motion.velocity.y>0:motion.velocity.y=0
		motion.grounded=false;motion.air_time=0
		return motion
	var stick:bool=motion.grounded and not jumped
	var block_id:int=motion.ground.block if stick and motion.ground.hit else -1
	if block_id>=0 and bool(blocks[block_id].get("roof",false)):roof_slide(motion,block_id,dt)
	elif motion.roof_time>0:motion.roof_time=0;motion.roof_direction=Vector3.ZERO
	if block_id>=0 and bool(blocks[block_id].get("rail",false)) and not is_squid:motion.position=rail_center(motion.position,movement,block_id,dt)
	if stick:
		var normal:Vector3=motion.ground.normal
		motion.velocity.y=-(motion.velocity.x*normal.x+motion.velocity.z*normal.z)/maxf(.35,normal.y)
	else:
		var gravity:float=Rules.player("gravity",25)
		if motion.velocity.y<0:gravity*=Rules.player("fallGravityMul",1.2)
		if absf(motion.velocity.y)<Rules.player("apexBand",1.6):gravity*=Rules.player("apexGravityMul",.82)
		motion.velocity.y=maxf(-Rules.player("maxFall",40),motion.velocity.y-gravity*dt)
	var previous_y:float=motion.position.y
	motion.position+=motion.velocity*dt
	resolve(motion.position,motion.velocity,is_squid,previous_y,stick,motion.grounded,motion.smooth_y,motion)
	motion.air_time=0 if motion.grounded else motion.air_time+1.0/60.0
	return motion

func resolve(position:Vector3,velocity:Vector3,is_squid:bool,previous_y:float,stick:bool,was_grounded:bool,smooth_y:float=0,out:Motion=null) -> Motion:
	if not out:out=Motion.new()
	var lift:float=Rules.player("squidBodyLift",.16) if is_squid else Rules.player("stepUp",.35)
	var height:float=Rules.player("squidHeight",.55) if is_squid else Rules.player("height",1.45)
	var contacts:Contacts=collide_body(position,Rules.player("radius",.38),lift,height,out.contacts,stick,is_squid)
	position=contacts.position
	var px:float=contacts.position64[0];var py:float=contacts.position64[1];var pz:float=contacts.position64[2]
	if contacts.ceiling and velocity.y>0:velocity.y=0
	if contacts.wall:
		var normal:Vector3=contacts.wall_normal
		var inward:float=velocity.x*normal.x+velocity.z*normal.z
		if inward<0:velocity.x-=normal.x*inward;velocity.z-=normal.z*inward
	var up:float=Rules.player("squidStepUp",.24) if is_squid else Rules.player("stepUp",.35)
	var grounded:bool=false
	if stick:
		_ground_probe64(px,py,pz,up,Rules.player("stepDown",.45),Rules.player("footRadius",.24),out.ground,is_squid)
		if not is_squid:_rail_feet64(px,py,pz,Rules.player("footRadius",.24),out.ground,py-Rules.player("stepDown",.45),py+up)
		if out.ground.hit:
			var dy:float=out.ground.y-py
			position.y=out.ground.y;grounded=true
			if absf(dy)>.06:smooth_y-=dy
	elif velocity.y<=.5:
		var top:float=maxf(previous_y,py)
		var assist:float=Rules.player("squidStepUp",.24) if is_squid else Rules.player("ledgeAssist",.35)
		_ground_probe64(px,py,pz,(top-py)+assist,.02,Rules.player("footRadius",.24),out.ground,is_squid)
		if not is_squid:_rail_feet64(px,py,pz,Rules.player("footRadius",.24),out.ground,py-.02,top+assist)
		if out.ground.hit and out.ground.y>=py-.02 and (velocity.y<=0 or out.ground.y-py<.02):
			var pop:float=out.ground.y-previous_y
			position.y=out.ground.y;grounded=true
			if pop>.035:smooth_y-=pop
	out.landed=grounded and not was_grounded
	out.land_speed=maxf(0,-velocity.y) if out.landed else 0
	if grounded:velocity.y=0
	out.position=position;out.velocity=velocity;out.grounded=grounded;out.smooth_y=smooth_y
	return out
