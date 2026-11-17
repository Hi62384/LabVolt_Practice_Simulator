extends SceneTree
const Layout=preload("res://scripts/campus/facilities/accessory_layout.gd")
const Hotbar=preload("res://scripts/carry_hotbar.gd")
var failures: Array[String]=[]
func check(value: bool,message: String) -> void:
	if not value:failures.append(message)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var initial: Dictionary=Layout.resolve({},["goggles","backpack","belt"])
	check(initial=={"goggles":0,"backpack":1,"belt":2},"legacy gear did not migrate to free slots")
	var moved: Dictionary=Layout.move(initial,"belt",0)
	check(moved=={"goggles":2,"backpack":1,"belt":0},"occupied destination did not swap")
	var restored: Dictionary=Layout.resolve(moved,["goggles","backpack","belt"])
	check(restored==moved,"saved order did not restore")
	var malformed: Dictionary=Layout.resolve({"goggles":99,"backpack":1,"belt":1},["goggles","backpack","belt"])
	check(malformed.size()==3 and malformed.values().duplicate().all(func(v):return v in range(4)) and malformed.values().count(1)==1,"invalid positions caused duplicate slots")
	var hotbar=Hotbar.new();root.add_child(hotbar)
	hotbar.slots=[{"kind":"lab_goggles"},{"kind":"backpack","id":"bag"},{"kind":"gym_belt","id":0},{},{},{}]
	hotbar.accessory_positions={"backpack":2}
	check(hotbar._can_drop_accessory(Vector2.ZERO,{"hotbar_slot":0,"item":hotbar.slots[0]},3),"goggles rejected from free slot")
	check(not hotbar._can_drop_accessory(Vector2.ZERO,{"hotbar_slot":1,"item":hotbar.slots[1]},0),"duplicate backpack category accepted")
	check(not hotbar._can_drop_accessory(Vector2.ZERO,{"hotbar_slot":2,"item":hotbar.slots[2]},2),"occupied destination accepted")
	check(hotbar._can_drop_accessory(Vector2.ZERO,{"accessory_key":"backpack","slot":2},0),"equipped accessory could not be rearranged")
	check(not hotbar._can_drop_accessory(Vector2.ZERO,{"accessory_key":"backpack","slot":1},0),"stale drag accepted")
	hotbar.free()
	for failure in failures:push_error(failure)
	print("ACCESSORY_LAYOUT ","PASS" if failures.is_empty() else "FAIL")
	quit(0 if failures.is_empty() else 1)
