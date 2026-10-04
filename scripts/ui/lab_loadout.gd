class_name SplatLabLoadout
extends SplatLabCanvas
const C=preload("res://scripts/ui/lab_canvas.gd")
const L=preload("res://scripts/ui/lab_screens.gd")
const K=Color("15121c")
const O=Color("ff8a14")
const M=Color("c3bdd6")
var host:InkUI
var equipped:String="shooter"
var shown:String=""
var detail:Control
var count:Label
var cards:Array[Dictionary]=[]
var _bars:Array[Dictionary]=[]
var _time:float=0

func build(ui:InkUI)->void:
	host=ui;equipped=str(host.options.weapon)
	L.header(host,self,"LOADOUT","7 weapons · every one comes with a sub and a special")
	C.icon(canvas,"weapon_shooter",3.6,10.7,1.2,1.0)
	C.label(canvas,"WEAPON",5.45,10.4,47,1.4,.9)
	var count_chip:Control=C.panel(canvas,54.2,10.55,3.4,1.3,Color(1,1,1,.1),.6);count_chip.z_index=20
	count=C.label(canvas,"1 / 7",54.2,10.55,3.4,1.3,.8,false,Color.WHITE);count.z_index=21;count.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	var catalog:Dictionary=SplatUiTheme.catalog()
	for index:int in catalog.weapon_order.size():
		var id:String=str(catalog.weapon_order[index]);var weapon:Dictionary=catalog.weapons[id]
		var action:Callable=func()->void:_equip(id)
		var tile:Button=C.tile(canvas,action,3.6+(index%4)*13.725,13.25+floori(index/4.0)*9.3,12.825,8.4,false)
		var rim:Control=C.panel(tile,-.7,-.7,14.225,9.8,Color(0,0,0,0),1.4)
		var rim_material:ShaderMaterial=rim.material as ShaderMaterial;rim_material.set_shader_parameter("top_color",Color.TRANSPARENT);rim_material.set_shader_parameter("bottom_color",Color.TRANSPARENT);rim_material.set_shader_parameter("border_color",Color(O,.55));rim_material.set_shader_parameter("border",2.5);rim.z_index=9;rim.visible=id==equipped
		tile.set_meta("source_click_sound","")
		tile.set_meta("source_tilt",deg_to_rad([-1.5,1.0,-.8,1.4,-1.1][index%5]));tile.rotation=float(tile.get_meta("source_tilt"))
		var blob:TextureRect=C.icon(tile,"weapon_blob_%d"%index,(12.825-9.5)*.5,8.4*.36-4.75,9.5,9.5);blob.visible=id==equipped
		var weapon_shadow:TextureRect=C.icon(tile,"weaponw_"+id,.4+.2*12.825,.73,12.825*.82,4.3);weapon_shadow.self_modulate=K;weapon_shadow.position.x=(12.825*12.8-weapon_shadow.size.x)*.5
		var icon:TextureRect=C.icon(tile,"weaponw_"+id,.4+.2*12.825,.55,12.825*.82,4.3)
		icon.position.x=(12.825*12.8-icon.size.x)*.5
		var title:Label=C.label(tile,str(weapon.name),.3,5.55,12.225,1.1,1.02,true);title.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var kind:Label=C.label(tile,str(weapon.get("class",id)).to_upper(),.3,6.9,12.225,.95,.8,false,Color(1,1,1,.75));kind.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var eq:Control=C.panel(tile,10.075,.55,2.2,2.2,Color.WHITE,1.1);C.icon(eq,"glyph_check",.4,.4,1.4,1.4).modulate=K;eq.visible=id==equipped
		var new_chip:Control
		if id not in host.settings.get("seenWeapons",["shooter","roller","charger","blaster"]):
			new_chip=C.panel(tile,.45,.45,2.7,1.22,SplatUiTheme.GOLD,.4);new_chip.rotation=deg_to_rad(-8);new_chip.pivot_offset=new_chip.size*.5
			(new_chip.material as ShaderMaterial).set_shader_parameter("border",2.0);(new_chip.material as ShaderMaterial).set_shader_parameter("border_color",K)
			var new_label:Label=C.label(new_chip,"NEW!",.1,.0,2.5,1.22,.78,false,K);new_label.add_theme_font_override("font",preload("res://assets/fonts/ink_body_900_font.tres"));new_label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		cards.append({"id":id,"tile":tile,"blob":blob,"eq":eq,"new":new_chip,"icon":icon,"rim":rim})
		tile.mouse_entered.connect(tile.grab_focus)
		tile.focus_entered.connect(func()->void:
			_render(id);tile.rotation=0;icon.rotation=deg_to_rad(-6);icon.pivot_offset=icon.size*.5
			if is_instance_valid(new_chip):new_chip.hide())
		tile.focus_exited.connect(func()->void:tile.rotation=float(tile.get_meta("source_tilt"));icon.rotation=0)
		if id==equipped:C.defer_focus(tile)
	detail=C.panel(canvas,3.6,32,54,22.25)
	_look_chip()
	L.hero_drag(host,canvas,Rect2(60,9,width_u-63.4,height_u-13))
	L.prompts(self,"Enter  Equip    ← →  Browse    Esc  Back",26)
	_render(equipped)

func _equip(id:String)->void:
	if equipped==id:_sound("ui_click");return
	equipped=id;host.options.weapon=id;host.weapon_changed.emit(id);host.save_profile();_sound("ui_confirm")
	for card:Dictionary in cards:
		(card.blob as Control).visible=str(card.id)==id;(card.eq as Control).visible=str(card.id)==id
		(card.rim as Control).visible=str(card.id)==id
		(card.tile as Control).pivot_offset=(card.tile as Control).size*.5
		if str(card.id)==id:
			var tween:Tween=(card.tile as Control).create_tween();tween.tween_property(card.tile,"scale",Vector2.ONE*.92,.06);tween.tween_property(card.tile,"scale",Vector2.ONE*1.06,.16);tween.tween_property(card.tile,"scale",Vector2.ONE*1.035,.28)
	_render(id,true)

func _render(id:String,force:bool=false)->void:
	if shown==id and not force:return
	shown=id;count.text="%d / 7"%[SplatUiTheme.catalog().weapon_order.find(id)+1]
	var seen:Array=host.settings.get("seenWeapons",["shooter","roller","charger","blaster"])
	if id not in seen:seen.append(id);host.settings.seenWeapons=seen;host._save()
	for child:Node in detail.get_children():detail.remove_child(child);child.queue_free()
	_bars.clear()
	var catalog:Dictionary=SplatUiTheme.catalog();var weapon:Dictionary=catalog.weapons[id];var current:Dictionary=catalog.weapons[equipped]
	C.label(detail,str(weapon.get("class",id)).to_upper(),1.6,1.05,36,1.2,.8,false,O)
	C.label(detail,str(weapon.name),1.6,2.45,43,3.0,2.5,true)
	if id==equipped:
		var badge:Control=C.panel(detail,44.5,3.4,7.9,1.9,O,.95);C.icon(badge,"glyph_check",.55,.5,.85,.85).modulate=K;C.label(badge,"EQUIPPED",1.7,.1,5.9,1.7,.8,false,K)
	else:
		var badge:Control=C.panel(detail,37,3.4,15.4,1.9,Color(1,1,1,.1),.95);C.panel(badge,.6,.65,.65,.65,Color(1,1,1,.55),.325);C.label(badge,"vs "+str(current.name),1.7,.1,12.9,1.7,.8)
	C.label(detail,str(weapon.blurb),1.6,6.1,50.8,1.5,.95)
	for index:int in 5:
		var key:String=["range","damage","rate","mobility","paint"][index]
		var value:float=float(weapon.stats[key]);var ghost:float=float(current.stats[key]) if id!=equipped else 0.0
		var color:Color=Color("3ddc84") if id!=equipped and value>ghost+.01 else Color("ff5a70") if id!=equipped and value<ghost-.01 else O
		C.icon(detail,"glyph_"+["target","bolt","clock","feather","drop"][index],1.6,9.0+index*2.55,1.05,1.05).modulate=O
		C.label(detail,["RANGE","DAMAGE","FIRE RATE","MOBILITY","INK COVERAGE"][index],3.0,8.7+index*2.55,7.5,1.5,.8,false,Color(1,1,1,.85))
		var bar:=ColorRect.new();detail.add_child(bar);C.at(bar,10.95,9.03+index*2.55,10.6,1.1);bar.mouse_filter=Control.MOUSE_FILTER_IGNORE
		var mat:=ShaderMaterial.new();mat.shader=preload("res://assets/ui/lab_stat.gdshader");mat.set_shader_parameter("quad_size",bar.size);mat.set_shader_parameter("ink",color);mat.set_shader_parameter("ghost",ghost);mat.set_shader_parameter("value",0.0);bar.material=mat
		var number:Label=C.label(detail,"0",22.15,8.7+index*2.55,2.3,1.5,1.15,true,Color("6dffa8") if id!=equipped and value>ghost+.01 else Color("ff8a9a") if id!=equipped and value<ghost-.01 else Color.WHITE);number.horizontal_alignment=HORIZONTAL_ALIGNMENT_RIGHT
		if id!=equipped and absf(value-ghost)>.01:C.label(detail,"%+d"%roundi((value-ghost)*100),25.0,8.7+index*2.55,2.2,1.5,.72,false,color)
		_bars.append({"material":mat,"number":number,"value":value,"shown":0.0,"delay":.25+index*.07})
	for index:int in 2:
		var special:Dictionary=catalog.specials[str(weapon.special)]
		var kit:Control=C.panel(detail,29,8.0+index*7.0,23.4,6.4,Color(1,1,1,.05),1.0)
		var chip:Control=C.panel(kit,.85,.65,3.6,3.6,Color(0,0,0,.38),.8)
		C.icon(chip,"subw_bomb" if index==0 else "specialw_"+str(weapon.special),.36,.36,2.88,2.88)
		C.label(kit,"SUB WEAPON" if index==0 else "SPECIAL",5.35,.65,17.2,.9,.8,false,Color(1,1,1,.6))
		var name:String="Splat Bomb" if index==0 else str(special.name)
		C.label(kit,name,5.35,1.6,17.2,1.7,1.3,true)
		if index==1:
			var offset:float=SplatUiTheme.DISPLAY.get_string_size(name,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x/12.8
			var cost:Control=C.panel(kit,minf(20.15,5.35+offset+.6),2.13,2.75,1.0,Color(O,.2),.5);C.label(cost,"%dp"%int(weapon.get("specialCost",190)),0,0,2.75,1,.66,false,O.lightened(.45)).horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
		var tip:Label=C.label(kit,"Costs 70% of your ink tank. Hold to aim, release to throw." if index==0 else str(special.blurb),5.35,3.35,17.2,2.45,.8,false,Color("d0cadf"));tip.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	_time=0

func _look_chip()->void:
	var look:Button=C.tile(canvas,func()->void:host.open_page("locker"),width_u-29.4,2.6,26,4.8);look.rotation=deg_to_rad(1.2)
	C.icon(look,"profile_blob",.9,.4,3.8,3.8)
	var portrait:SplatAvatarPreview=SplatAvatarPreview.make(host.profile,equipped,host.main);portrait.thumbnail=true;portrait.portrait_kind="head";C.at(portrait,.6,.1,4.4,4.4);look.add_child(portrait);portrait.mouse_filter=Control.MOUSE_FILTER_IGNORE
	C.label(look,"SQUIDKID",5.7,.8,13,.9,.8,false,Color(1,1,1,.65));C.label(look,str(host.profile.name),5.7,1.9,13,1.7,1.35,true)
	var pill:Control=C.panel(look,18,1.5,7.3,1.9,Color(1,1,1,.1),.95);C.icon(pill,"glyph_hanger",.55,.5,.9,.9);C.label(pill,"LOCKER",1.8,.1,5,1.7,.8)
	look.mouse_entered.connect(look.grab_focus)

func _sound(id:String)->void:
	if is_instance_valid(host.main) and host.main.get("audio")!=null:host.main.audio.play(id)

func _process(delta:float)->void:
	_time+=delta
	for row:Dictionary in _bars:
		if _time<float(row.delay):continue
		row.shown=lerpf(float(row.shown),float(row.value),1-exp(-delta*9))
		if absf(float(row.shown)-float(row.value))<.004:row.shown=row.value
		(row.material as ShaderMaterial).set_shader_parameter("value",row.shown);(row.number as Label).text=str(roundi(float(row.shown)*100))
	for card:Dictionary in cards:
		if is_instance_valid(card.new) and (card.new as Control).visible:(card.new as Control).scale=Vector2.ONE*(1+.06-.06*cos(_time*TAU/1.6))
