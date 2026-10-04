class_name SplatLabToasts
extends SplatLabCanvas
const C=preload("res://scripts/ui/lab_canvas.gd")
var host:InkUI
var stack:Array[Dictionary]=[]

func _ready()->void:
	super._ready();z_index=55;process_mode=Node.PROCESS_MODE_ALWAYS

func add_message(text:String,options:Dictionary={})->void:
	if text.is_empty():return
	var lobby:bool=is_instance_valid(host) and host.page=="lobby"
	var kind:String=str(options.get("kind","info"));var color:Color=options.get("color",Color("e3ff2e"))
	var icon:String=str(options.get("icon",{"error":"close","join":"plus","leave":"exit","good":"check"}.get(kind,"sparkle")))
	if kind=="error":color=Color("ff3d5e")
	elif kind=="good":color=Color("3ddc84")
	elif kind=="leave":color=Color("5a5170")
	var font:Font=preload("res://assets/fonts/ink_body_900_font.tres")
	var fs:float=.8 if lobby else .95
	var width:float=minf(16 if lobby else 34,6.5+font.get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,roundi(fs*12.8)).x/12.8)
	var group:=Control.new();canvas.add_child(group);C.at(group,0,0,width,4.3);group.mouse_filter=Control.MOUSE_FILTER_IGNORE;group.pivot_offset=group.size*.5
	var shadow:Control=C.panel(group,.25,.4,width,4.3,Color("15121c"),1.1)
	var face:Control=C.panel(group,0,0,width,4.3,Color("3a0d1a") if kind=="error" else Color("15121c"),1.1)
	(face.material as ShaderMaterial).set_shader_parameter("border_color",Color.WHITE);(face.material as ShaderMaterial).set_shader_parameter("border",2.0)
	var pattern:TextureRect=C.icon(group,"tex-squids",0,0,width,4.3);pattern.stretch_mode=TextureRect.STRETCH_TILE;pattern.modulate.a=.06
	var badge:Control=C.panel(group,.45,.6,3.1,3.1,color,1.4);badge.rotation=deg_to_rad(-8)
	C.icon(badge,"glyph_"+icon,.55,.55,2,2).modulate=Color.WHITE if kind in ["error","leave"] else Color("15121c")
	var label:Label=C.label(group,text,4.35,.5,width-5.2,3.4,fs);label.add_theme_font_override("font",font);label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	group.rotation=deg_to_rad(1.2 if stack.size()%2==1 else -1.4)
	stack.append({"node":group,"life":float(options.get("ms",3400))/1000.0,"out":false,"lobby":lobby})
	while stack.size()>(2 if lobby else 3):
		var old:Dictionary=stack.pop_front();(old.node as Control).queue_free()
	_reflow()
	var target:Vector2=group.position;group.position=target+Vector2(0,-2.5*12.8) if lobby else target+Vector2(4*12.8,0);group.modulate.a=0;group.scale=Vector2.ONE*.7
	var tween:Tween=group.create_tween().set_parallel(true);tween.tween_property(group,"position",target,.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);tween.tween_property(group,"scale",Vector2.ONE,.55).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT);tween.tween_property(group,"modulate:a",1,.2)

func _reflow()->void:
	for index:int in stack.size():
		var row:Dictionary=stack[index];var node:Control=row.node as Control
		var x:float=61-node.size.x/25.6 if bool(row.lobby) else width_u-3.4-node.size.x/12.8
		C.at(node,x,(2.8 if bool(row.lobby) else 11.4)+index*5.2,node.size.x/12.8,node.size.y/12.8)

func _process(delta:float)->void:
	for index:int in range(stack.size()-1,-1,-1):
		var row:Dictionary=stack[index];row.life=float(row.life)-delta
		if float(row.life)<=0 and not bool(row.out):
			row.out=true
			var node:Control=row.node as Control;var tween:Tween=node.create_tween().set_parallel(true)
			tween.tween_property(node,"modulate:a",0,.38);tween.tween_property(node,"scale",Vector2.ONE*.9,.38)
			tween.tween_property(node,"position",node.position+Vector2(0,-1.5*12.8) if bool(row.lobby) else node.position+Vector2(3*12.8,0),.38)
		if float(row.life)<-.42:(row.node as Control).queue_free();stack.remove_at(index);_reflow()
