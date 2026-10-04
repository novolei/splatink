class_name SplatLabFixture
extends RefCounted
## Explicit --ui-fixture only. Values mirror tools/ui-lab.js; never saves user progress.
const DEMO:Array=[
	[0,"shooter",true,0,false,.82,612,3,1], [0,"roller",true,0,true,1,540,2,2],
	[0,"charger",false,3.4,false,.4,301,4,1], [0,"blaster",true,0,false,.66,455,1,0],
	[1,"charger",true,0,false,.5,488,2,1], [1,"shooter",false,1.2,false,.3,390,1,3],
	[1,"blaster",true,0,true,1,520,3,2], [1,"roller",true,0,false,.7,610,0,1]]

static func prepare(host:InkUI)->void:
	host.fixture_mode=true
	host.news_seen="mp-expansion-1"
	host.profile.merge({"name":"Jayden","level":12,"xp":1840,"xp_to_next":5000,"wins":37,"played":64,"hair":6,"skin":6,"outfit":7,"eyes":3,"hat":0,"brows":0},true)
	if is_instance_valid(host.main) and host.main.get("_profile") is Dictionary:
		host.main.get("_profile").merge({"level":12,"xp":1840,"wins":37,"matches":64},true)
	host.options.merge({"stage":"tidewater","map":"tidewater","mapId":"tidewater","time_of_day":"day","timeOfDay":"day","duration":180,"difficulty":"normal","weapon":"shooter","mode":"turf","palette":0},true)
	host.settings.merge(InkUI.DEFAULT_SETTINGS,true)
	host.settings.reduce_motion=false
	host.settings.touch=false
	host.controls_pad=false
	host.style_changed.emit(host.profile.duplicate());host.weapon_changed.emit("shooter")

static func roster(host:InkUI)->Array:
	var result:Array=[];var names:Array=["Jayden"]+Array(SplatUiTheme.catalog().get("bot_names",[])).slice(0,7)
	if names.size()!=8:
		names=["Jayden","Squiddo","Blotch","Marlo","Inky Vee","Pip","Coral","Riptide"]
	for index:int in 8:
		var row:Array=DEMO[index]
		result.append({"name":str(names[index]),"team":row[0],"weapon":row[1],"alive":row[2],"respawn":row[3],"specialReady":row[4],"special":row[5],"specialFrac":row[5],"turf":row[6],"splats":row[7],"deaths":row[8],"isSelf":index==0,"local":index==0})
	return result

static func frame(host:InkUI)->Dictionary:
	var value:Dictionary={"time_left":94.4,"duration":180,"ink":72,"max_ink":100,"hp":100,"max_hp":100,"special":.82,"weapon":"shooter","points":612,"team_color":SplatUiTheme.ORANGE,"enemy_color":SplatUiTheme.BLUE,"roster":roster(host),"prompt":"Hold [SHIFT] to swim","map_name":"Tidewater Plaza","team_names":["Tangerine","Cobalt"]}
	if is_instance_valid(host.main) and host.main.get("minimap") is Node:value.map={"texture":host.main.minimap.get_texture(),"players":[],"local_team":0}
	return value

static func results(host:InkUI)->Dictionary:
	prepare(host)
	var players:Array=[];var names:Array=["Jayden","Squiddo","Blotch","Marlo","Inky Vee","Pip","Coral","Riptide"]
	var weapons:Array=SplatUiTheme.catalog().weapon_order
	for index:int in 8:
		players.append({"name":names[index],"team":0 if index<4 else 1,"weapon":weapons[(index*3+1)%4],"turf":roundi(1450-((index*263)%900)),"splats":(index*7)%8,"deaths":(index*5)%5,"isSelf":index==0,"style":host.profile.duplicate() if index==0 else {"hair":index%8,"skin":index%9,"outfit":index%10,"eyes":index%8,"hat":0,"brows":index%4}})
	return {"mode":"turf","win":true,"won":true,"winner":0,"team":0,"local_team":0,"percents":[52.6,39.1],"colors":[SplatUiTheme.ORANGE,SplatUiTheme.BLUE],"teamNames":["Tangerine","Cobalt"],"mapName":"Tidewater Plaza","map":"tidewater","players":players,"xp":{"gained":1720,"levelBefore":12,"levelAfter":13,"xpBefore":4100,"xpAfter":620,"xpToNextBefore":5000,"xpToNextAfter":5350}}

static func show(host:InkUI,variant:String)->void:
	prepare(host)
	if variant.begins_with("settings-"):
		host.settings_tab=maxi(0,["controls","video","audio","gameplay"].find(variant.trim_prefix("settings-")));host.open_page("settings")
	elif variant.begins_with("locker-"):
		host.locker_tab=maxi(0,["squidkids","hair","face","outfit"].find(variant.trim_prefix("locker-")))
		var key:String=["preset","hair","eyes","outfit"][host.locker_tab]
		host.locker_focus={"key":key,"index":int(host.profile.get(key,0))};host.open_page("locker")
	elif variant=="setup-boss":host.options.mode="boss";host.options.duration=240;host.open_page("setup")
	elif variant=="loading":host.show_loading(.4,"Building the plaza…")
	elif variant=="title":host.show_title()
	elif variant=="main":host.show_menu()
	elif variant.begins_with("news-"):
		host.show_menu();host._news=SplatLabNews.new();host._news.z_index=50;host._news.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);host.root.add_child(host._news);host._news._layout();host._news.build(host)
		if variant=="news-2":host._news.show_card(1)
	elif variant=="lobby":
		var players:Array=[];var portraits:Array=[]
		var rows:Array=roster(host)
		var names:Array=["Jayden","Mako","Tentakool","inkjet","Wavebreaker","Tidal Tia","Blot","Pixel"]
		var weapons:Array=["shooter","roller","charger","blaster","blaster","charger","shooter","roller"]
		for index:int in rows.size():
			var style:Dictionary=host.profile.duplicate() if index==0 else {"hair":index%8,"hat":0,"outfit":index%10,"eyes":index%8,"skin":index%9,"brows":index%4}
			var row:Dictionary=rows[index];row.merge({"id":"fixture-%d"%index,"name":names[index],"weapon":weapons[index],"host":index==0,"ready":index==0 or (index-1)%3!=0,"style":style},true);players.append(row)
			portraits.append({"style":style,"weapon":row.weapon,"team":row.team,"color":SplatUiTheme.ORANGE if int(row.team)==0 else SplatUiTheme.BLUE})
		host.show_lobby({"fixture":true,"code":"CE7QX","you":"fixture-0","host":"fixture-0","mode":"turf","map":"tidewater","time":"day","duration":180,"bots":true,"difficulty":"normal","palette":0,"players":players})
		if is_instance_valid(host.main) and host.main.get("lobby") is Node:host.main.lobby.set_players(portraits,false)
	elif variant=="pause":
		host.show_hud();host.update_match(frame(host));host.toggle_pause()
	elif variant.begins_with("hud"):
		var value:Dictionary=frame(host)
		value.points=0;value.spread=4.0;value.crosshair={"spread":4.0}
		for index:int in value.roster.size():
			var player:Dictionary=value.roster[index]
			player.alive=true;player.respawn=0;player.specialReady=index in [2,5]
			player.weapon=["shooter","roller","charger","blaster","blaster","charger","shooter","roller"][index]
		var path:String="res://assets/ui/fixtures/%s.json"%variant
		if FileAccess.file_exists(path):
			var source:Variant=JSON.parse_string(FileAccess.get_file_as_string(path))
			if source is Dictionary:
				var players:Array=source.get("players",[])
				for index:int in players.size():
					players[index].uv=Vector2(float(players[index].x),float(players[index].y));players[index].local=bool(players[index].get("isSelf",false));players[index].name=value.roster[index].name;players[index].weapon=value.roster[index].weapon
				value.map={"texture":load("res://assets/ui/fixtures/%s-map.png"%variant),"players":players,"local_team":0,"beacons":source.get("beacons",[])}
				value.markers=source.get("markers",[])
		if variant=="hud-charger":value.weapon="charger";value.charge=.72
		host.show_hud();host.hud._chrome.show();host.update_match(value)
		if variant=="hud-map":host.hud.set_map_open(true)
		Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	else:host.open_page(variant)
