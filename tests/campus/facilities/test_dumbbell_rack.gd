extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
var profile=Host.empty_profile()
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 game.front.entered();game.player.enabled=true
 var weights=game.gym_weights
 game.player.global_position=weights.RACK
 assert(weights.items.size()==24)
 weights.request("pickup",8)
 assert(weights.items[8].where=="held" and weights.items[8].owner==1)
 assert(absf(weights.held_mass(1)-25.0*2*.45359237)<.0001)
 game.hotbar._process(.01)
 assert(game.hotbar.slots.any(func(slot):return slot.get("kind","")=="gym_dumbbells" and slot.id==8))
 weights.request("stow",8);assert(weights.items[8].where=="stowed" and weights.held_mass(1)==0)
 weights.request("equip",8);assert(weights.items[8].where=="held")
 var host=Host.new();host.authority=func():return true
 host.context=func(_p):return {"identity":"student","position":Vector3.ZERO,"room_id":"gym","allowed":true,"grounded":true}
 host.load_profile=func(_i):return profile.duplicate(true)
 host.commit_profile=func(_i,_d,p):profile=p.duplicate(true);return true
 host.dumbbell_mass=func(peer):return weights.held_mass(peer)
 host.anchors={"curl":{"kind":"curl","room_id":"gym","position":Vector3.ZERO}}
 var result=host.act(1,{"op":"start","station":"curl","exercise":"curl","weight":5,"sequence":1})
 assert(result.ok and absf(host.active[1].weight-weights.held_mass(1))<.0001)
 weights.request("return",8);assert(weights.items[8].where=="rack" and weights.items[8].owner==0)
 print("PASS dumbbell pickup, hotbar, stow, combined mass and return")
 game.queue_free();await process_frame;quit()
