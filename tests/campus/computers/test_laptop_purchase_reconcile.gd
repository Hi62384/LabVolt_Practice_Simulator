extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
func _initialize() -> void:
	var profile=Profile.new();profile.open("laptop-purchase-reconcile")
	profile.data.dollars=10000
	var owner: String=profile.data.dorm.owner;var id: String="d".repeat(32);var secret: String="a".repeat(64)
	var ledger=Ledger.new();var ok: bool=ledger.open("user://laptop-purchase-ledger")==OK
	ok=ok and ledger.bind(2,owner,secret,profile.data).get("ok",false)
	var stale: Dictionary=profile.data.duplicate(true);stale.laptop_purchase_pending={id:{"tier":"standard","host":"host-a"}}
	var purchased: Dictionary=ledger.transact(2,"purchase-fixture","buy_portable_laptop",["standard",6,id])
	ok=ok and purchased.get("ok",false)
	var balance: int=int(purchased.profile.dollars)
	ledger.unbind(2)
	var recovered: Dictionary=ledger.bind(2,owner,secret,stale)
	ok=ok and recovered.get("ok",false) and recovered.profile.dorm.portable_laptops.has(id) and int(recovered.profile.dollars)==balance and not recovered.profile.get("laptop_purchase_pending",{}).has(id)
	ledger.unbind(2)
	var again: Dictionary=ledger.bind(2,owner,secret,recovered.profile)
	ok=ok and again.get("ok",false) and int(again.profile.dollars)==balance and again.profile.dorm.portable_laptops.size()==1
	var uncommitted: String="f".repeat(32)
	var waiting: Dictionary=again.profile.duplicate(true);waiting.laptop_purchase_pending={uncommitted:{"tier":"basic","host":"host-a"}}
	ledger.unbind(2)
	var cancelled: Dictionary=ledger.bind(2,owner,secret,waiting)
	ok=ok and cancelled.get("ok",false) and cancelled.profile.get("laptop_purchase_resolved",{}).has(uncommitted)
	profile.data=waiting;profile.authority_revision=-1
	ok=ok and profile.accept_authority(cancelled)==OK and not profile.data.get("laptop_purchase_pending",{}).has(uncommitted)
	print("LAPTOP_PURCHASE_RECONCILE ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
