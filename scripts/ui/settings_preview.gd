class_name SplatSettingsPreview
extends Control
## Original settings SVG recipes, with their native animation and value responses.
const C=preload("res://scripts/ui/lab_canvas.gd")
const O=Color("ff8a14")
const B=Color("2f5bff")
const K=Color("15121c")
var key:String=""
var value:Variant=1.0
var settings:Dictionary={}
var _clock:float=0
var _art:TextureRect
var _caption:Label
var _stage:Control
var _pan:Control
var _input:TextureRect
var _rows:Array[Control]=[]
var _cache:Dictionary={}
var _frame_svg:String=""
var _size_rect:Rect2
var _trail:PackedVector2Array=[]

func _ready()->void:
	mouse_filter=Control.MOUSE_FILTER_IGNORE
	clip_contents=true
	_stage=Control.new();add_child(_stage);C.at(_stage,.8,.8,26.5,11.8)
	_stage.mouse_filter=Control.MOUSE_FILTER_IGNORE
	_caption=C.label(self,"",.8,13.15,26.5,1.85,.78)
	_caption.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_caption.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	resized.connect(queue_redraw)

func show_setting(next_key:String,next_value:Variant,all_settings:Dictionary)->void:
	var changed:bool=key!=next_key
	key=next_key;value=next_value;settings=all_settings
	if not is_instance_valid(_stage):return
	if changed:
		for child:Node in _stage.get_children():_stage.remove_child(child);child.queue_free()
		_rows.clear();_art=null;_pan=null;_input=null;_trail.clear();_clock=0
		build()
	refresh()
	queue_redraw()

func build()->void:
	if key in ["sensitivity","padSensitivity"]:
		_stage.clip_contents=true
		_pan=Control.new();_stage.add_child(_pan);C.at(_pan,0,0,26.5,11.1);_pan.clip_contents=true
		_art=C.icon(_pan,"preview_sensitivity_0",-26.5,0,79.5,11.1)
		_art.stretch_mode=TextureRect.STRETCH_SCALE
		_input=C.icon(self,"glyph_gamepad" if key=="padSensitivity" else "preview_sensitivity_1",1.0,12.5,2.4,2.4)
		return
	var name:String=key
	if key in ["fov","shadows","bloom","showFps","minimap","cameraShake","aimAssist"]:
		_frame_svg=FileAccess.get_file_as_string("res://assets/ui/source/preview_%s_0.svg"%name)
		_art=C.image(_stage,"",0,0,26.5,11.8)
		return
	if key=="invertY":
		C.icon(_stage,"preview_invertY_0",.5,3.9,2.4,3)
		C.icon(_stage,"glyph_next",3.8,5.1,1.6,1.6)
		_art=C.icon(_stage,"preview_invertY_3",6.3,0,20.2,11.8)
		return
	if key=="rumble":_input=C.icon(_stage,"glyph_gamepad",9.75,2.4,7,7)
	if key in ["master","music","sfx"]:_input=C.icon(_stage,"glyph_speaker",.6,4,3.6,3.6)
	if key=="aimAssistMouse":
		for index:int in 2:
			var card:Control=C.panel(_stage,5.4+index*8.5,2.7,7.1,7.1,Color("2b2438"),1)
			C.icon(card,"glyph_gamepad" if index==0 else "preview_sensitivity_1",1.7,.8,3.6,3.6)
			C.panel(card,.9,5.1,5.3,1.2,O,.6);C.label(card,"ASSIST",1.2,5.1,4.7,1.1,.62,false,K).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			_rows.append(card)
	if key=="matchLength":
		_art=C.icon(_stage,"preview_matchLength_0",7.4,0,11.8,11.8)
		var num:Label=C.label(_stage,"",7.4,5.7,11.8,2.4,2,true);num.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER;_rows.append(num)
	if key=="quality":
		var labs:Array=["LOW","MED","HIGH","ULTRA"]
		for index:int in 4:
			var col:Control=C.panel(_stage,.3+index*2.15,9.2-(.3+index*.233)*9.2,1.7,(.3+index*.233)*9.2,Color("484252"),.5);_rows.append(col)
			C.label(_stage,labs[index],.1+index*2.15,10.0,2.1,1,.66).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		for index:int in 6:
			var chip:Control=C.panel(_stage,10.3+(index%2)*8.2,1.6+floori(index/2.0)*3.1,7.8,2.7,Color("30283e"),.6)
			var label:Label=C.label(chip,["PIXEL DENSITY","SHADOW MAP","ANTI-ALIASING","INK DETAIL","AMBIENT OCCLUSION","PARTICLES"][index],.55,.4,6.7,.7,.5)
			label.modulate.a=.65
			var val:Label=C.label(chip,"",.55,1.3,6.7,1.1,.95,true);_rows.append(val)
	if key=="difficulty":
		for index:int in 3:
			var card:Control=C.panel(_stage,index*9.0,1.9,8.5,9.4,Color("292335"),.9)
			C.icon(card,"glyph_bot",2.9,.9,2.7,2.7)
			for pip:int in 3:C.panel(card,2.6+pip*1.2,4.2,.6,.6,O if pip<=index else Color("514755"),.3)
			C.label(card,["Chill","Fresh","Fierce"][index],.5,5.9,7.5,1.5,1.0,true).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
			_rows.append(card)
	if key=="colorblind":
		for index:int in 2:
			var card:Control=C.panel(_stage,0,.4+index*5.8,26.5,5.2,Color("30293d"),.8)
			C.label(card,"STANDARD INKS · rotate each match" if index==0 else "COLORBLIND-SAFE · always",.8,.6,24,1,.6)
			_rows.append(card)
			if index==0:
				var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/themes/source_catalog.json")) as Dictionary
				var palettes:Array=catalog.get("palettes",[]) as Array
				for pair:int in mini(6,palettes.size()):
					C.panel(card,.8+pair*3.5,2.3,1.45,1.45,Color(str(palettes[pair].a)),.725)
					C.panel(card,1.8+pair*3.5,2.3,1.45,1.45,Color(str(palettes[pair].b)),.725)
			else:
				C.panel(card,.8,2.3,1.45,1.45,Color("ffd21a"),.725);C.panel(card,1.8,2.3,1.45,1.45,Color("2a52ff"),.725)
				C.label(card,"Sun vs Sea",4,2.25,18,1.7,1.0,true)
	if key in ["controls","_reset"]:
		C.icon(_stage,"glyph_keyboard" if key=="controls" else "glyph_reset",7.1,2.3,4.2,4.2)
		if key=="controls":C.icon(_stage,"glyph_gamepad",15.1,2.3,4.2,4.2)

func refresh()->void:
	var caption:String=""
	var number:float=float(value) if value is int or value is float else 0.0
	match key:
		"sensitivity":caption="%d px of mouse travel per 360° turn"%roundi(TAU/(.0021*maxf(.2,number)))
		"padSensitivity":caption="Full-stick 360° turn in %.2f s"%(TAU/(3.4*maxf(.2,number)))
		"invertY":caption="Push up → look DOWN" if bool(value) else "Push up → look UP"
		"fov":
			var half:float=deg_to_rad(number*.5);var start:Vector2=Vector2(160-sin(half)*158,172-cos(half)*158)
			var wedge:String="M160 172 L%.1f %.1f A158 158 0 0 1 %.1f %.1f Z"%[start.x,start.y,320-start.x,start.y]
			var expression:=RegEx.new();expression.compile('(<path class="iw-pv-fov__wedge"[^>]*d=")[^"]*')
			set_svg(expression.sub(_frame_svg,"${1}"+wedge))
			var count:int=0
			for angle:int in [-58,-46,-35,-20,-4,12,27,39,49,61]:if absf(angle)<=number*.5:count+=1
			caption="%d of 10 squidkids in view"%count
		"shadows":
			set_svg(_frame_svg if bool(value) else _frame_svg.replace('class="iw-pv-shadow"','class="iw-pv-shadow" opacity="0"'))
			caption="Soft sun shadows ON" if bool(value) else "Shadows OFF — faster on older machines"
		"bloom":
			set_svg(_frame_svg if bool(value) else _frame_svg.replace('class="iw-pv-bloom__glow"','class="iw-pv-bloom__glow" opacity="0"'))
			caption="Bright ink and specials glow" if bool(value) else "Glow OFF"
		"showFps","minimap":
			set_svg(_frame_svg if bool(value) else _frame_svg.replace('class="iw-pv-pop"','class="iw-pv-pop" opacity="0"'))
			caption=("Frame counter shown in matches" if bool(value) else "Frame counter hidden") if key=="showFps" else ("Turf minimap in the corner" if bool(value) else "Minimap hidden — hold TAB for the big map")
		"cameraShake":set_svg(_frame_svg);caption="Screen shake OFF" if number<=0 else "Shake strength %d%%"%roundi(number*100)
		"aimAssist":set_svg(_frame_svg.replace('class="iw-pv-aim__x"','class="iw-pv-aim__x" opacity="0"'));caption="Aim assist OFF" if number<=0 else "Pull strength %d%%"%roundi(number*100)
		"aimAssistMouse":
			caption="Assist on controller and mouse (lighter on mouse)" if bool(value) else "Assist on controller only"
			if _rows.size()==2:_rows[1].modulate.a=1.0 if bool(value) else .4
		"rumble":caption="Vibration OFF" if number<=0 else "Rumble strength %d%%"%roundi(number*100)
		"master":caption="Overall output %d%%"%roundi(number*100)
		"music","sfx":caption="Heard at %d%% after master volume"%roundi(number*float(settings.get("master",.8))*100)
		"difficulty":
			var own:int=maxi(0,["easy","normal","hard"].find(str(value)))
			caption=["Chill rivals. Time to find your feet.","Balanced rivals. A proper turf war.","Sharp aim and quick reactions. Bring your best."][own]
			for index:int in _rows.size():_rows[index].modulate.a=1.0 if index==own else .5
		"quality":
			var tier:int=maxi(0,["low","medium","high","ultra"].find(str(value)))
			var table:Array=[[.75,1024,0,2,false,40],[1,2048,2,2,false,70],[1.5,4096,4,4,true,100],[2,4096,4,4,true,100]]
			for index:int in 4:(_rows[index].material as ShaderMaterial).set_shader_parameter("top_color",O if index==tier else Color("484252"))
			var values:Array=table[tier]
			var labels:Array=["up to %s×"%str(values[0]),"%dpx"%values[1],"Off" if values[2]==0 else "%d× MSAA"%values[2],"%dK atlas"%values[3],"On" if values[4] else "Off","%d%%"%values[5]]
			for index:int in 6:(_rows[index+4] as Label).text=labels[index]
		"matchLength":
			if not _rows.is_empty():(_rows[0] as Label).text="%d:%02d"%[floori(number/60),int(number)%60]
			caption="A quick sprint — every second counts" if number<120 else "The full turf war — room for comebacks"
		"colorblind":
			for index:int in _rows.size():_rows[index].modulate.a=1.0 if index==(1 if bool(value) else 0) else .45
		"controls":caption="Every binding for keyboard, mouse and controller"
		"_reset":caption="Press twice to restore every setting on every tab"
	_caption.text=caption

func set_svg(svg:String)->void:
	if not is_instance_valid(_art):return
	if not _cache.has(svg):
		var img:=Image.new()
		if img.load_svg_from_string(svg,1.25)!=OK:return
		_cache[svg]=ImageTexture.create_from_image(img)
	_art.texture=_cache[svg] as Texture2D

func _process(dt:float)->void:
	if not visible:return
	_clock+=dt
	var number:float=float(value) if value is int or value is float else 0.0
	if key in ["sensitivity","padSensitivity"] and _art:
		_art.position.x=(-33.333-sin(_clock*TAU/2.2)*5.2*number)*.01*_art.size.x
		_input.position.x=12.8+sin(_clock*TAU/2.2)*16
	if key=="cameraShake" and _art:
		var elapsed:float=fmod(_clock,1.7)
		var fade:float=maxf(0,1-elapsed/.42)
		_art.position=Vector2(sin(elapsed*90)*9*number*fade,cos(elapsed*80)*5.4*number*fade)
	if key=="rumble" and _input:
		var elapsed:float=fmod(_clock,1.5)
		var fade:float=maxf(0,1-elapsed/.52)
		_input.position.x=9.75*12.8+sin(elapsed*90)*7*number*fade
	if key=="invertY" and _art:_art.position.y=sin(_clock*TAU/2)*6*(-1 if bool(value) else 1)
	if key in ["aimAssist","rumble","master","music","sfx"]:queue_redraw()

func _draw()->void:
	if not _stage:return
	var number:float=float(value) if value is int or value is float else 0.0
	if key=="aimAssist":
		var phase:float=fmod(_clock/2.6,1);var x0:float=30+phase*260;var near:float=exp(-pow((x0-160)/60,2))
		var point:Vector2=Vector2(x0+(160-x0)*near*number*.55,64+36*near*number)
		var fit:float=(26.5*12.8)/320
		point=point*fit+_stage.position+Vector2(0,(11.8*12.8-180*fit)*.5)
		if phase<.02:_trail.clear()
		if _trail.is_empty() or _trail[-1].distance_to(point)>1:_trail.append(point)
		if _trail.size()>1:draw_polyline(_trail,Color(1,.54,.078,.9),3,true)
		draw_arc(point,13*fit,0,TAU,32,Color.WHITE,4*fit,true);draw_arc(point,13*fit,0,TAU,32,K,1.6*fit,true);draw_circle(point,3*fit,Color.WHITE)
	if key in ["master","music","sfx"]:
		var eff:float=number*(1.0 if key=="master" else float(settings.get("master",.8)))
		var beat:float=pow(maxf(0,sin(_clock*5.1)),6) if key=="sfx" else .55+.45*pow(maxf(0,sin(_clock*PI*2.4)),3)
		for index:int in 18:
			var spectrum:float=1-index/17.0*.55 if key=="music" else .35+.65*sin(index/17.0*PI) if key=="sfx" else .8-index/17.0*.3
			var height:float=clampf(eff*spectrum*(.4+.6*absf(sin(index*97.0)))*(.45+.55*absf(sin(_clock*(2+fmod(index*7,5))+index*1.73)))*(.5+.8*beat)*1.25,.02,1)*103
			draw_rect(Rect2(Vector2(5.2*12.8+index*1.1*12.8,6.3*12.8-height*.5),Vector2(.78*12.8,height)),O if eff>0 else Color("62596d"))
	if key=="rumble" and number>0:
		var elapsed:float=fmod(_clock,1.5)
		if elapsed<.5:
			for side:int in [-1,1]:draw_arc(Vector2((13.25+side*5.5)*12.8,6.2*12.8),24,PI*.65 if side<0 else -PI*.35,PI*1.35 if side<0 else PI*.35,24,Color(1,.54,.078,(1-elapsed/.5)*number),3,true)
