extends SceneTree
const Router=preload("res://scripts/campus/dorms/interactions/personal_station_router.gd")
const Fallback=preload("res://scripts/campus/dorms/interactions/shop_fallback_policy.gd")
class Provider:
	extends RefCounted
	var assignment:=1
	var revision:=1
	func room_for_peer(peer:int)->String:return "dorm_00" if peer==assignment else ""
	func authenticated_identity(peer:int)->String:return "peer:"+str(peer) if peer==assignment else ""
	func owner_identity(room:String)->String:return "peer:"+str(assignment) if room=="dorm_00" else ""
	func assignment_revision()->int:return revision
class Electronics:
	extends Node
	var active:=false
	var current_page:=""
	var opened:Array=[]
	func open(page:String)->void:active=true;current_page=page;opened.append(page)
	func close()->void:active=false
class GameFixture:
	extends Node
	var electronics:Electronics
var failures:=0
func check(ok:bool,label:String)->void:
	if not ok:failures+=1;printerr("FAIL "+label)
func _initialize()->void:call_deferred("run")
func run()->void:
	var game:=GameFixture.new();root.add_child(game)
	game.electronics=Electronics.new();game.add_child(game.electronics)
	var provider:=Provider.new()
	var router:=Router.new();game.add_child(router);router.configure(game,provider)
	var stations:Dictionary={}
	for kind in ["kit_workshop","loadout","notes"]:
		var station:=StaticBody3D.new();game.add_child(station)
		check(router.register_station(station,"dorm_00",kind),"register "+kind)
		stations[kind]=station
	var legacy:=StaticBody3D.new();game.add_child(legacy);legacy.set_meta("page","notes")
	check(router.replacements_ready_for_local_owner(),"all personal routes ready")
	Fallback.filter_legacy_station(router,legacy)
	check(not legacy.visible and legacy.collision_layer==0,"legacy target retired after replacement")
	check(router.interact(stations.notes) and game.electronics.opened==["notes"],"owner opens own notes route")
	provider.assignment=2;provider.revision+=1;router.assignment_changed()
	check(not game.electronics.active,"departure closes stale notes UI")
	check(router.interact(stations.loadout) and game.electronics.opened==["notes"],"visitor cannot open resident loadout")
	check(router.interact(stations.notes) and game.electronics.opened==["notes"],"visitor cannot open resident notes")
	check(not router.replacements_ready_for_local_owner(),"old owner loses personal routes")
	Fallback.filter_legacy_station(router,legacy)
	check(legacy.visible and legacy.collision_layer==4,"legacy target restores without local assignment")
	provider.assignment=1;provider.revision+=1;router.assignment_changed()
	router.unregister_station(stations.kit_workshop)
	check(not router.replacements_ready_for_local_owner(),"incomplete replacement fails readiness")
	Fallback.filter_legacy_station(router,legacy)
	check(legacy.visible and legacy.collision_layer==4,"legacy target remains during incomplete setup")
	check(router.interact(stations.kit_workshop) and game.electronics.opened==["notes"],"unregistered stale target cannot open kit")
	check(router.register_station(stations.kit_workshop,"dorm_00","kit_workshop"),"re-register kit route")
	check(router.interact(stations.kit_workshop) and game.electronics.opened==["notes","kits"],"owner kit route restored")
	print("DORM STATION PRIVACY failures=%d"%failures);quit(1 if failures else 0)
