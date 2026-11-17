extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const Drive=preload("res://scripts/campus/computers/device_filesystem.gd")
func _initialize() -> void:
	var profile=Profile.new();profile.open("usb-purchase-reconcile")
	profile.data.dollars=1000
	var owner: String=profile.data.dorm.owner;var id: String="d".repeat(32);var secret: String="a".repeat(64)
	var ledger=Ledger.new();var ok: bool=ledger.open("user://usb-purchase-ledger")==OK
	ok=ok and ledger.bind(2,owner,secret,profile.data).get("ok",false)
	ok=ok and Archive.save(owner,id,"USB drive",8,Drive.new(8*1024*1024))==OK
	var stale: Dictionary=profile.data.duplicate(true);stale.usb_purchase_pending={id:8}
	var purchased: Dictionary=ledger.transact(2,"purchase-fixture","buy_usb",[8,6,id])
	if not purchased.get("ok",false):
		push_error("USB purchase fixture failed: "+str(purchased.get("error","unknown")))
		quit(1);return
	ok=ok and purchased.get("ok",false)
	var expected_balance: int=int(purchased.profile.dollars)
	ledger.unbind(2)
	var recovered: Dictionary=ledger.bind(2,owner,secret,stale)
	if not recovered.get("ok",false):
		push_error("USB reconnect fixture failed: "+str(recovered.get("error","unknown")))
		quit(1);return
	ok=ok and recovered.get("ok",false) and recovered.profile.dorm.usb_drives.has(id) and int(recovered.profile.dollars)==expected_balance and not recovered.profile.get("usb_purchase_pending",{}).has(id)
	ledger.unbind(2)
	var again: Dictionary=ledger.bind(2,owner,secret,recovered.profile)
	ok=ok and again.get("ok",false) and int(again.profile.dollars)==expected_balance
	var uncommitted: String="f".repeat(32)
	var waiting: Dictionary=again.profile.duplicate(true);waiting.usb_purchase_pending={uncommitted:8}
	ledger.unbind(2)
	var cancelled: Dictionary=ledger.bind(2,owner,secret,waiting)
	ok=ok and cancelled.get("ok",false) and cancelled.profile.get("usb_purchase_resolved",{}).has(uncommitted)
	profile.data=waiting;profile.authority_revision=-1
	ok=ok and profile.accept_authority(cancelled)==OK and not profile.data.get("usb_purchase_pending",{}).has(uncommitted)
	print("USB_PURCHASE_RECONCILE ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
