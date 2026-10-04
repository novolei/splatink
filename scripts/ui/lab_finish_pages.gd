class_name SplatLabFinishPages
extends RefCounted
const C=preload("res://scripts/ui/lab_canvas.gd")
const L=preload("res://scripts/ui/lab_screens.gd")

static func credits(host:InkUI)->void:
	host.content.hide()
	var view:=SplatLabCredits.new();host._margin.add_child(view);view.size=host.get_viewport().get_visible_rect().size;view._layout();view.build(host)

static func results(host:InkUI,stats:Dictionary)->void:
	host.content.hide()
	var view:=SplatLabResults.new();host._margin.add_child(view);view.size=host.get_viewport().get_visible_rect().size;view._layout();view.build(host,stats);host.results_view=view

static func title(host:InkUI)->void:
	var view:SplatLabCanvas=L.canvas(host)
	var root:Control=view.canvas
	var bg:=ColorRect.new();root.add_child(bg);C.at(bg,0,0,view.width_u,view.height_u)
	var material:=ShaderMaterial.new();material.shader=preload("res://assets/ui/lab_loading.gdshader");material.set_shader_parameter("title",true);bg.material=material;bg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	L.logo(root,view.width_u*.5-29.0,view.height_u*.4-7.2,11.5)
	var press:Label=C.label(root,"PRESS ANY KEY",view.width_u*.5-24,view.height_u*.85-5.0,48,4,2.5,true)
	press.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	C.label(root,"OR CLICK TO START",view.width_u*.5-22,view.height_u*.85-.5,44,1.6,.95).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	C.label(root,"INKWAVE · an original turf-war shooter",3.4,view.height_u-2.7,45,1,.7)
	C.label(root,"v1.0.0",view.width_u-8,view.height_u-2.7,4.6,1,.7).horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
	var click:=Button.new();root.add_child(click);C.at(click,0,0,view.width_u,view.height_u)
	for state:String in ["normal","hover","focus","pressed"]:click.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	click.pressed.connect(host.show_menu)
	var pulse:Tween=press.create_tween().set_loops()
	pulse.tween_property(press,"modulate:a",.6,.75).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(press,"modulate:a",1.0,.75).set_trans(Tween.TRANS_SINE)

static func loading(host:InkUI,value:float=0,label:String="MAKING WAVES…")->void:
	var view:SplatLabCanvas=L.canvas(host)
	var root:Control=view.canvas
	var bg:=ColorRect.new();root.add_child(bg);C.at(bg,0,0,view.width_u,view.height_u)
	var material:=ShaderMaterial.new();material.shader=preload("res://assets/ui/lab_loading.gdshader");bg.material=material;bg.mouse_filter=Control.MOUSE_FILTER_IGNORE
	L.logo(root,view.width_u*.5-15.7,view.height_u*.45-10.0,6.2)
	var track:Control=C.panel(root,view.width_u*.5-20.6,view.height_u*.45+3.55,34,2.3,Color("0d0a18"),1.15)
	for edge:Array in [[.45,.45,Color(0,0,0,.4),0.0],[0.0,.45,SplatUiTheme.INK,6.0],[0.0,.235,Color.WHITE,3.0]]:
		C.panel(track,-float(edge[1]),float(edge[0])-float(edge[1]),34+float(edge[1])*2,2.3+float(edge[1])*2,edge[2],1.15+float(edge[1]))
	var fill:=ColorRect.new();track.add_child(fill);C.at(fill,0,0,34,2.3);fill.mouse_filter=Control.MOUSE_FILTER_IGNORE
	var progress:=ShaderMaterial.new();progress.shader=preload("res://assets/ui/lab_progress.gdshader");progress.set_shader_parameter("value",value);fill.material=progress
	C.label(track,"%d%%"%roundi(value*100),35.4,0,5.7,2.3,1.9,true)
	C.label(root,label.to_upper(),view.width_u*.5-25,view.height_u*.45+8.2,50,1.8,1.1).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var tip:Control=C.panel(root,view.width_u*.5-31,view.height_u-9.1,62,3.9,Color(1,1,1,.06),1.4)
	var badge:Control=C.panel(tip,1.4,.85,3.6,2.1,SplatUiTheme.BLUE,.55);badge.rotation=deg_to_rad(-4)
	(badge.material as ShaderMaterial).set_shader_parameter("border_color",SplatUiTheme.INK);(badge.material as ShaderMaterial).set_shader_parameter("border",2.0)
	C.label(badge,"TIP",0,0,3.6,2.1,1.1,false).add_theme_font_override("font",SplatUiTheme.DISPLAY)
	C.label(tip,"Hold",6.1,.65,3.1,2.5,1.1)
	C.keycap(tip,"SHIFT",9.2,.8,.94)
	C.label(tip,"to dive into your ink — you are nearly invisible while swimming.",13.7,.65,46.8,2.5,1.1)
	C.label(root,"v1.0.0",view.width_u-8,view.height_u-2.7,4.6,1,.7)
