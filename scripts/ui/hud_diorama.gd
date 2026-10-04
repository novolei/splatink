class_name SplatHudDiorama
extends Control
## Production src/ui/diorama.js: projects five pins onto the actual live 3D camera.
## No minimap textures, duplicate world, capture camera or image map exists here.
const C=preload("res://scripts/ui/lab_canvas.gd")
var hud:Control
var game:Node
var view:SplatLabCanvas
var k:float=0
var on:bool=false
var cursor:Vector2=Vector2(.5,.62)
var hover:int=-1
var has_cursor:bool=false
var pins:Array[Dictionary]=[]
var _clock:float=0
var _mouse_delta:Vector2=Vector2.ZERO
var _clicked:bool=false
var _finish:ColorRect
var _copy:BackBufferCopy
var _head:Control
var _title:Label
var _when:Label
var _foot:Control
var _last_stage:String=""
var _arc:PackedVector2Array=PackedVector2Array()
var _color:Color=SplatUiTheme.ORANGE

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	_copy=BackBufferCopy.new();_copy.copy_mode=BackBufferCopy.COPY_MODE_VIEWPORT;add_child(_copy)
	_finish=ColorRect.new();_finish.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_finish)
	var finish_material:=ShaderMaterial.new();finish_material.shader=preload("res://assets/ui/diorama_finish.gdshader");_finish.material=finish_material
	# Arc draws after the finish quad and before all badges.
	var arc:=Control.new();arc.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(arc);arc.set_script(preload("res://scripts/ui/hud_diorama_arc.gd"));arc.set("diorama",self)
	for index:int in 5:_make_pin(index)
	_head=Control.new();_head.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(_head)
	var kicker:Label=C.label(_head,"STAGE MAP",0,0,32,1.1,.95);kicker.add_theme_font_override("font",preload("res://assets/fonts/ink_body_800_font.tres"));kicker.modulate.a=.85
	_title=C.label(_head,"STAGE",0,1.3,58,3.2,3.1,true);_title.rotation=deg_to_rad(-2)
	_when=C.label(_head,"DAY",.8,4.88,5,1.35,.85);_when.add_theme_font_override("font",preload("res://assets/fonts/ink_body_800_font.tres"))
	var plate:Control=C.panel(_head,0,4.7,5.3,1.8,SplatUiTheme.INK,.9);_head.move_child(plate,_when.get_index());_when.z_index=1
	_foot=C.panel(self,0,0,71,3.0,Color(.082,.071,.11,.82),1.5)
	var x:float=1.3
	for key:String in ["1","2","3"]:x+=C.keycap(_foot,key,x,.65,.82)+.35
	C.label(_foot,"Super Jump to a teammate",x,.5,20.1,2,1.02);x+=20.65
	x+=C.keycap(_foot,"4",x,.65,.82)+.35
	C.label(_foot,"Base   ·   Point + click a pin   ·   release",x,.5,28.7,2,1.02);x+=28.9
	C.keycap(_foot,"TAB",x,.65,.82)
	view.layout_changed.connect(_layout)
	_layout();hide()

func configure(owner_hud:Control,controller:Node,canvas:SplatLabCanvas)->void:
	hud=owner_hud;game=controller;view=canvas

func _make_pin(index:int)->void:
	var group:=Control.new();group.mouse_filter=Control.MOUSE_FILTER_IGNORE;add_child(group)
	var face:=ColorRect.new();face.mouse_filter=Control.MOUSE_FILTER_IGNORE;group.add_child(face);C.at(face,-3,-6.75,6,9)
	var material:=ShaderMaterial.new();material.shader=preload("res://assets/ui/diorama_pin.gdshader");material.set_shader_parameter("kind",2.0 if index==4 else 1.0 if index==3 else 0.0);material.set_shader_parameter("draw_ground",false);face.material=material
	var s:float=3.3 if index==4 else 2.5 if index==3 else 2.9
	var icon:TextureRect=C.icon(group,"diorama_self" if index==4 else "diorama_home" if index==3 else "weaponw_shooter",-s*.35,-2.2-s*.85,s*.7,s*.7);icon.pivot_offset=icon.size*.5
	var name:Label=C.label(group,"YOU" if index==4 else "BASE" if index==3 else "",-15,-2.2-s-1.45,30,1.2,.95);name.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;name.clip_text=false;name.add_theme_font_override("font",preload("res://assets/fonts/ink_body_800_font.tres"));name.add_theme_constant_override("outline_size",3)
	var state:Label=C.label(group,"",-2,-2.2-s*.5-.75,4,1.5,1.3);state.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;state.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"));state.add_theme_constant_override("outline_size",3)
	var key:Control=Control.new();group.add_child(key);C.at(key,s*.34,-2.2-s*.62-1.58,3,2)
	if index<4:C.keycap(key,str(index+1),0,0,.9)
	pins.append({"group":group,"face":face,"material":material,"icon":icon,"name":name,"state":state,"target":null,"position":Vector2.ZERO,"display":Vector2.ZERO,"label_width":0.0,"visible":false,"ok":false,"weapon":"shooter","flash":0.0,"size":s})

func _layout()->void:
	if view==null:return
	C.at(self,0,0,view.width_u,view.height_u)
	C.at(_finish,0,0,view.width_u,view.height_u)
	C.at(_head,2.6,7.6,60,7)
	C.at(_foot,(view.width_u-71)*.5,view.height_u-5.2,71,3)
	(_foot.material as ShaderMaterial).set_shader_parameter("panel_size",_foot.size)

func cursor_vector()->Vector2:
	return Vector2((cursor.x-.5)*2.0,(cursor.y-.55)*2.0) if on else Vector2.ZERO

func _process(dt:float)->void:
	_clock+=dt
	if not is_instance_valid(game) or not is_instance_valid(game.get("camera_rig")):return
	k=float(game.get("camera_rig").get("map_k"))
	var active:bool=k>.002 and hud.is_visible_in_tree() and game.get("local_player")!=null
	if active!=on:
		on=active;visible=on;_copy.visible=on
		if on:cursor=Vector2(.5,.62);hover=-1;_head_text();_sound("ui_toggle",.4)
	if not on:_mouse_delta=Vector2.ZERO;_clicked=false;return
	var alpha:float=smoothstep(.3,.95,k);var pin_k:float=smoothstep(.62,1.0,k)
	(_finish.material as ShaderMaterial).set_shader_parameter("fade",alpha)
	(_finish.material as ShaderMaterial).set_shader_parameter("blur_enabled",str(game.settings.get("quality","high"))!="low")
	_head.modulate.a=pin_k;_head.position.y=(7.6*12.8)-(1-pin_k)*12;_foot.modulate.a=pin_k;_foot.position.y=(view.height_u-5.2)*12.8+(1-pin_k)*14
	_color=game.team_colors[game.local_player.team_id]
	var can_jump:bool=game.local_player.can_super_jump()
	_project(can_jump,pin_k,alpha,dt)
	_cursor_update(dt)
	if _clicked and k>.7 and hover>=0:_jump(hover)
	_clicked=false;_mouse_delta=Vector2.ZERO
	_arc_update(can_jump)
	get_child(2).queue_redraw()

func _project(can_jump:bool,pin_k:float,alpha:float,dt:float)->void:
	var local:Node3D=game.local_player;var camera:Camera3D=game.camera
	var allies:Array=game.actors.filter(func(actor)->bool:return actor!=local and actor.team_id==local.team_id)
	var display_scale:Vector2=view.canvas.scale
	for index:int in pins.size():
		var pin:Dictionary=pins[index];var target:Node3D=allies[index] if index<3 and index<allies.size() else local if index==4 else null
		var position:Vector3=Vector3.ZERO;var exists:bool=target!=null or index==3
		var dead:bool=false;var available:bool=false;var text:String="";var state:String=""
		if target!=null:
			position=target.visual_position() if index==4 and target.has_method("visual_position") else target.global_position
			dead=not bool(target.alive);available=target.alive and target.super_jump_state.is_empty();text="YOU" if index==4 else str(target.display_name)
			state=str(maxi(1,ceili(float(target.respawn_timer)))) if dead and index<3 else "↑" if index<3 and not target.super_jump_state.is_empty() else ""
		elif index==3:
			position=InkStage.vec3(game.stage.layout.spawnPads[local.team_id]);available=true;text="BASE"
		pin.target=target;pin.ok=available and can_jump and index!=4
		position.y+=.1
		pin.visible=exists and not camera.is_position_behind(position)
		(pin.group as Control).visible=pin.visible
		if not pin.visible:continue
		var point:Vector2=camera.unproject_position(position);pin.position=point;(pin.group as Control).position=point/display_scale;(pin.group as Control).modulate.a=alpha*pin_k
		(pin.name as Label).text=text;(pin.state as Label).text=state
		if index<3 and pin.weapon!=target.weapon_id:pin.weapon=target.weapon_id;(pin.icon as TextureRect).texture=load("res://assets/ui/source/weaponw_%s.svg"%pin.weapon)
		pin.flash=maxf(0,float(pin.flash)-dt)
		var scale_value:float=.4+.6*pin_k
		if hover==index and (pin.ok or index==3):scale_value=1.22
		if pin.flash>0:scale_value*=1.0+.45*sin((1.0-float(pin.flash)/.42)*PI)
		(pin.material as ShaderMaterial).set_shader_parameter("ink",_color);(pin.material as ShaderMaterial).set_shader_parameter("pin_k",pin_k);(pin.material as ShaderMaterial).set_shader_parameter("badge_scale",scale_value);(pin.material as ShaderMaterial).set_shader_parameter("clock",_clock);(pin.material as ShaderMaterial).set_shader_parameter("dead",dead);(pin.material as ShaderMaterial).set_shader_parameter("hover",1.0 if hover==index and (pin.ok or index==3) else 0.0)
		(pin.icon as TextureRect).modulate.a=.35 if dead else 1.0
		(pin.icon as TextureRect).scale=Vector2.ONE*scale_value
		(pin.icon as TextureRect).position.y=-(2.2+float(pin.size)*.5*scale_value+float(pin.size)*.35)*12.8
		if index==4:
			var forward:Vector3=position+Vector3(sin(local.aim_yaw),0,cos(local.aim_yaw))*3
			var delta:Vector2=camera.unproject_position(forward)-point;(pin.icon as TextureRect).rotation=atan2(delta.x,-delta.y)
	_spread()

func _spread()->void:
	# Reuse source hud.js:1210 six-pass repulsion; diorama.js itself had no declutter.
	# Badge/name width extends that source gap. Ground/arc retain actual projections.
	var screen_scale:float=view.canvas.scale.x
	var source_gap:float=12.8*screen_scale*3.4*1.3
	for pin:Dictionary in pins:
		pin.display=pin.position
		var label:Label=pin.name
		pin.label_width=label.get_theme_font("font").get_string_size(label.text,HORIZONTAL_ALIGNMENT_LEFT,-1,label.get_theme_font_size("font_size")).x*screen_scale
	for iteration:int in 6:
		for index:int in pins.size():
			for other:int in range(index+1,pins.size()):
				var a:Dictionary=pins[index];var b:Dictionary=pins[other]
				if not a.visible or not b.visible:continue
				var gap:float=maxf(source_gap,(float(a.label_width)+float(b.label_width))*.5+12.8*screen_scale*.8)
				var delta:Vector2=Vector2(b.display)-Vector2(a.display);var distance:float=delta.length()
				if distance>=gap:continue
				if distance<.5:delta=Vector2.from_angle(index*2.1+other*1.3);distance=1
				var push:Vector2=delta/distance*(gap-distance)*.5
				a.display=Vector2(a.display)-push;b.display=Vector2(b.display)+push
	for pin:Dictionary in pins:
		if pin.visible:(pin.group as Control).position=Vector2(pin.display)/view.canvas.scale

func _cursor_update(dt:float)->void:
	var dimensions:Vector2=get_viewport().get_visible_rect().size
	var stick:Vector2=Vector2.ZERO
	for device:int in Input.get_connected_joypads():stick=Vector2(Input.get_joy_axis(device,JOY_AXIS_RIGHT_X),Input.get_joy_axis(device,JOY_AXIS_RIGHT_Y));break
	if stick.length()<.15:stick=Vector2.ZERO
	if not _mouse_delta.is_zero_approx() or not stick.is_zero_approx():
		cursor+=_mouse_delta/dimensions*1.1+stick*dt*.75;cursor=cursor.clamp(Vector2(.02,.04),Vector2(.98,.96));has_cursor=true
	var best:int=-1;var distance:float=72
	for index:int in 4:
		var pin:Dictionary=pins[index]
		if not pin.visible:continue
		var delta:float=(Vector2(pin.display)-Vector2(0,34)-cursor*dimensions).length()
		if delta<distance:distance=delta;best=index
	if best!=hover:
		hover=best
		if hover>=0 and k>.7:_sound("ui_hover",.4)

func _arc_update(can_jump:bool)->void:
	_arc.clear()
	if hover<0 or not can_jump or not pins[4].visible or not pins[hover].visible or (hover!=3 and not pins[hover].ok):return
	var scale_value:Vector2=view.canvas.scale
	var a:Vector2=Vector2(pins[4].position)/scale_value;var b:Vector2=Vector2(pins[hover].position)/scale_value
	var lift:float=minf(220,a.distance_to(b)*.55+40);var control:Vector2=Vector2((a.x+b.x)*.5,minf(a.y,b.y)-lift)
	for step:int in 49:
		var t:float=float(step)/48;_arc.append(a.lerp(control,t).lerp(control.lerp(b,t),t))

func _head_text()->void:
	if not game.stage:return
	var stage_name:String=str(game.stage.layout.get("name","Stage"))
	for stage:Dictionary in game.config.get("MAPS",[]):
		if str(stage.id)==str(game.stage.stage_id):stage_name=str(stage.name);break
	_title.text=stage_name.to_upper();_when.text="DUSK" if str(game.options.get("time_of_day","day"))=="dusk" else "DAY"

func _jump(index:int)->void:
	if index<0 or index>3:return
	pins[index].flash=.42
	if not game.local_player.can_super_jump() or not bool(pins[index].ok):_sound("ui_error",.55);return
	hud.jump_requested.emit(index);_sound("ui_confirm",.55)

func _input(event:InputEvent)->void:
	if not on or not hud.is_visible_in_tree() or game.paused:return
	if event is InputEventMouseMotion and Input.mouse_mode==Input.MOUSE_MODE_CAPTURED:
		_mouse_delta+=event.relative;get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT:
		_clicked=_clicked or event.pressed;get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and event.button_index==JOY_BUTTON_A:
		_clicked=_clicked or event.pressed;get_viewport().set_input_as_handled()
	elif event is InputEventKey and event.pressed and not event.echo and event.keycode>=KEY_1 and event.keycode<=KEY_4:
		_jump(event.keycode-KEY_1);get_viewport().set_input_as_handled()

func _sound(id:String,volume:float)->void:
	if is_instance_valid(game) and is_instance_valid(game.get("audio")):game.audio.play(id,{"volume":volume})
