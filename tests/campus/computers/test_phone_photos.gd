extends SceneTree
const Photos=preload("res://scripts/campus/phones/photo_library.gd")
const Tiers=preload("res://scripts/campus/phones/phone_tiers.gd")
const Profile=preload("res://scripts/electronics_profile.gd")
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const PhoneInventory=preload("res://scripts/campus/phones/phone_inventory.gd")
func _initialize() -> void:
	var owner: String="a".repeat(48);var phone: String="b".repeat(32)
	var other: String="c".repeat(32)
	var image:=Image.create(24,24,false,Image.FORMAT_RGB8);image.fill(Color("b2d8d0"))
	var first: Dictionary=Photos.capture(owner,phone,image,Tiers.TIERS.basic.storage_bytes)
	var ok: bool=first.has("id")
	if ok:
		var state: Dictionary=Photos.list(owner,phone)
		ok=state.photos.size()==1 and int(state.bytes)==int(first.bytes)
		var loaded: Dictionary=Photos.load_photo(owner,phone,first.id)
		ok=ok and not loaded.has("error") and loaded.image.get_width()==24 and loaded.image.get_height()==24
		ok=ok and Photos.list(owner,other).photos.is_empty()
		ok=ok and Photos.capture(owner,phone,image,int(first.bytes)).get("error","")=="Phone storage is full"
		ok=ok and not Photos.delete_photo(owner,phone,"../invalid")
		ok=ok and Photos.delete_photo(owner,phone,first.id) and not Photos.delete_photo(owner,phone,first.id)
		ok=ok and Photos.list(owner,phone).photos.is_empty() and Photos.load_photo(owner,phone,first.id).has("error")
	ok=ok and Tiers.TIERS.basic.storage_bytes<Tiers.TIERS.standard.storage_bytes and Tiers.TIERS.standard.storage_bytes<Tiers.TIERS.premium.storage_bytes
	ok=ok and Tiers.TIERS.basic.delay_ms>Tiers.TIERS.standard.delay_ms and Tiers.TIERS.standard.delay_ms>Tiers.TIERS.premium.delay_ms
	var profile=Profile.new();profile.open("phone-inventory-test");profile.data.dollars=10000
	profile.buy_smartphone("basic")
	ok=ok and profile.operation_succeeded and Profile.valid(profile.data)
	if ok:
		var phone_id: String=profile.data.dorm.smartphones.keys()[0]
		var stored: Dictionary=Dorm.apply_intent(profile.data,profile.data.dorm.owner,{"op":"carry_item","item":"phone:"+phone_id,"carry":false,"revision":profile.data.dorm.revision})
		ok=stored.get("ok",false) and stored.profile.dorm.smartphones[phone_id].location=="cabinet"
		if stored.get("ok",false):
			var retrieved: Dictionary=Dorm.apply_intent(stored.profile,stored.profile.dorm.owner,{"op":"carry_item","item":"phone:"+phone_id,"carry":true,"revision":stored.profile.dorm.revision})
			ok=ok and retrieved.get("ok",false) and retrieved.profile.dorm.smartphones[phone_id].location=="hotbar"
			if retrieved.get("ok",false):profile.data=retrieved.profile
		var before: Dictionary=profile.data.duplicate(true);profile.buy_smartphone("invalid")
		ok=ok and not profile.operation_succeeded and profile.data==before
		var bag: String="d".repeat(24)
		profile.data.dorm.backpacks={bag:{"size":"backpack_small","location":"back","items":[]}}
		var packed: Dictionary=Dorm.apply_intent(profile.data,profile.data.dorm.owner,{"op":"bag_pack","bag":bag,"item":{"kind":"phone","id":phone_id},"revision":profile.data.dorm.revision})
		ok=ok and packed.get("ok",false) and packed.profile.dorm.smartphones[phone_id].location=="packed" and PhoneInventory.carried(packed.profile.dorm)
		if packed.get("ok",false):
			var direct_take: Dictionary=Dorm.apply_intent(packed.profile,packed.profile.dorm.owner,{"op":"carry_item","item":"phone:"+phone_id,"carry":true,"revision":packed.profile.dorm.revision})
			ok=ok and not direct_take.get("ok",false)
			var duplicate: Dictionary=packed.profile.dorm.duplicate(true)
			duplicate.backpacks[bag].items.append({"kind":"phone","id":phone_id})
			ok=ok and not PhoneInventory.valid(duplicate)
			duplicate.backpacks=[]
			ok=ok and not PhoneInventory.valid(duplicate)
			packed.profile.dorm.backpacks[bag].location="cabinet"
			ok=ok and not PhoneInventory.carried(packed.profile.dorm)
	print("PHONE_PHOTOS ","PASS" if ok else "FAIL")
	quit(0 if ok else 1)
