class_name SplatLabCredits
extends SplatLabCanvas
const C=preload("res://scripts/ui/lab_canvas.gd")
const L=preload("res://scripts/ui/lab_screens.gd")
var host:InkUI
var roll:Control
var items:Array[Control]=[]
var y:float=0
var roll_height:float=0

func build(controller:InkUI)->void:
	host=controller
	C.panel(canvas,0,0,width_u,height_u,Color(.047,.035,.086,.55),0)
	L.header(host,self,"CREDITS")
	var clip:=Control.new();canvas.add_child(clip);C.at(clip,width_u*.5-29,0,58,height_u);clip.clip_contents=true;clip.mouse_filter=Control.MOUSE_FILTER_IGNORE
	roll=Control.new();clip.add_child(roll);C.at(roll,0,height_u*.62,58,160)
	L.logo(roll,14,3,5.2)
	add_line("An original 4 v 4 turf-war shooter.",20,1.4,false)
	section("MADE WITH",["Procedural everything — squidkids, weapons,\nstage, ink, music and sound are all generated in code."],29)
	section("RENDERING",["Godot Engine","Native adaptation of the original three.js game"],45)
	section("TYPOGRAPHY",["Titan One — Font Diner","Rubik — Hubert & Fischer","SIL Open Font License"],62)
	add_line("STARRING THE SQUIDKIDS",83,.95,false,SplatUiTheme.ORANGE)
	var names:Array=SplatUiTheme.catalog().get("bot_names",["Squiddo","Blotch","Marlo","Inky Vee","Pip","Coral","Riptide","Nori","Suki","Zest","Kelp","Drip","Tako","Sprinkle","Bubbles","Moxie","Juno","Wasabi","Fizz","Loop"])
	for index:int in names.size():
		var x:float=(index%4)*14.8
		var yy:float=87+floori(index/4.0)*3.3
		C.icon(roll,"squid" if index%2==0 else "squid_blue",x,yy,1.9,1.9)
		items.append(C.label(roll,str(names[index]),x+2.5,yy,11.8,1.9,1.1))
	section("SPECIAL THANKS",["Everyone who ever painted a wall","Every bot that got splatted in testing","And you, for playing"],111)
	C.icon(roll,"splat",15,137,28,28)
	add_line("STAY FRESH!",144,4.8,true)
	roll_height=168;y=height_u*.62*12.8
	L.prompts(self,"Enter  Hold to speed up     Esc  Back",26)

func add_line(value:String,at_y:float,fs:float,display:bool,color:Color=Color.WHITE)->void:
	var line:Label=C.label(roll,value,0,at_y,58,fs*2.0,fs,display,color)
	line.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	items.append(line)

func section(title:String,lines:Array,at_y:float)->void:
	add_line(title,at_y,.95,false,SplatUiTheme.ORANGE)
	for index:int in lines.size():add_line(str(lines[index]),at_y+3.0+index*3.4,1.1 if str(lines[index]).begins_with("SIL") or str(lines[index]).begins_with("Native") else 2.0,false)

func _process(delta:float)->void:
	if roll==null:return
	var speed:float=260 if Input.is_action_pressed("ui_accept") or Input.is_action_pressed("ui_down") else -140 if Input.is_action_pressed("ui_up") else 42
	y-=speed*delta
	if y<(-roll_height+height_u*.35)*12.8:y=height_u*12.8
	y=minf(y,height_u*12.8);roll.position.y=y
	for item:Control in items:
		var center:float=(y+item.position.y+item.size.y*.5)/(height_u*12.8)
		item.modulate.a=clampf(minf(center/.2,(1-center)/.2),0,1)
