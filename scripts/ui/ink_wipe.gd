class_name SplatInkWipe
extends Control
## Source menu-art.js InkWipe: the same wave, tongue geometry and 380 / 500 / 1000 ms timeline.
signal finished
var running:bool=false
var mode:String="full"
var direction:int=1
var clock:float=0
var a:Color=SplatUiTheme.ORANGE
var b:Color=SplatUiTheme.BLUE
var _mid:Callable
var _mid_done:bool=false
var _rng:=RandomNumberGenerator.new()
var _ph:Array[Vector3]=[]
var _down:Array=[]
var _up:Array=[]
var _lead:Array=[]
var _tail:Array=[]
var _drops:Array[Dictionary]=[]
var _residue:Array[Dictionary]=[]
var _splats:Array[Dictionary]=[]
var _dots:Texture2D
var _squid:Texture2D=preload("res://assets/ui/source/squid_white.svg")
var _splat:Texture2D=preload("res://assets/ui/source/banner_go.svg")

func _ready()->void:
	z_index=60;mouse_filter=Control.MOUSE_FILTER_IGNORE
	texture_repeat=CanvasItem.TEXTURE_REPEAT_ENABLED
	var image:=Image.new();image.load_svg_from_string('<svg xmlns="http://www.w3.org/2000/svg" width="16" height="16"><circle cx="8" cy="8" r="1.9" fill="white"/></svg>');_dots=ImageTexture.create_from_image(image)
	hide();set_process(false)

func run(type:String="full",dir:int=1,first:Color=SplatUiTheme.ORANGE,second:Color=SplatUiTheme.BLUE,on_mid:Callable=Callable())->void:
	if running:cancel()
	mode=type;direction=-1 if dir<0 else 1;a=first;b=second;_mid=on_mid;_mid_done=not on_mid.is_valid();clock=0;running=true
	_rng.randomize();_ph=[]
	for index:int in 2:_ph.append(Vector3(_r()*TAU,_r()*TAU,_r()*TAU))
	_down=[_drips(10,1),_drips(8,1.25)];_up=[_drips(8,1.1),_drips(6,.9)]
	_lead=[_tongues(7,1),_tongues(6,1.2)];_tail=[_tongues(6,1.3),[]]
	_drops=[];_residue=[];_splats=[]
	for index:int in (16 if mode=="light" else 30):
		_drops.append({"x":_r()*size.x,"y":_r()*size.y,"p":.1+_r()*.6 if mode=="light" else .06+_r()*.62,"vx":1.6+_r()*1.6 if mode=="light" else (_r()-.5)*.35,"vy":(_r()-.5)*.5 if mode=="light" else 1.1+_r()*1.5,"r":size.y*(.004+_r()*(.008 if mode=="light" else .01)),"team":0 if _r()<.72 else 1})
	for index:int in 12:_residue.append({"x":_r()*size.x,"y":size.y*(.05+_r()*.85),"r":size.y*(.006+_r()*.014),"on":-1.0})
	for index:int in 6:_splats.append({"x":size.x*(.08+((index+_r()*.8)/6)*.84),"y":size.y*(.28+_r()*.62),"s":size.y*(.04+_r()*.07),"rot":_r()*TAU,"team":0 if _r()<.6 else 1,"on":-1.0})
	if mode=="light" and not _mid_done:_mid_done=true;_mid.call()
	show();set_process(true);queue_redraw()

func cancel()->void:
	if not running:return
	running=false
	if not _mid_done and _mid.is_valid():_mid_done=true;_mid.call()
	hide();set_process(false);finished.emit()

func pending_swap()->bool:return running and not _mid_done
func abort()->void:
	# Engine-driven match entry supersedes a queued menu swap. It must not flush that old callback.
	running=false;_mid=Callable();_mid_done=true;hide();set_process(false)

func _process(delta:float)->void:
	clock+=minf(.05,delta)*1000.0
	if clock>=380 and not _mid_done:_mid_done=true;_mid.call()
	if clock>=(520 if mode=="light" else 900 if mode=="fade" else 1000):cancel();return
	queue_redraw()

func _r()->float:return _rng.randf()
func _ease(value:float)->float:
	var p:float=clampf(value,0,1);return 4*p*p*p if p<.5 else 1-pow(-2*p+2,3)*.5
func _smooth(low:float,high:float,value:float)->float:
	var p:float=clampf((value-low)/maxf(.0001,high-low),0,1);return p*p*(3-2*p)
func _drips(count:int,length:float)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for index:int in count:
		var w:float=size.x*(.012+_r()*.013)
		result.append({"x":((index+.15+_r()*.7)/count)*size.x,"w":w,"length":size.y*(.05+_r()*.15)*length,"delay":_r()*.35,"wob":_r()*TAU,"bulb":w*(.5+_r()*.22)})
	return result
func _tongues(count:int,length:float)->Array[Dictionary]:
	var result:Array[Dictionary]=[]
	for index:int in count:
		var w:float=size.y*(.014+_r()*.014)
		result.append({"y":((index+.2+_r()*.6)/count)*size.y,"w":w,"length":size.x*(.03+_r()*.07)*length,"bulb":w*(.5+_r()*.2)})
	return result
func _edge(x:float,base:float,phase:Vector3)->float:
	var k:float=x/maxf(1,size.x)
	return base+size.y*(.021*sin(k*6.3+phase.x+clock*.0058)+.013*sin(k*14.1+phase.y-clock*.0087)+.006*sin(k*29.7+phase.z+clock*.0125))
func _side(y:float,center:float,offset:float,phase:Vector3)->float:
	var k:float=y/maxf(1,size.y)
	return center+offset+(k-.5)*size.y*.28*direction+size.y*(.018*sin(k*7+phase.x+clock*.009)+.01*sin(k*17+phase.y-clock*.014))

func _bezier(points:PackedVector2Array,start:Vector2,c1:Vector2,c2:Vector2,end:Vector2)->PackedVector2Array:
	for index:int in range(1,11):
		var t:float=index/10.0;var q:float=1-t
		points.append(start*q*q*q+c1*3*q*q*t+c2*3*q*t*t+end*t*t*t)
	return points
func _arc(points:PackedVector2Array,center:Vector2,radius:float,start:float,end:float)->PackedVector2Array:
	for index:int in 15:points.append(center+Vector2.from_angle(lerpf(start,end,index/14.0))*radius)
	return points
func _down_tongue(x:float,y:float,w:float,length:float,bulb:float)->PackedVector2Array:
	var tip:float=y+length;var points:=PackedVector2Array([Vector2(x+w,y-3)])
	points=_bezier(points,points[-1],Vector2(x+w*.32,y+length*.14),Vector2(x+bulb*.85,tip-length*.55),Vector2(x+bulb*.7,tip-bulb*.45))
	points=_arc(points,Vector2(x,tip-bulb*.2),bulb,-.25,PI+.25)
	return _bezier(points,points[-1],Vector2(x-bulb*.85,tip-length*.55),Vector2(x-w*.32,y+length*.14),Vector2(x-w,y-3))
func _up_tongue(x:float,y:float,w:float,length:float,bulb:float)->PackedVector2Array:
	var tip:float=y-length;var points:=PackedVector2Array([Vector2(x-w,y+3)])
	points=_bezier(points,points[-1],Vector2(x-w*.3,y-length*.16),Vector2(x-bulb,tip+length*.42),Vector2(x-bulb,tip+bulb*.35))
	points=_arc(points,Vector2(x,tip+bulb*.35),bulb,PI,TAU)
	return _bezier(points,points[-1],Vector2(x+bulb,tip+length*.42),Vector2(x+w*.3,y-length*.16),Vector2(x+w,y+3))
func _side_tongue(x:float,y:float,w:float,length:float,bulb:float,dir:int)->PackedVector2Array:
	var tip:float=x+length*dir;var points:=PackedVector2Array([Vector2(x-3*dir,y-w)])
	points=_bezier(points,points[-1],Vector2(x+length*.16*dir,y-w*.3),Vector2(tip-length*.42*dir,y-bulb),Vector2(tip-bulb*.35*dir,y-bulb))
	points=_arc(points,Vector2(tip-bulb*.35*dir,y),bulb,-PI*.5,PI*.5 if dir>0 else -PI*1.5)
	return _bezier(points,points[-1],Vector2(tip-length*.42*dir,y+bulb),Vector2(x+length*.16*dir,y+w*.3),Vector2(x-3*dir,y+w))

func _union(points:PackedVector2Array,tongue:PackedVector2Array)->PackedVector2Array:
	var result:Array[PackedVector2Array]=Geometry2D.merge_polygons(points,tongue)
	return result[0] if result.size()==1 else points
func _paint(points:PackedVector2Array,color:Color,pattern:bool=false,width:float=6)->void:
	if points.size()<3:return
	# Canvas Path2D permits self-crossing contours. Clip to the visible rectangle to resolve
	# those into simple rings before the Godot polygon tessellator sees them.
	var bounds:=PackedVector2Array([Vector2(-8,-8),Vector2(size.x+8,-8),size+Vector2(8,8),Vector2(-8,size.y+8)])
	var contours:Array[PackedVector2Array]=Geometry2D.intersect_polygons(points,bounds)
	for contour:PackedVector2Array in contours:_paint_simple(contour,color,pattern,width)
func _paint_simple(points:PackedVector2Array,color:Color,pattern:bool,width:float)->void:
	if Geometry2D.triangulate_polygon(points).is_empty():return
	var outline:PackedVector2Array=points.duplicate();outline.append(outline[0])
	draw_polyline(outline,color.darkened(.4),width,true);draw_colored_polygon(points,color)
	if pattern:
		var uv:=PackedVector2Array()
		for p:Vector2 in points:uv.append(p/16)
		draw_colored_polygon(points,Color(1,1,1,.13),uv,_dots)
func _sheet(base:float,phase:Vector3,tongues:Array,color:Color,progress:float,up:bool=false,pattern:bool=false)->void:
	var points:=PackedVector2Array([Vector2(-40,size.y*2 if up else -size.y),Vector2(size.x+40,size.y*2 if up else -size.y)])
	var step:float=maxf(10,size.x/120);var x:float=size.x+40
	while x>=-40-step:points.append(Vector2(x,_edge(x,base,phase)));x-=step
	for drip:Dictionary in tongues:
		var grow:float=_smooth(0,.14,progress)*(1-_smooth(.5,1,progress))*(1+.1*sin(clock*.02+float(drip.wob))) if up else _smooth(float(drip.delay),float(drip.delay)+.45,progress)*(1+.07*sin(clock*.021+float(drip.wob)))
		var length:float=float(drip.length)*grow
		if length<maxf(3,float(drip.bulb)*1.5):continue
		var tongue:PackedVector2Array=_up_tongue(float(drip.x),_edge(float(drip.x),base,phase),float(drip.w)*.8,length,float(drip.bulb)*.62) if up else _down_tongue(float(drip.x),_edge(float(drip.x),base,phase),float(drip.w),length,float(drip.bulb)*(.9+.1*sin(clock*.02+float(drip.wob))))
		points=_union(points,tongue)
	_paint(points,color,pattern)
func _gloss(base:float,phase:Vector3,up:bool)->void:
	var points:=PackedVector2Array();var step:float=maxf(12,size.x/100);var x:float=-20
	while x<size.x+20+step:points.append(Vector2(x,_edge(x,base,phase)+(1 if up else -1)*size.y*.016));x+=step
	draw_polyline(points,Color(1,1,1,.2),size.y*.007,true)
func _ellipse(point:Vector2,radius:float,stretch:float,rotation:float,color:Color)->void:
	draw_set_transform(point,rotation,Vector2(stretch,1));draw_circle(Vector2.ZERO,radius,color);draw_set_transform(Vector2.ZERO)

func _draw()->void:
	if not running:return
	if mode=="light":_draw_light();return
	if mode=="fade":
		var alpha:float=clock/300 if clock<300 else 1 if clock<500 else 1-(clock-500)/380
		draw_rect(Rect2(Vector2.ZERO,size),Color(a,clampf(alpha,0,1)));return
	_draw_full();_draw_mark()
func _draw_full()->void:
	if clock<=380:
		var p:float=clock/380;var base:float=lerpf(-.3*size.y,1.12*size.y,_ease(p))
		for splat:Dictionary in _splats:
			if float(splat.on)<0 and base+size.y*.34>=float(splat.y):splat.on=clock
			if float(splat.on)<0:continue
			var q:float=clampf((clock-float(splat.on))/110,0,1);var scale:float=1+3.2*pow(q-1,3)+2.2*pow(q-1,2)
			if scale<=0:continue
			draw_set_transform(Vector2(float(splat.x),float(splat.y)),float(splat.rot),Vector2.ONE*float(splat.s)*scale)
			draw_texture_rect(_splat,Rect2(-1.6,-1.6,3.2,3.2),false,a if int(splat.team)==0 else b);draw_set_transform(Vector2.ZERO)
		for drop:Dictionary in _drops:
			var time:float=clock-float(drop.p)*380
			if time<0:continue
			var factor:float=size.y/900;var origin:float=_edge(float(drop.x),lerpf(-.3*size.y,1.12*size.y,_ease(float(drop.p))),_ph[0])+float(drop.r)
			var point:=Vector2(float(drop.x)+float(drop.vx)*time*factor,origin+float(drop.vy)*time*factor+.0016*time*time*factor)
			var speed:float=float(drop.vy)+.0032*time
			if point.y<=size.y+40:_ellipse(point,float(drop.r),1+minf(2.4,speed*.55),atan2(speed,float(drop.vx)),a if int(drop.team)==0 else b)
		_sheet(base+size.y*(.03+.06*sin(p*PI)),_ph[1],_down[1],b,p)
		_sheet(base,_ph[0],_down[0],a,p,false,true);_gloss(base,_ph[0],false)
	elif clock<500:
		draw_rect(Rect2(Vector2.ZERO,size),a);draw_texture_rect(_dots,Rect2(Vector2.ZERO,size),true,Color(1,1,1,.13))
	else:
		var q:float=clampf((clock-500)/460,0,1);var top:float=lerpf(-.16*size.y,1.2*size.y,_ease(q))
		_sheet(top-size.y*(.035+.06*sin(q*PI)),_ph[1],_up[1],b,q,true)
		_sheet(top,_ph[0],_up[0],a,q,true,true);_gloss(top,_ph[0],true)
		for drop:Dictionary in _residue:
			if float(drop.on)<0 and top>float(drop.y)+size.y*.05:drop.on=clock
			if float(drop.on)<0:continue
			var k:float=1-_smooth(0,240,clock-float(drop.on))
			if k>.01:draw_circle(Vector2(float(drop.x),float(drop.y)+(clock-float(drop.on))*.05),float(drop.r)*k,a)
func _draw_light()->void:
	var p:float=clampf(clock/490,0,1);var skew:float=size.y*.28;var center:float=lerpf(-.25*size.x-skew,1.25*size.x+skew,_ease(p))
	if direction<0:center=size.x-center
	var half:float=size.x*.06
	for drop:Dictionary in _drops:
		var time:float=clock-float(drop.p)*520
		if time<0:continue
		var factor:float=size.x/1600;var point:=Vector2(_side(float(drop.y),center,(half+size.x*.02)*direction,_ph[0])+float(drop.vx)*time*factor*direction,float(drop.y)+float(drop.vy)*time*factor+.0012*time*time*factor)
		_ellipse(point,float(drop.r),2.2,0,a if int(drop.team)==0 else b)
	for index:int in [1,0]:
		var offset:float=size.x*.018 if index==1 else 0.0;var lead:float=(half+offset)*direction;var trail:float=(-half+offset)*direction
		var points:=PackedVector2Array();var step:float=maxf(10,size.y/60);var y:float=-40
		while y<size.y+40+step:points.append(Vector2(_side(y,center,lead,_ph[index]),y));y+=step
		y=size.y+40
		while y>-40-step:points.append(Vector2(_side(y,center,trail,_ph[index]),y));y-=step
		for side:int in [1,-1]:
			for tongue:Dictionary in (_lead[index] if side>0 else _tail[index]):
				var length:float=float(tongue.length)*sin(p*PI)
				if length<float(tongue.bulb)*1.5:continue
				var own:PackedVector2Array=_side_tongue(_side(float(tongue.y),center,lead if side>0 else trail,_ph[index]),float(tongue.y),float(tongue.w)*(1 if side>0 else .8),length,float(tongue.bulb)*(1 if side>0 else .7),direction*side)
				points=_union(points,own)
		_paint(points,a if index==0 else b,false,5)
func _draw_mark()->void:
	var p:float=clock/1000;var u:float=minf(size.x/100,size.y/56.25);var scale:float;var alpha:float;var rotation:float
	if p<.3:return
	if p<.4:var k:float=(p-.3)/.1;scale=lerpf(.4,1.12,k);alpha=k;rotation=lerpf(-30,6,k)
	elif p<.48:var k:float=(p-.4)/.08;scale=lerpf(1.12,1,k);alpha=1;rotation=lerpf(6,0,k)
	elif p<.56:scale=1;alpha=1;rotation=0
	elif p<.64:var k:float=(p-.56)/.08;scale=lerpf(1,.85,k);alpha=1-k;rotation=0
	else:return
	draw_set_transform(size*.5+Vector2(0,u*2*_smooth(.56,.64,p)),deg_to_rad(rotation),Vector2.ONE*scale)
	draw_texture_rect(_squid,Rect2(-u*5.5,-u*5.5,u*11,u*11),false,Color(1,1,1,alpha));draw_set_transform(Vector2.ZERO)
	if p>=.36 and p<.62:
		var ring_scale:float=lerpf(.5,1.6,1-pow(1-clampf((p-.36)/.26,0,1),3));var ring_alpha:float=_smooth(.36,.42,p)*(1-_smooth(.42,.62,p))*.85
		draw_arc(size*.5,u*7.48*ring_scale,0,TAU,80,Color(1,1,1,ring_alpha),lerpf(u*.5,1,_smooth(.42,.62,p)),true)
