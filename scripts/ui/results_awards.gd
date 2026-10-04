class_name SplatResultsAwards
extends RefCounted
## Literal port of computeAwards / computeBossAwards in original src/ui/menu-art.js.
static func compute(players:Array,won:bool,percents:Array,boss:bool=false)->Dictionary:
	var catalog:Dictionary=JSON.parse_string(FileAccess.get_file_as_string("res://resources/themes/awards.json")) as Dictionary
	var meta:Dictionary=catalog.boss if boss else catalog.turf
	var by:Array=[]
	for _p:Variant in players:by.append([])
	if players.is_empty():return {"byPlayer":by,"match":[]}
	var mt:float=maximum(players,"turf");var ms:float=maximum(players,"splats");var md:float=maxf(1,maximum(players,"deaths"))
	var active:Array=[];var zero:Array=[]
	for index:int in players.size():
		var p:Dictionary=players[index]
		var is_active:bool=(float(p.get("damage",0))>0 or float(p.get("turf",0))>=30) if boss else (float(p.get("turf",0))>=30 or int(p.get("splats",0))>0)
		if is_active:
			active.append(index)
			if int(p.get("deaths",0))==0:zero.append(index)
	if not zero.is_empty() and zero.size()<=3:
		for index:int in zero:give(by,index,"unsinkable" if boss else "untouchable","Never splatted",meta)
	elif zero.is_empty() and not active.is_empty():
		var min_d:int=2147483647;var survivors:Array=[]
		for index:int in active:min_d=mini(min_d,int(players[index].get("deaths",0)))
		for index:int in active:
			if int(players[index].get("deaths",0))==min_d:survivors.append(index)
		if survivors.size()==1:give(by,survivors[0],"survivor","Splatted %d×"%min_d,meta)
	var self_team:int=0
	for p:Dictionary in players:
		if bool(p.get("isSelf",false)):self_team=int(p.get("team",0));break
	var win_team:int=self_team if won else 1-self_team
	var best:int=-1;var best_score:float=-INF
	if boss:
		var damage:float=maximum(players,"damage");var weak:float=maximum(players,"weakHits")
		for index:int in players.size():
			var p:Dictionary=players[index]
			if damage>0 and float(p.get("damage",0))==damage:give(by,index,"heavy","%d damage"%damage,meta)
			if weak>=3 and float(p.get("weakHits",0))==weak:give(by,index,"crit","%d weak-point hits"%weak,meta)
			if ms>=2 and float(p.get("splats",0))==ms:give(by,index,"brood","%d crablets"%ms,meta)
			if mt>0 and float(p.get("turf",0))==mt:give(by,index,"cleaner","%dp inked"%mt,meta)
			if float(p.get("damage",0))<=0 and float(p.get("turf",0))<=0:continue
			var score:float=float(p.get("damage",0))/maxf(1,damage)+.35*float(p.get("weakHits",0))/maxf(1,weak)+.2*float(p.get("splats",0))/maxf(1,ms)+.15*float(p.get("turf",0))/maxf(1,mt)-.25*float(p.get("deaths",0))/md
			if score>best_score+1e-9:best=index;best_score=score
	else:
		var crowned:Array=[]
		for index:int in players.size():
			var p:Dictionary=players[index]
			if mt>0 and float(p.get("turf",0))==mt:give(by,index,"turf","%dp inked"%mt,meta);crowned.append(index)
			if ms>0 and float(p.get("splats",0))==ms:give(by,index,"splats","%d splat%s"%[int(ms),"" if ms==1 else "s"],meta)
			if int(p.get("team",0))==win_team and (float(p.get("turf",0))>0 or float(p.get("splats",0))>0):
				var score:float=float(p.get("turf",0))/maxf(1,mt)+.55*float(p.get("splats",0))/maxf(1,ms)-.3*float(p.get("deaths",0))/md
				if score>best_score+1e-9 or (absf(score-best_score)<1e-9 and float(p.get("turf",0))>float(players[best].get("turf",0))):best=index;best_score=score
		for team:int in 2:
			var team_max:float=0;var has_crown:bool=false
			for index:int in players.size():
				if int(players[index].get("team",0))!=team:continue
				team_max=maxf(team_max,float(players[index].get("turf",0)))
				if index in crowned:has_crown=true
			if team_max<=0 or has_crown:continue
			for index:int in players.size():
				if int(players[index].get("team",0))==team and float(players[index].get("turf",0))==team_max:give(by,index,"inker","%dp inked"%team_max,meta)
		var order:Array=[]
		for index:int in players.size():order.append(index)
		order.sort_custom(func(a:int,b:int)->bool:return float(players[a].get("turf",0))>float(players[b].get("turf",0)))
		for rank:int in mini(3,order.size()):
			var index:int=order[rank]
			if int(players[index].get("splats",0))==0 and float(players[index].get("turf",0))>0:give(by,index,"pure","%dp · 0 splats"%float(players[index].get("turf",0)),meta)
	if best>=0:give(by,best,"mvp","Top all-round score",meta)
	var order:Array=["mvp","heavy","crit","brood","unsinkable","survivor","cleaner"] if boss else ["mvp","turf","splats","inker","untouchable","survivor","pure"]
	for list:Array in by:list.sort_custom(func(a:Dictionary,b:Dictionary)->bool:return order.find(a.id)<order.find(b.id))
	var tags:Array=[]
	if not boss:
		var margin:float=absf(float(percents[0])-float(percents[1]))
		if margin<3:tags.append({"id":"close","label":"PHOTO FINISH","icon":"stopwatch","value":"%.1f%% margin"%margin})
		elif margin>=20:tags.append({"id":"landslide","label":"LANDSLIDE","icon":"wave","value":"+%.1f%%"%margin})
	return {"byPlayer":by,"match":tags}

static func maximum(players:Array,key:String)->float:
	var result:float=0
	for p:Dictionary in players:result=maxf(result,float(p.get(key,0)))
	return result

static func give(by:Array,index:int,id:String,value:String,meta:Dictionary)->void:
	var award:Dictionary=(meta[id] as Dictionary).duplicate();award.id=id;award.value=value
	by[index].append(award)
