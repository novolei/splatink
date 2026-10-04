class_name SplatLabNews
extends SplatLabCanvas
signal closed(action:String)
const C=preload("res://scripts/ui/lab_canvas.gd")
const K=Color("15121c")
const O=Color("ff8a14")
const B=Color("2f5bff")
var host:InkUI
var index:int=0
var card:Control
var backdrop:ColorRect
var confetti:Control
var _age:float=0
var _particles:Array[Dictionary]=[]
var _busy:bool=false
var _ticket_materials:Array[ShaderMaterial]=[]

func build(ui:InkUI)->void:
	host=ui
	layout_changed.connect(_ticket_scale)
	mouse_filter=Control.MOUSE_FILTER_STOP
	backdrop=ColorRect.new();canvas.add_child(backdrop);C.at(backdrop,0,0,width_u,height_u)
	var material:=ShaderMaterial.new();material.shader=preload("res://assets/ui/lab_news.gdshader");material.set_shader_parameter("viewport_size",Vector2(width_u,height_u)*12.8);material.set_shader_parameter("reveal",.001);backdrop.material=material
	confetti=Control.new();canvas.add_child(confetti);C.at(confetti,0,0,width_u,height_u);confetti.mouse_filter=Control.MOUSE_FILTER_IGNORE
	create_tween().tween_method(func(v:float)->void:material.set_shader_parameter("reveal",v),.001,1.0,.7).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	show_card(0)

func show_card(page_index:int)->void:
	index=page_index;_age=0;_particles.clear()
	for child:Node in confetti.get_children():confetti.remove_child(child);child.queue_free()
	if is_instance_valid(card):canvas.remove_child(card);card.queue_free()
	_ticket_materials.clear()
	var color:Color=O if index==0 else B
	(backdrop.material as ShaderMaterial).set_shader_parameter("ink",color)
	var h:float=39.0 if index==0 else 37.8125
	card=_ticket(canvas,(width_u-88)*.5,(height_u-h)*.5,88,h,2.4,.35,.7,1.0,.45,true)
	card.rotation=deg_to_rad(-1.2);card.pivot_offset=card.size*.5
	var hero:Control=Control.new();card.add_child(hero);C.at(hero,33.0/12.8,(96.0 if index==0 else 89.0)/12.8,549.0/12.8,309.0/12.8);hero.rotation=deg_to_rad(2.2);hero.pivot_offset=hero.size*.5
	var splat:TextureRect=C.icon(hero,"news_splat_%d"%index,-3.86,-3.86,18.875,18.875);splat.modulate=color
	_ticket(hero,0,0,549.0/12.8,309.0/12.8,1.3,.5,.85,.9,.4,false,"res://assets/ui/news/%s.webp"%("lobby" if index==0 else "boss"))
	for own:int in 2:
		var tape:ColorRect=ColorRect.new();tape.mouse_filter=Control.MOUSE_FILTER_IGNORE;hero.add_child(tape);C.at(tape,-2.14453125 if own==0 else 37.74375,-.72421875 if own==0 else 22.209375,7.29140625,2.65546875)
		var tape_material:ShaderMaterial=ShaderMaterial.new();tape_material.shader=preload("res://assets/ui/lab_news_tape.gdshader");tape_material.set_shader_parameter("tape_size",tape.size);tape.material=tape_material
		tape.pivot_offset=tape.size*.5;tape.rotation=deg_to_rad(-33)
	if index==0:
		var stamp:Control=C.panel(hero,471.0/12.8,-28.0/12.8,100.0/12.8,40.0/12.8,Color("ffd23f"),20.0/12.8);stamp.rotation=deg_to_rad(12);stamp.pivot_offset=stamp.size*.5
		(stamp.material as ShaderMaterial).set_shader_parameter("border_color",K);(stamp.material as ShaderMaterial).set_shader_parameter("border",3.0)
		var stamp_word:Label=C.label(stamp,"NEW!",.5,.25,6.81,2.6,2.0,false,K);stamp_word.add_theme_font_override("font",SplatUiTheme.DISPLAY);stamp_word.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	else:
		var tape:Control=C.panel(hero,-33.0/12.8,245.0/12.8,314.0/12.8,35.0/12.8,K,0);tape.rotation=deg_to_rad(-6);tape.pivot_offset=tape.size*.5
		C.icon(tape,"news_beta_tape",0,0,314.0/12.8,35.0/12.8)
		C.panel(tape,1.2,.45,314.0/12.8-2.6,35.0/12.8-.9,Color.WHITE,0)
		var tape_word:Label=C.label(tape,"BOSS BATTLE · PUBLIC BETA",1.5,.5,314.0/12.8-3.2,1.7,1.12,false,K);tape_word.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"));tape_word.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var x:float=623.0/12.8
	var kicker:Control=C.panel(card,x,33.0/12.8,158.0/12.8,25.0/12.8,color,.4);kicker.rotation=deg_to_rad(-3)
	C.icon(kicker,"glyph_sparkle",.55,.5,1.1,1.1).modulate=K
	C.label(kicker,"INTRODUCING",2,.45,10.0,1.2,.95,false,K)
	var title:Control=Control.new();card.add_child(title);C.at(title,x,68.0/12.8,36.33,94.0/12.8 if index==0 else 61.0/12.8);title.rotation=deg_to_rad(-2);title.pivot_offset=Vector2(0,title.size.y*.5)
	if index==0:
		C.label(title,"THE MULTIPLAYER",0,0,36.33,3.672,3.6,true)
		C.label(title,"EXPANSION",0,3.672,36.33,3.672,3.6,true,color.lerp(Color.WHITE,.45))
	else:C.label(title,"HULLBREAKER",0,0,36.33,4.78,4.7,true,color.lerp(Color.WHITE,.45))
	var lede:Label=C.label(card,"Grab your crew — the harbour just got a whole lot louder!" if index==0 else "A giant hermit crab has moved into a rusty shipping container — and it wants the whole harbour.",x,(171.0 if index==0 else 138.0)/12.8,34.6,19.0/12.8 if index==0 else 39.0/12.8,1.12);lede.add_theme_font_override("font",preload("res://assets/fonts/ink_body_700_font.tres"))
	lede.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	var rows:Array=[
		["glyph_key","Private rooms","share a code, squad up with up to 8 friends"],
		["glyph_smile","The Lobby","watch your squad roll in, emote, ready up"],
		["glyph_map","Cargo Terminal","a brand-new stage, online only"]
	] if index==0 else [
		["glyph_users","Co-op showdown","your whole squad vs one colossal crab"],
		["glyph_target","Three phases of chaos","dodge the tells, crack the shell, blast the glowing weak points"],
		["glyph_sparkle","Public beta","it’s still sharpening its claws — tell us what you think!"]
	]
	for own:int in 3:
		var row_y:Array=[204,257,309] if index==0 else [191,243,298]
		var row_h:Array=[45,45,50] if index==0 else [45,47,47]
		var row:Control=C.panel(card,x,float(row_y[own])/12.8,465.0/12.8,float(row_h[own])/12.8,Color("30283e"),.9)
		var icon:Control=C.panel(row,.5,.5,2.5,2.5,K,1.25)
		(icon.material as ShaderMaterial).set_shader_parameter("border_color",color);(icon.material as ShaderMaterial).set_shader_parameter("border",2)
		C.icon(icon,rows[own][0],.475,.475,1.55,1.55).modulate=color
		var text:Label=C.label(row,rows[own][1]+" — "+rows[own][2],3.8,.45,25.4 if index==0 and own==2 else 30.2,2.65,1.02)
		text.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
		if index==0 and own==2:C.image(row,"res://assets/ui/stages/cargo-day-sm.webp",29.0,.5,5.2,2.93).rotation=deg_to_rad(4)
	var go_y:float=(381.0 if index==0 else 366.0)/12.8
	var go_width:float=(259.0 if index==0 else 215.0)/12.8
	var go:SplatInkButton=C.button(card,"CONTINUE" if index==0 else "TRY IT",func()->void:next() if index==0 else close("try"),x,go_y,go_width,4.6,1.9,"" if index==0 else "glyph_play","",true,color)
	if index==0:C.icon(go,"glyph_next",13.1,1.25,2.0,2.0).modulate=K
	C.keycap(go,"Enter",go_width-4.6,1.4,.78)
	C.defer_focus(go)
	# The source global cursor sits below the z60 News modal; no extra outside focus ring here.
	go._material.set_shader_parameter("focus_outline",0.0)
	var later:SplatInkButton=C.button(card,"Skip" if index==0 else "LATER",func()->void:close("skip" if index==0 else "later"),x+(274.0 if index==0 else 230.0)/12.8,go_y+(.78 if index==0 else 0),97.0/12.8 if index==0 else 130.0/12.8,3.0 if index==0 else 4.6,.95 if index==0 else 1.9)
	later.set_source_ghost()
	later._material.set_shader_parameter("focus_outline",0.0)
	if index==0:C.keycap(later,"Esc",4.85,.72,.78)
	var buttons:Array[Control]=[]
	for child:Node in card.get_children():if child is Button:buttons.append(child as Control)
	for own:int in buttons.size():
		buttons[own].focus_next=buttons[(own+1)%buttons.size()].get_path();buttons[own].focus_previous=buttons[posmod(own-1,buttons.size())].get_path()
		buttons[own].focus_neighbor_left=buttons[posmod(own-1,buttons.size())].get_path();buttons[own].focus_neighbor_right=buttons[(own+1)%buttons.size()].get_path()
		buttons[own].focus_neighbor_top=buttons[own].get_path();buttons[own].focus_neighbor_bottom=buttons[own].get_path()
	var footer_y:float=(458.0 if index==0 else 443.0)/12.8
	C.panel(card,x,footer_y,2.2 if index==0 else .8,.8,color if index==0 else Color("60576a"),.4)
	C.panel(card,x+2.6,footer_y,.8 if index==0 else 2.2,.8,Color("60576a") if index==0 else color,.4)
	C.label(card,"%d / 2"%(index+1),x+4.0,footer_y-.3,7.0,1.4,.75,false,Color("9e94af"))
	if not bool(host.settings.get("reduce_motion",false)):
		card.scale=Vector2.ONE*.55;card.modulate.a=0;card.rotation=deg_to_rad(-9)
		var tween:Tween=create_tween().set_parallel(true)
		tween.tween_property(card,"scale",Vector2.ONE,.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card,"rotation",deg_to_rad(-1.2),.7).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(card,"modulate:a",1.0,.38)
		for own:int in 34:
			var node:Control=C.panel(confetti,fposmod(own*.618034+.07,1)*width_u,-2,.8*(.5+fposmod(own*.43,1)*.7),1.5*(.5+fposmod(own*.43,1)*.7),[color,color.lightened(.45),Color("ffd23f"),Color.WHITE,O,B][own%6],.4 if own%3==0 else 0)
			_particles.append({"node":node,"start":node.position,"delay":.05+fposmod(own*.37,1)*.5,"duration":1.5+fposmod(own*.53,1)*1.1,"rotation":deg_to_rad(fposmod(own*.71,1)*720-360),"drift":(fposmod(own*.29,1)-.5)*width_u*.12*12.8})

func _ticket(parent:Node,x:float,y:float,w:float,h:float,radius:float,white:float,ink:float,drop:float,shadow_alpha:float,grain:bool,image_path:String="")->Control:
	var body:Control=Control.new();body.mouse_filter=Control.MOUSE_FILTER_IGNORE;parent.add_child(body);C.at(body,x,y,w,h)
	var quad:ColorRect=ColorRect.new();quad.mouse_filter=Control.MOUSE_FILTER_IGNORE;quad.position=Vector2(-20,-20);quad.size=body.size+Vector2(40,56);body.add_child(quad)
	var material:ShaderMaterial=ShaderMaterial.new();material.shader=preload("res://assets/ui/lab_news_ticket.gdshader");quad.material=material
	material.set_shader_parameter("body_size",body.size);material.set_shader_parameter("quad_size",quad.size);material.set_shader_parameter("radius",radius*12.8)
	material.set_shader_parameter("white_spread",white*12.8);material.set_shader_parameter("ink_spread",ink*12.8);material.set_shader_parameter("shadow_drop",drop*12.8);material.set_shader_parameter("shadow_alpha",shadow_alpha)
	material.set_shader_parameter("pixel_scale",canvas.scale.x);material.set_shader_parameter("print_grain",grain)
	if grain:material.set_shader_parameter("grain_tex",preload("res://assets/ui/source/news_grain.png"))
	if not image_path.is_empty():material.set_shader_parameter("image_face",true);material.set_shader_parameter("image_tex",load(image_path))
	_ticket_materials.append(material)
	return body

func _ticket_scale()->void:
	for material:ShaderMaterial in _ticket_materials:material.set_shader_parameter("pixel_scale",canvas.scale.x)

func next()->void:
	if _busy:return
	_busy=true
	var tween:Tween=create_tween();tween.tween_property(card,"modulate:a",0,.28);tween.tween_callback(func()->void:_busy=false;show_card(1))

func close(action:String="back")->void:
	if _busy:return
	_busy=true
	var tween:Tween=create_tween().set_parallel(true)
	tween.tween_property(card,"modulate:a",0,.28)
	tween.tween_method(func(v:float)->void:(backdrop.material as ShaderMaterial).set_shader_parameter("reveal",v),1.0,.001,.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.chain().tween_callback(func()->void:closed.emit(action);queue_free())

func _input(event:InputEvent)->void:
	if event.is_action_pressed("ui_cancel"):close("back");get_viewport().set_input_as_handled()

func _process(dt:float)->void:
	_age+=dt
	for particle:Dictionary in _particles:
		var node:Control=particle.node as Control
		if not is_instance_valid(node):continue
		var phase:float=clampf((_age-float(particle.delay))/float(particle.duration),0,1)
		node.visible=phase>0 and phase<1;node.position=particle.start+Vector2(float(particle.drift)*phase,height_u*12.8*1.08*phase);node.rotation=float(particle.rotation)*phase
		node.modulate.a=1.0 if phase<.85 else (1-phase)/.15
