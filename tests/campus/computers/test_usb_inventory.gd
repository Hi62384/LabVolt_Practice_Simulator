extends SceneTree
const Profile=preload("res://scripts/electronics_profile.gd")
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
const Archive=preload("res://scripts/campus/computers/usb_archive.gd")
const StoreUI=preload("res://scripts/ui/store_bundles_equipment/module.gd")
func _initialize() -> void:
	var failures: Array[String]=[]
	var profile=Profile.new();profile.open("usb-inventory-test")
	profile.data.dollars=1000
	for capacity in [8,32,64,150]:profile.buy_usb(capacity)
	var drives: Dictionary=profile.data.dorm.get("usb_drives",{})
	if drives.size()!=4:failures.append("Purchases did not create four distinct drives")
	if not failures.is_empty():
		for failure in failures:push_error(failure)
		print("USB_INVENTORY FAIL")
		quit(1)
		return
	if not Profile.valid(profile.data):failures.append("Purchased profile invalid")
	var capacities:=[]
	for drive_id in drives:
		var capacity: int=drives[drive_id].capacity_mb
		capacities.append(capacity)
		if Archive.load(profile.data.dorm.owner,drive_id,capacity).has("error"):failures.append("Purchased archive missing")
	capacities.sort()
	if capacities!=[8,32,64,150]:failures.append("Incorrect drive capacities")
	var products: Array=StoreUI.equipment_products().filter(func(product):return product.kind=="usb")
	if products.size()!=4:failures.append("USB shop products missing")
	var id: String=drives.keys()[0]
	var owner: String=profile.data.dorm.owner
	var revision: int=profile.data.dorm.revision
	var renamed:=Dorm.apply_intent(profile.data,owner,{"op":"rename_usb","revision":revision,"id":id,"name":"Lecture files"})
	if not renamed.ok or renamed.profile.dorm.usb_drives[id].name!="Lecture files":failures.append("USB rename failed")
	else:
		profile.data=renamed.profile
		var stored:=Dorm.apply_intent(profile.data,owner,{"op":"carry_item","revision":profile.data.dorm.revision,"item":"usb:"+id,"carry":false})
		if not stored.ok or stored.profile.dorm.usb_drives[id].location!="cabinet":failures.append("Storing USB failed")
		else:
			var carried:=Dorm.apply_intent(stored.profile,owner,{"op":"carry_item","revision":stored.profile.dorm.revision,"item":"usb:"+id,"carry":true})
			if not carried.ok or carried.profile.dorm.usb_drives[id].location!="hotbar":failures.append("Retrieving USB failed")
	var before: Dictionary=profile.data.duplicate(true);profile.buy_usb(151)
	if profile.operation_succeeded or profile.data!=before:failures.append("Invalid capacity purchase changed profile")
	for invalid_name in ["", "   ", "bad\nname", "bad\u007fname", "x".repeat(41)]:
		var invalid:=Dorm.apply_intent(profile.data,owner,{"op":"rename_usb","revision":profile.data.dorm.revision,"id":id,"name":invalid_name})
		if invalid.ok:failures.append("Invalid name was accepted")
	var full=Profile.new();full.open("usb-full-inventory-test");full.data.dollars=100000
	var d: Dictionary=full.data.dorm
	if not d.has("usb_drives"):d.usb_drives={}
	if not d.has("carry_items"):d.carry_items=[]
	var counter:=0
	while d.carry_items.size()<6:
		var key: String="%032x"%counter;counter+=1
		d.usb_drives[key]={"name":"Drive","capacity_mb":8,"location":"hotbar"};d.carry_items.append("usb:"+key)
	full.buy_usb(8)
	if not full.operation_succeeded or not full.data.dorm.usb_drives.values().any(func(item):return item.location=="cabinet"):failures.append("Full hotbar did not use cabinet")
	while Dorm.storage_used(d)<Dorm.CAPACITY:
		var key: String="%032x"%counter;counter+=1
		d.usb_drives[key]={"name":"Drive","capacity_mb":8,"location":"cabinet"}
	var full_before: Dictionary=full.data.duplicate(true)
	full.buy_usb(8)
	if full.operation_succeeded or full.data!=full_before:failures.append("Full inventory purchase changed profile")
	for failure in failures:push_error(failure)
	print("USB_INVENTORY ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
