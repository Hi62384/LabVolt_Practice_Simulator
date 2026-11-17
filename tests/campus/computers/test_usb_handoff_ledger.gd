extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")
func _initialize() -> void:
	var source=Profile.new();source.open("usb-handoff-source")
	var target=Profile.new();target.open("usb-handoff-target")
	source.data.dollars=1000;source.buy_usb(8)
	var id: String=source.data.dorm.usb_drives.keys()[0]
	source.data.dorm.carry_items.erase("usb:"+id);source.data.dorm.usb_drives[id].location="handoff"
	source.data.usb_handoff_pending={id:"c".repeat(32)}
	var stale_source: Dictionary=source.data.duplicate(true)
	stale_source.dorm.usb_drives[id].location="handoff"
	var stale_target: Dictionary=target.data.duplicate(true)
	var ledger=Ledger.new();var ok: bool=ledger.open("user://usb-handoff-ledger")==OK
	var source_owner: String=source.data.dorm.owner;var target_owner: String=target.data.dorm.owner
	var source_secret: String="a".repeat(64);var target_secret: String="b".repeat(64)
	ok=ok and ledger.bind(2,source_owner,source_secret,source.data).get("ok",false)
	ok=ok and ledger.bind(3,target_owner,target_secret,target.data).get("ok",false)
	var result: Dictionary=ledger.commit_usb_handoff(2,3,id,"c".repeat(32))
	ok=ok and result.get("ok",false)
	ok=ok and not ledger.account(2).profile.dorm.usb_drives.has(id) and ledger.account(3).profile.dorm.usb_drives[id].location=="hotbar"
	ledger.unbind(2);ledger.unbind(3)
	var source_return: Dictionary=ledger.bind(2,source_owner,source_secret,stale_source)
	var target_return: Dictionary=ledger.bind(3,target_owner,target_secret,stale_target)
	ok=ok and source_return.get("ok",false) and not source_return.profile.dorm.usb_drives.has(id)
	ok=ok and target_return.get("ok",false) and target_return.profile.dorm.usb_drives[id].location=="hotbar"
	var reopened=Ledger.new();ok=ok and reopened.open("user://usb-handoff-ledger")==OK
	ok=ok and not reopened.state.accounts[source_owner].profile.dorm.usb_drives.has(id) and reopened.state.accounts[target_owner].profile.dorm.usb_drives.has(id)
	var later_target: Dictionary=target_return.profile.duplicate(true)
	later_target.dorm.carry_items.erase("usb:"+id);later_target.dorm.usb_drives.erase(id)
	ledger.unbind(3)
	var after_later_move: Dictionary=ledger.bind(3,target_owner,target_secret,later_target)
	ok=ok and after_later_move.get("ok",false) and not after_later_move.profile.dorm.usb_drives.has(id)
	print("USB_HANDOFF_LEDGER ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
