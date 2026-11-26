extends RefCounted

const Equipment = preload("res://scripts/campus/items/equipment_configuration.gd")
const PREFIX := "power_bank:"
const LIMIT := 12
const PRICE := 37

static func valid_key(key: String) -> bool:
	if not key.begins_with(PREFIX):return false
	var uid:=key.trim_prefix(PREFIX)
	return uid.length()==32 and uid==uid.to_lower() and not uid.begins_with("-") and uid.is_valid_hex_number(false)

static func capacity(options: Dictionary) -> float:
	return Equipment.value(Equipment.POWER_BANK,options,"hardware","capacity",10.0)

static func valid(bank: Variant) -> bool:
	if not bank is Dictionary or bank.size()!=2 or Equipment.quote(Equipment.POWER_BANK,0,bank.get("configuration")).is_empty():return false
	var charge: Variant=bank.get("charge_wh")
	return (charge is float or charge is int) and is_finite(charge) and charge>=0 and charge<=capacity(bank.configuration)
