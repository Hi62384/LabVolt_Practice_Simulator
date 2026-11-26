extends RefCounted

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")

static func slot(profile: Dictionary, kind: String, key: String) -> Dictionary:
	var dorm: Dictionary=profile.get("dorm",{})
	var record: Dictionary={}
	match kind:
		Config.PHONE:record=dorm.get("smartphones",{}).get(key,{})
		Config.USB:record=dorm.get("usb_drives",{}).get(key,{})
		Config.LAPTOP:record=dorm.get("portable_laptops",{}).get(key,{})
		Config.BACKPACK:record=dorm.get("backpacks",{}).get(key,{})
		Config.POWER_BANK:record=dorm.get("power_banks",{}).get(key,{})
		Config.KIT:record=profile.get("kits",{}).get(key,{})
		Config.NOTEBOOK:return _entry(dorm.get("notebook_options",{}),key)
		Config.CALCULATOR:return _entry(dorm.get("calculator_options",{}),key)
	if record.get("location","") in ["lost","placed","ground","mounted"]:return {}
	return _entry(record,"configuration")

static func _entry(record: Dictionary, property: String) -> Dictionary:
	if not record.has(property):return {}
	return {"record":record,"property":property,"configuration":record[property]}

static func key(item: Dictionary) -> String:
	if item.get("kind") in [Config.NOTEBOOK,Config.CALCULATOR,Config.POWER_BANK]:
		return str(item.get("dorm_item",""))
	return str(item.get("id",""))
