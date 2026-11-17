extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
func _initialize() -> void:
	var profile=Profile.new();profile.open("phone-purchase-reconcile")
	profile.data.dollars=10000
	var owner: String=profile.data.dorm.owner;var id: String="d".repeat(32);var secret: String="a".repeat(64)
	var ledger=Ledger.new();var ok: bool=ledger.open("user://phone-purchase-ledger")==OK
	ok=ok and ledger.bind(2,owner,secret,profile.data).get("ok",false)
	var stale: Dictionary=profile.data.duplicate(true);stale.phone_purchase_pending={id:{"tier":"standard","host":"host-a"}}
	var purchased: Dictionary=ledger.transact(2,"purchase-fixture","buy_smartphone",["standard",6,id])
	if not purchased.get("ok",false):
		push_error("Phone purchase fixture failed: "+str(purchased.get("error","unknown")))
		quit(1);return
	ok=ok and purchased.get("ok",false)
	var balance: int=int(purchased.profile.dollars)
	ledger.unbind(2)
	var recovered: Dictionary=ledger.bind(2,owner,secret,stale)
	if not recovered.get("ok",false):
		push_error("Phone reconnect fixture failed: "+str(recovered.get("error","unknown")))
		quit(1);return
	ok=ok and recovered.get("ok",false) and recovered.profile.dorm.smartphones.has(id) and int(recovered.profile.dollars)==balance and not recovered.profile.get("phone_purchase_pending",{}).has(id)
	ledger.unbind(2)
	var again: Dictionary=ledger.bind(2,owner,secret,recovered.profile)
	ok=ok and again.get("ok",false) and int(again.profile.dollars)==balance and again.profile.dorm.smartphones.size()==1
	var uncommitted: String="f".repeat(32)
	var waiting: Dictionary=again.profile.duplicate(true);waiting.phone_purchase_pending={uncommitted:{"tier":"basic","host":"host-a"}}
	ledger.unbind(2)
	var cancelled: Dictionary=ledger.bind(2,owner,secret,waiting)
	ok=ok and cancelled.get("ok",false) and cancelled.profile.get("phone_purchase_resolved",{}).has(uncommitted)
	profile.data=waiting;profile.authority_revision=-1
	ok=ok and profile.accept_authority(cancelled)==OK and not profile.data.get("phone_purchase_pending",{}).has(uncommitted)
	print("PHONE_PURCHASE_RECONCILE ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
