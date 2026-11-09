extends SceneTree
# Synthetic fixture. No profile.open(), user save paths, engine scenes or live data.
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Board=preload("res://scripts/breadboard_model.gd")
class MemoryHistory:
	extends RefCounted
	func lookup_op(state: Dictionary,owner: String,id: String) -> Dictionary:
		var receipts: Dictionary=state.accounts.get(owner,{}).get("receipts",{})
		return {"ok":true,"found":receipts.has(id),"value":receipts.get(id)}
class MemoryLedger:
	extends "res://scripts/inventory_authority/ledger.gd"
	var reject := false
	var commits := 0
	func _init() -> void:receipt_history=MemoryHistory.new()
	func persist(next: Dictionary) -> bool:
		if reject:return false
		state=next.duplicate(true);commits+=1;return true
var checks := 0
func check(value: bool,label: String) -> void:
	checks+=1
	assert(value,label)
func initial() -> Dictionary:
	return {"schema":1,"dollars":137,"inventory":{"r1000":8,"r220":4},"capacity":40,"equipped":"starter","kits":{"starter":{"name":"Starter","items":{"r1000":8},"board":Board.empty()}},"notebook":"keep notes","programs":{"test":"keep code"},"reward_ids":{"old":50},"analyzer":false}
func _initialize() -> void:
	var a := "a".repeat(48);var b := "b".repeat(48);var secret := "1".repeat(64)
	var legacy := initial();var before := legacy.duplicate(true)
	var migration := Dorm.migrate(legacy,a)
	check(migration.ok and migration.changed,"legacy migrated")
	check(legacy==before,"migration input immutable")
	for key in before:check(migration.profile[key]==before[key],"unrelated field "+str(key))
	check(Dorm.migrate(migration.profile,a).changed==false,"migration idempotent")
	check(not Dorm.migrate(migration.profile,b).ok,"identity conflict")
	var l := MemoryLedger.new()
	check(l.bind(11,a,secret,legacy).ok,"first enrollment")
	check(l.account(11).profile.dorm.room_id=="dorm_"+a,"assignment before returned snapshot")
	var room: String=l.account(11).profile.dorm.room_id
	check(not l.bind(12,a,secret,legacy).ok,"connected clone rejected")
	l.unbind(11)
	check(l.bind(99,a,secret,legacy).ok,"stale peer rejoin")
	check(l.account(11).is_empty() and l.account(99).profile.dorm.room_id==room,"stable room independent of peer")
	var store := {"op":"storage","revision":0,"item":"r1000","delta":3,"instances":[]}
	check(l.transact(99,"store","dorm",[store]).ok,"store")
	check(l.free_stock(99,"r1000")==5 and l.account(99).profile.inventory.r1000==8,"allocation conserves master inventory")
	check(l.transact(99,"store","dorm",[store]).ok and l.account(99).profile.dorm.storage.r1000==3,"receipt replay no duplicate")
	var changed := store.duplicate();changed.delta=4
	check(not l.transact(99,"store","dorm",[changed]).ok,"changed replay rejected")
	var snapshot := l.state.duplicate(true);l.reject=true
	check(not l.transact(99,"fail","dorm",[{"op":"storage","revision":1,"item":"r1000","delta":1}]).ok,"save failure reported")
	check(l.state==snapshot,"save failure changes neither inventory nor allocation")
	l.reject=false
	check(l.transact(99,"retrieve","dorm",[{"op":"storage","revision":1,"item":"r1000","delta":-3}]).ok,"retrieve")
	check(l.free_stock(99,"r1000")==8 and l.account(99).profile.inventory.r1000==8,"retrieve conservation")
	var restored := MemoryLedger.new();restored.state=l.state.duplicate(true)
	check(restored.bind(41,a,secret,legacy).ok and restored.account(41).profile.dorm.room_id==room,"synthetic restart")
	for index in 24:
		var id := ("%048x"%(index+100))
		check(restored.bind(100+index,id,("%064x"%(index+100)),initial()).ok,"historical owner "+str(index))
	check(restored.state.accounts.size()==25,"logical rooms exceed eight entrances")
	var d: Dictionary=restored.account(41).profile.dorm
	check(not Dorm.may_enter(d,a,b),"private visitor rejected")
	check(Dorm.may_enter(d,a,a),"owner allowed")
	var invited := d.duplicate(true);invited.policy="Invited";invited.invited=[b]
	check(Dorm.may_enter(invited,a,b),"explicit invite")
	check(not Dorm.may_enter(invited,a,"peer:41"),"peer string is not authenticated identity")
	check(not restored.transact(41,"bad-policy","dorm",[{"op":"policy","revision":2,"value":"Friends"}]).ok,"unsupported friends policy")
	var bad := {"op":"edit","revision":2,"edit":{"op":"move","item":{"id":"bed","kind":"bed","x":-3.0,"z":0.0,"rotation":0}}}
	check(not restored.transact(41,"blocked-door","dorm",[bad]).ok,"placement blocks doorway")
	var public := Dorm.public_room(restored.account(41).profile)
	for key in ["inventory","notebook","programs","storage","instances","credential"]:
		check(not public.has(key),"public excludes "+key)
	var specific := initial();specific.component_instances={"unique":{"type":"r1000","root":"board/r","component_runtime":{}}}
	var u := MemoryLedger.new();check(u.bind(2,b,"2".repeat(64),specific).ok,"unique instance enrollment")
	check(u.transact(2,"unique-store","dorm",[{"op":"storage","revision":0,"item":"r1000","delta":1,"instances":["unique"]}]).ok,"specific instance store")
	check(u.account(2).profile.component_instances.has("unique"),"instance bytes stay in master registry")
	check(not u.transact(2,"unique-twice","dorm",[{"op":"storage","revision":1,"item":"r1000","delta":1,"instances":["unique"]}]).ok,"instance cannot occupy storage twice")
	check(not u.transact(2,"overflow","dorm",[{"op":"storage","revision":1,"item":"r1000","delta":8}]).ok,"overcapacity rejects")
	check(not u.transact(999,"unbound","dorm",[{"op":"policy","revision":0,"value":"Open"}]).ok,"stale unbound peer rejected")
	var forged := u.account(2).profile.duplicate(true);forged.dorm.policy="Open";forged.dollars=9999
	check(u.transact(2,"metadata-forge","metadata",[forged]).ok,"metadata merge")
	check(u.account(2).profile.dorm.policy=="Private" and u.account(2).profile.dollars==137,"metadata cannot overwrite ownership/privacy/economy")
	var failed := MemoryLedger.new();failed.reject=true
	check(not failed.bind(3,a,secret,initial()).ok and failed.bindings.is_empty() and failed.state.accounts.is_empty(),"failed first enrollment publishes no binding")
	print("Synthetic in-memory authority checks: ",checks)
	quit()

