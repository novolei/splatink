extends SceneTree
const Director=preload("res://scripts/game/ink_boss_audio.gd")
class AudioStub:
	extends Node
	var sounds:Array=[]
	var loops:Dictionary={}
	var music:Array=[]
	func play(name:String,options:Dictionary={}) -> void:sounds.append({"name":name,"options":options})
	func loop(key:String,name:String,options:Dictionary={}) -> void:loops[key]={"name":name,"options":options}
	func stop_loop(key:String) -> void:loops.erase(key)
	func play_music(track:String,fade:float=1.0) -> void:music.append({"track":track,"fade":fade})
	func stop_music(fade:float=.4) -> void:music.append({"track":"","fade":fade})
class GameStub:
	extends Node
	var state:String="intro"
class BossStub:
	extends Node3D
	var match_node:Node
	func get_socket(_name:String,fallback:Vector3=Vector3.ZERO) -> Vector3:return fallback
class ActorStub:
	extends Node
	var is_local:bool=true
var checks:int=0
var failures:Array[String]=[]
func _initialize() -> void:call_deferred("run_contract")
func expect(value:bool,message:String) -> void:
	checks+=1
	if not value:failures.append(message);push_error(message)
func run_contract() -> void:
	var owner:=AudioStub.new();root.add_child(owner)
	var game:=GameStub.new();root.add_child(game)
	var boss:=BossStub.new();root.add_child(boss);boss.match_node=game
	var actor:=ActorStub.new();root.add_child(actor)
	var director:=Director.new();director.configure(owner)
	expect(not director.on_event("shoot_shooter",{}),"Non-Boss gun sounds stay with ordinary source audio")
	director.on_event("boss:spawn",{"boss":boss})
	director.on_event("boss:intro",{"boss":boss})
	expect(owner.sounds.size()==3,"Boss intro schedules title, deck burst and roar")
	expect(owner.sounds[1].options.delay==.35 and owner.sounds[2].options.delay==.1,"Source intro delayed roar and deck-burst times")
	director.update(.01)
	expect(owner.music.is_empty(),"Boss intro does not prematurely start battle music")
	game.state="playing";director.update(.01)
	expect(owner.music.back().track=="boss","Playing begins Boss phase1music")
	director.on_event("boss:phase",{"boss":boss,"phase":2})
	expect(owner.music.back().track=="boss_2" and director.phase==2,"Phase2switches source Boss track")
	director.on_event("boss:move",{"boss":boss,"id":"sweep","phase":"act","dur":2.1})
	director.update(.01)
	expect(owner.loops.has("boss_sweep") and owner.loops.boss_sweep.name=="boss_cannon_sweep","Sweep active loop follows cannon socket")
	director.on_event("boss:move",{"boss":boss,"id":"sweep","phase":"rec"})
	expect(not owner.loops.has("boss_sweep"),"Sweep recovery stops the active loop")
	owner.sounds.clear()
	director.on_event("boss:hit",{"attacker":actor,"weak":false})
	director.on_event("boss:hit",{"attacker":actor,"weak":false})
	expect(owner.sounds.size()==1 and owner.sounds[0].name=="boss_hit","Source local Boss hit tick throttles repeated same-frame hits")
	director.on_event("boss:stun",{"boss":boss,"dur":2.0})
	director.update(.34)
	expect(not owner.loops.has("boss_dizzy"),"Dizzy loop waits source.35seconds")
	director.update(.02)
	expect(owner.loops.has("boss_dizzy"),"Dizzy loop starts after crash delay")
	director.on_event("boss:defeat",{"boss":boss})
	expect(owner.loops.is_empty() and owner.music.back().track=="","Defeat retires attack loops and fades music")
	expect(owner.sounds.back().name=="boss_sunk" and owner.sounds.back().options.delay==1.35,"Defeat schedules source sinking accent")
	director.clear()
	expect(director.boss==null and director.loops.is_empty() and director.delayed.is_empty(),"Director clear cannot retain old fight loops or delayed callbacks")
	print("AUDIO CONTRACT: %d checks, %d failures"%[checks,failures.size()])
	quit(0 if failures.is_empty() else 1)
