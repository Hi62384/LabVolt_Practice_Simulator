extends SceneTree
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:
	var identity:="a".repeat(48)
	var base: Dictionary=Dorm.migrate({"inventory":{},"component_instances":{},"kits":{}},identity).profile
	base.dorm.supply_counts["lab_goggles"]=1;base.dorm.carry_items=["lab_goggles"]
	base.avatar_cosmetics={"equipped":{"eyewear":{"id":"eyewear.test"}}}
	var result:=Dorm.apply_intent(base,identity,{"op":"wear_goggles","wear":true,"revision":0})
	check(result.ok and result.profile.avatar_cosmetics==base.avatar_cosmetics,"goggles preserve eyewear")
	var bag:="b".repeat(24)
	base.dorm.carry_items=["bag:"+bag];base.dorm.backpacks={}
	base.dorm.backpacks[bag]={"location":"hotbar","size":"backpack_small","items":[]}
	base.avatar_cosmetics.equipped={"back":{"id":"back.test"}}
	result=Dorm.apply_intent(base,identity,{"op":"bag_move","bag":bag,"destination":"back","revision":0})
	check(result.ok and result.profile.avatar_cosmetics==base.avatar_cosmetics,"backpack preserves decorative back item")
	if not result.ok:
		push_error(str(result.error));quit(1);return
	var equipped_profile: Dictionary=result.profile
	for cycle in 4:
		var removed := Dorm.apply_intent(equipped_profile,identity,{"op":"bag_move","bag":bag,"destination":"hotbar","revision":equipped_profile.dorm.revision})
		check(removed.ok and removed.profile.dorm.carry_items.count("bag:"+bag)==1 and Dorm.Backpacks.equipped(removed.profile.dorm).is_empty(),"unequip left a stale Back slot or duplicated the bag")
		if not removed.ok:break
		var equipped := Dorm.apply_intent(removed.profile,identity,{"op":"bag_move","bag":bag,"destination":"back","revision":removed.profile.dorm.revision})
		check(equipped.ok and "bag:"+bag not in equipped.profile.dorm.carry_items and Dorm.Backpacks.equipped(equipped.profile.dorm)==bag,"rewear failed to move the same bag from hotbar")
		if not equipped.ok:break
		equipped_profile=equipped.profile
	base.dorm.carry_items=["lab_goggles"]
	base.dorm.backpacks={}
	base.avatar_cosmetics.equipped={"head":{"id":"hat"},"neck":{"id":"necklace"},"ears":{"id":"earrings"},"back":{"id":"pack"}}
	result=Dorm.apply_intent(base,identity,{"op":"wear_goggles","wear":true,"revision":0})
	check(result.ok and result.profile.avatar_cosmetics==base.avatar_cosmetics,"cosmetics do not block functional goggles")
	var layout=preload("res://scripts/campus/facilities/accessory_layout.gd")
	check(result.ok and layout.persistent_count(base)==0 and layout.persistent_count(result.profile)==1,"only functional gear counts toward slots")
	for failure in failures:push_error(failure)
	print("ACCESSORY_CONFLICTS ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
