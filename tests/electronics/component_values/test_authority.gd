extends SceneTree
## DEFERRED. Requires shared_integration.patch. In-memory ledger, no save files.
const Values=preload("res://scripts/electronics/component_values/values.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Board=preload("res://scripts/breadboard_model.gd")

class MemoryLedger:
	extends "res://scripts/inventory_authority/ledger.gd"
	var reject_commit := false
	func persist(next: Dictionary) -> bool:
		if reject_commit:return false
		state=next.duplicate(true)
		return true

var checks := 0
func check(value: bool, message: String) -> void:
	checks+=1
	assert(value,message)

func _init() -> void:
	var identity := "a".repeat(48)
	var initial := {"schema":1,"dollars":17,"inventory":{"r1000":8},"capacity":40,"equipped":"starter","kits":{"starter":{"name":"Starter","items":{"r1000":8},"board":Board.empty()}},"notebook":"","reward_ids":{},"analyzer":false}
	check(Profile.valid(initial),"Legacy fixture valid without migration")
	var ledger := MemoryLedger.new()
	ledger.receipt_history.configured=true
	ledger.state={"schema":2,"receipt_archive":{"head":"","segments":0},"transactions":{},"accounts":{identity:{"credential":"fixture","profile":initial.duplicate(true),"revision":0,"receipts":{},"deployment":{}}}}
	ledger.bindings={11:identity}
	var configured := Values.configure("r1000",{"value":"333.125 Ω"},Catalog.all())
	var args: Array=["r1000",{"value":"333.125 Ω"},1000]
	check(not ledger.transact(99,"unbound","buy_configured",args).ok,"Unauthenticated purchase rejected")
	var result := ledger.transact(11,"configured-one","buy_configured",args)
	check(result.ok and result.profile.inventory[configured.id]==1000,"Host accepts arbitrary value and quantity")
	check(result.profile.dollars==17,"Unlimited purchasing preserves stored dollars")
	check(result.profile.inventory.r1000==8,"Legacy stock identity and count unchanged")
	check(result.profile.kits==initial.kits,"Purchasing does not silently equip or exceed a kit")
	var after := ledger.state.duplicate(true)
	check(ledger.transact(11,"configured-one","buy_configured",args).profile.inventory[configured.id]==1000,"Replay adds no stock")
	check(ledger.state==after,"Replay does not mutate revision or receipts")
	check(not ledger.transact(11,"configured-one","buy_configured",["r1000",{"value":"334 Ω"},1000]).ok,"Changed request with same receipt rejected")
	check(ledger.state==after,"Replay conflict leaves complete state untouched")
	ledger.bindings.erase(11);ledger.bindings[22]=identity
	check(ledger.transact(22,"configured-one","buy_configured",args).profile.inventory[configured.id]==1000,"Authenticated identity retains receipt across peer change")
	for bad in [0,-1,1.5,"1.5",100001,NAN,INF,true,{},[]]:
		var before := ledger.state.duplicate(true)
		check(not ledger.transact(22,"bad-"+str(checks),"buy_configured",["r1000",{"value":"333 Ω"},bad]).ok,"Hostile quantity blocked")
		check(ledger.state==before,"Invalid quantity cannot partially debit or allocate")
	for settings in [{"price":0},{"rarity":"Legendary"},{"value":"0 Ω"},{"value":"NaN"},{"value":-100},{"value":"1e999"}]:
		var before := ledger.state.duplicate(true)
		check(not ledger.transact(22,"bad-field-"+str(checks),"buy_configured",["r1000",settings,1]).ok,"Hostile setting blocked")
		check(ledger.state==before,"Invalid setting cannot partially mutate")
	ledger.reject_commit=true
	var before := ledger.state.duplicate(true)
	check(not ledger.transact(22,"failed-commit","buy_configured",["r1000",{"value":"335 Ω"},1]).ok,"Commit failure reported")
	check(ledger.state==before,"Commit failure preserves balance, stock, revision and receipt")
	ledger.reject_commit=false
	check(ledger.transact(22,"failed-commit","buy_configured",["r1000",{"value":"335 Ω"},1]).ok,"Same failed receipt can safely retry")
	var malformed := initial.duplicate(true);malformed.inventory["cv1:r1000:value=NaN"]=1
	check(not Profile.valid(malformed),"Malformed procedural saved identity rejected")
	var p := Profile.new();p.data=initial.duplicate(true)
	check(p.buy_configured("r1000",{"value":"333 Ω"},1)=="Authenticated host required" and p.data==initial,"Direct nonauthority cannot allocate")
	print("component_values deferred in-memory authority fixtures passed: ",checks)
	quit()
