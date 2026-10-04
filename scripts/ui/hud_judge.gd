class_name SplatHudJudge
extends SplatLabCanvas
signal finished(winner:int)
const C=preload("res://scripts/ui/lab_canvas.gd")
var elapsed:float=0
var pa:float=50
var pb:float=50
var share:float=.5
var winner:int=0
var bar_a:Control
var bar_b:Control
var num_a:Label
var num_b:Label
var title:Label
var win:Control
var track:Control
var w:float=86
var _from:Vector2=Vector2(.43,.43)
var _revealed:bool=false

func build(data:Dictionary)->void:
	var percents:Array=data.get("percents",[50,50]) as Array
	pa=float(percents[0]);pb=float(percents[1])
	if pa<=1.0001 and pb<=1.0001:pa*=100;pb*=100
	share=pa/(pa+pb) if pa+pb>0 else .5
	winner=-1 if absf(pa-pb)<.05 else 0 if pa>pb else 1
	var colors:Array=data.get("colors",[SplatUiTheme.ORANGE,SplatUiTheme.BLUE]) as Array
	var ca:Color=colors[0] if colors[0] is Color else Color(str(colors[0]));var cb:Color=colors[1] if colors[1] is Color else Color(str(colors[1]))
	var names:Array=data.get("names",["Tangerine","Cobalt"]) as Array
	var bg:=ColorRect.new();canvas.add_child(bg);C.at(bg,0,0,width_u,height_u);bg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var material:=ShaderMaterial.new();material.shader=preload("res://assets/ui/lab_judge.gdshader");bg.material=material
	title=C.label(canvas,"JUDGING •••",width_u*.5-25,height_u*.2,50,6,4.6,true);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	w=width_u*.86
	var x:float=width_u*.07
	var y:float=height_u*.52-7
	C.panel(canvas,x,y,16,2.8,ca,.4);C.label(canvas,str(names[0]).to_upper(),x+.8,y+.15,14.4,2.5,1.4,false,SplatUiTheme.INK)
	C.panel(canvas,x+w-16,y,16,2.8,cb,.4);C.label(canvas,str(names[1]).to_upper(),x+w-15.2,y+.15,14.4,2.5,1.4)
	num_a=C.label(canvas,"0.0%",x+17.2,y-2.1,27,7.1,5.6,true)
	num_b=C.label(canvas,"0.0%",x+w-44.2,y-2.1,27,7.1,5.6,true);num_b.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	track=C.panel(canvas,x,y+6.2,w,7,Color(1,1,1,.08),3.5)
	(track.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(track.material as ShaderMaterial).set_shader_parameter("border",3)
	bar_a=C.panel(track,0,0,w,7,ca,3.5)
	bar_b=C.panel(track,0,0,w,7,cb,3.5)
	set_bars(0,0)
	win=Control.new();canvas.add_child(win);C.at(win,width_u*(.3 if winner==0 else .7 if winner==1 else .5)-30,height_u*.75-3.5,60,7)
	C.icon(win,"splat",16.5,-8.7,27,27).modulate=cb if winner==1 else ca
	var label:Label=C.label(win,"IT’S A TIE!" if winner<0 else str(names[winner]).to_upper()+" WINS!",0,0,60,7,4.4,true);label.rotation=deg_to_rad(-5)
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;win.modulate.a=0

func set_bars(a:float,b:float)->void:
	bar_a.size.x=w*a*12.8;bar_b.size.x=w*b*12.8;bar_b.position.x=w*12.8-bar_b.size.x
	for face:Control in [bar_a,bar_b]:(face.material as ShaderMaterial).set_shader_parameter("panel_size",face.size)

func _process(delta:float)->void:
	elapsed+=delta
	if elapsed<.8:return
	if elapsed<3.45:
		var k:float=1-pow(1-clampf((elapsed-.8)/1.5,0,1),3)
		var jitter:float=sin(elapsed*38)*.006+sin(elapsed*23)*.004 if elapsed>2.3 else 0
		_from=Vector2(.43*k+jitter,.43*k-jitter);set_bars(_from.x,_from.y)
		num_a.text="??.?%" if elapsed>2.3 else "%.1f%%"%(10+fposmod(elapsed*333,60))
		num_b.text="??.?%" if elapsed>2.3 else "%.1f%%"%(10+fposmod(elapsed*271,60))
		return
	var rk:float=clampf((elapsed-3.45)/.55,0,1)
	var back:float=1+(2.2+1)*pow(rk-1,3)+2.2*pow(rk-1,2)
	set_bars(lerpf(_from.x,share,back),lerpf(_from.y,1-share,back))
	var nk:float=1-pow(1-clampf((elapsed-3.45)/.45,0,1),3)
	num_a.text="%.1f%%"%(pa*nk);num_b.text="%.1f%%"%(pb*nk)
	if not _revealed and elapsed>3.75:
		_revealed=true;title.hide();win.modulate.a=1;win.scale=Vector2.ONE*2.3;win.pivot_offset=win.size*.5
		create_tween().tween_property(win,"scale",Vector2.ONE,.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if elapsed>5.1:
		set_process(false);finished.emit(winner)
		var fade:Tween=create_tween();fade.tween_property(self,"modulate:a",0.0,.65);fade.tween_callback(queue_free)
