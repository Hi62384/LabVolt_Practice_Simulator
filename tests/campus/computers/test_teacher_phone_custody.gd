extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Ledger=preload("res://scripts/inventory_authority/ledger.gd")

func _initialize() -> void:
	var profile=Profile.new()
	profile.open("teacher-phone-custody-fixture")
	var saved: Dictionary=profile.data.duplicate(true)
	var id: String="a".repeat(32)
	saved.dorm.smartphones={id:{"tier":"standard","location":"hotbar"}}
	saved.dorm.carry_items=["phone:"+id]
	saved.dorm.teacher_phone_custody={"id":id,"room":"ac_lab","teacher":"dr_volts"}
	var ok: bool=Dorm.valid(saved.dorm,saved.get("inventory",{}),saved.get("component_instances",{}))
	var moved: Dictionary=saved.duplicate(true)
	moved.dorm.carry_items=[]
	moved.dorm.smartphones[id].location="cabinet"
	ok=ok and not Dorm.valid(moved.dorm,moved.get("inventory",{}),moved.get("component_instances",{}))
	profile.data=saved
	ok=ok and profile.save()==OK
	var reopened=Profile.new()
	reopened.open("teacher-phone-custody-fixture")
	ok=ok and reopened.data.dorm.get("teacher_phone_custody",{}).get("id","")==id
	var ledger=Ledger.new()
	ok=ok and ledger.open("user://teacher-phone-custody-ledger")==OK
	var owner: String=str(saved.dorm.owner)
	var secret: String="b".repeat(64)
	var joined: Dictionary=ledger.bind(2,owner,secret,saved)
	ok=ok and bool(joined.get("ok",false)) and joined.get("profile",{}).get("dorm",{}).get("teacher_phone_custody",{}).get("id","")==id
	ledger.unbind(2)
	var rejoined: Dictionary=ledger.bind(2,owner,secret,saved)
	ok=ok and bool(rejoined.get("ok",false)) and rejoined.get("profile",{}).get("dorm",{}).get("teacher_phone_custody",{}).get("id","")==id
	reopened.data.dorm.erase("teacher_phone_custody")
	ok=ok and Dorm.valid(reopened.data.dorm,reopened.data.get("inventory",{}),reopened.data.get("component_instances",{}))
	print("TEACHER_PHONE_CUSTODY ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
