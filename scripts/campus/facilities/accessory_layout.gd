extends RefCounted
## Slot order is presentation metadata; ownership remains with the existing authorities.
const COUNT:=4
const COSMETIC_SLOTS:=["head","eyewear","ears","neck","hands","wrist_left","wrist_right","back"]

static func cosmetic_entries(profile: Dictionary) -> Dictionary:
	var result:={}
	var equipped: Variant=profile.get("avatar_cosmetics",{}).get("equipped",{})
	if not equipped is Dictionary:return result
	for slot in COSMETIC_SLOTS:
		var entry: Variant=equipped.get(slot,{})
		if entry is Dictionary and entry.get("id","") is String and not entry.get("id","").is_empty():
			result["cosmetic/"+slot]=entry.id
	return result

static func persistent_count(profile: Dictionary) -> int:
	var count:=cosmetic_entries(profile).size()
	var dorm: Variant=profile.get("dorm",{})
	if not dorm is Dictionary:return count
	if dorm.get("worn_supplies",{}).get("head","")=="lab_goggles":count+=1
	if not preload("res://scripts/campus/dorms/authority/backpack_inventory.gd").equipped(dorm).is_empty():count+=1
	return count

static func permits_change(before: Dictionary,after: Dictionary,extra:=0) -> bool:
	var old_count:=persistent_count(before)+extra
	var new_count:=persistent_count(after)+extra
	return new_count<=maxi(COUNT,old_count)

static func belt_count(game: Node,peer: int) -> int:
	if not is_instance_valid(game) or not "gym_barbells" in game or not is_instance_valid(game.gym_barbells):return 0
	return int(game.gym_barbells.worn_belt(peer)>=0)

static func resolve(preferred: Dictionary,keys: Array) -> Dictionary:
	var result:={};var used:={}
	for key in keys:
		var slot: Variant=preferred.get(key,-1)
		if slot is int and slot in range(COUNT) and not used.has(slot):result[key]=slot;used[slot]=true
	for key in keys:
		if result.has(key):continue
		for slot in COUNT:
			if not used.has(slot):result[key]=slot;used[slot]=true;break
	return result

static func move(layout: Dictionary,key: String,destination: int) -> Dictionary:
	if not layout.has(key) or destination not in range(COUNT):return layout.duplicate()
	var result:=layout.duplicate();var original:=int(result[key])
	for other in result:
		if other!=key and int(result[other])==destination:result[other]=original;break
	result[key]=destination
	return result
