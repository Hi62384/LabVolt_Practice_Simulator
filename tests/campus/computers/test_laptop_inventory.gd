extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Laptops=preload("res://scripts/campus/computers/laptop_inventory.gd")
func _initialize() -> void:
	var profile=Profile.new();profile.open("portable-laptop-inventory")
	profile.data.dollars=10000
	for tier in ["basic","standard","premium"]:profile.buy_portable_laptop(tier)
	var items: Dictionary=profile.data.dorm.get("portable_laptops",{})
	var ok: bool=items.size()==3 and Profile.valid(profile.data)
	var tiers:=[]
	for id in items:tiers.append(items[id].tier)
	tiers.sort();ok=ok and tiers==["basic","premium","standard"]
	var id: String=items.keys()[0]
	var stored: Dictionary=Dorm.apply_intent(profile.data,profile.data.dorm.owner,{"op":"carry_item","item":"laptop:"+id,"carry":false,"revision":profile.data.dorm.revision})
	ok=ok and stored.get("ok",false) and stored.profile.dorm.portable_laptops[id].location=="cabinet"
	var before: Dictionary=profile.data.duplicate(true);profile.buy_portable_laptop("invalid")
	ok=ok and not profile.operation_succeeded and profile.data==before
	ok=ok and Laptops.TIERS.basic.delay_ms>Laptops.TIERS.standard.delay_ms and Laptops.TIERS.standard.delay_ms>Laptops.TIERS.premium.delay_ms
	ok=ok and Laptops.TIERS.basic.display_scale<Laptops.TIERS.standard.display_scale and Laptops.TIERS.standard.display_scale<Laptops.TIERS.premium.display_scale
	print("LAPTOP_INVENTORY ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
