extends RefCounted
const Config=preload("res://scripts/campus/items/equipment_configuration.gd")
## Portable computer ownership metadata. File bytes are held on separate USBs.
const TIERS:={
	"basic":{"name":"Basic laptop","price":600,"delay_ms":900,"display_scale":0.55},
	"standard":{"name":"Standard laptop","price":1500,"delay_ms":350,"display_scale":0.75},
	"premium":{"name":"Premium laptop","price":3500,"delay_ms":0,"display_scale":1.0},
}
const MAX_LAPTOPS:=64
const LOCATIONS:=["hotbar","cabinet","placed","lost"]
static func valid(dorm: Dictionary) -> bool:
	var laptops: Variant=dorm.get("portable_laptops",{})
	var carried: Variant=dorm.get("carry_items",[])
	if not laptops is Dictionary or laptops.size()>MAX_LAPTOPS or not carried is Array:return false
	for id in laptops:
		if not id is String or id.length()!=32 or not id.is_valid_hex_number() or id!=id.to_lower():return false
		var item: Variant=laptops[id]
		if not item is Dictionary or not TIERS.has(item.get("tier","")) or item.get("location","") not in LOCATIONS:return false
		if item.size()!=2+int(item.has("configuration")):return false
		if item.has("configuration") and (item.tier!="basic" or Config.quote(Config.LAPTOP,0,item.configuration).is_empty()):return false
		if (item.location=="hotbar") != ("laptop:"+id in carried):return false
	for key in carried:
		if key is String and key.begins_with("laptop:") and not laptops.has(key.trim_prefix("laptop:")):return false
	return true
