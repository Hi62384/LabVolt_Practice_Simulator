extends SceneTree
const Dorm=preload("res://scripts/campus/dorms/authority/persistent_dorm.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:
	var identity:="a".repeat(48)
	var base: Dictionary=Dorm.migrate({"inventory":{},"component_instances":{},"kits":{}},identity).profile
	base.dorm.supply_counts.lab_goggles=1;base.dorm.carry_items=["lab_goggles"]
	base.avatar_cosmetics={"equipped":{"eyewear":{"id":"eyewear.test"}}}
	var result:=Dorm.apply_intent(base,identity,{"op":"wear_goggles","wear":true,"revision":0})
	check(not result.ok,"goggles overlapped cosmetic eyewear")
	base.avatar_cosmetics.equipped.clear()
	result=Dorm.apply_intent(base,identity,{"op":"wear_goggles","wear":true,"revision":0})
	check(result.ok,"goggles were rejected after eyewear removal")
	var bag:="b".repeat(24)
	base.dorm.carry_items=["bag:"+bag];base.dorm.backpacks={bag:{"location":"hotbar","size":"backpack_small","items":[]}}
	base.avatar_cosmetics.equipped={"back":{"id":"back.test"}}
	result=Dorm.apply_intent(base,identity,{"op":"bag_move","bag":bag,"destination":"back","revision":0})
	check(not result.ok,"backpack overlapped cosmetic back accessory")
	base.avatar_cosmetics.equipped.clear()
	result=Dorm.apply_intent(base,identity,{"op":"bag_move","bag":bag,"destination":"back","revision":0})
	check(result.ok,"backpack was rejected after back accessory removal")
	base.dorm.carry_items=["lab_goggles"]
	base.dorm.backpacks={}
	base.avatar_cosmetics.equipped={"head":{"id":"hat"},"neck":{"id":"necklace"},"ears":{"id":"earrings"},"back":{"id":"pack"}}
	result=Dorm.apply_intent(base,identity,{"op":"wear_goggles","wear":true,"revision":0})
	check(not result.ok and str(result.error).contains("free a slot"),"fifth persistent accessory was accepted")
	var layout=preload("res://scripts/campus/facilities/accessory_layout.gd")
	var with_three: Dictionary=base.duplicate(true);with_three.avatar_cosmetics.equipped.erase("back")
	check(layout.persistent_count(with_three)==3 and not layout.permits_change(with_three,base,1),"worn belt did not count toward the limit")
	check(layout.permits_change(base,with_three,1),"legacy overflow could not be reduced")
	for failure in failures:push_error(failure)
	print("ACCESSORY_CONFLICTS ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
