extends RefCounted

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const Bags = preload("res://scripts/campus/dorms/authority/backpack_inventory.gd")
const Toon = preload("res://scripts/toon_character.gd")

static func build(parent: Node3D, model: String, options: Dictionary = {}) -> Node3D:
	var bag := Node3D.new()
	parent.add_child(bag)
	update(bag,model,options)
	return bag

static func update(bag: Node3D, model: String, options: Dictionary) -> void:
	for child in bag.get_children():
		bag.remove_child(child)
		child.queue_free()
	bag.scale=Bags.dimensions(model)/Vector3(.29,.38,.22)
	var base_color: String={"backpack_small":"607b58","backpack_medium":"3b7283","backpack_large":"8e5544","backpack_giant":"645780"}.get(model,"607b58")
	var shell: String=Config.value(Config.BACKPACK,options,"appearance","shell",base_color)
	var trim: String=Config.value(Config.BACKPACK,options,"appearance","trim","283e4b")
	var material: Vector2=Config.value(Config.BACKPACK,options,"appearance","finish",Vector2(.90,0))
	var fabric := Toon.material(shell,material.x)
	var edging := Toon.material(trim,.68)
	var zipper := Toon.material("c3ab82")
	Toon.ellipsoid(bag,Vector3(0,-.01,0),Vector3(.141,.174,.087),fabric,"Fabric shell")
	Toon.ellipsoid(bag,Vector3(0,-.071,.073),Vector3(.109,.080,.039),edging,"Front pocket")
	Toon.link(bag,Vector3(-.082,-.044,.106),Vector3(.082,-.044,.106),.004,zipper)
	if Config.value(Config.BACKPACK,options,"appearance","handle",true):
		Toon.line(bag,[Vector3(-.045,.145,0),Vector3(-.036,.179,0),Vector3(.036,.179,0),Vector3(.045,.145,0)],.009,edging)
	var strap_factor: float=Config.value(Config.BACKPACK,options,"hardware","straps",1.0)
	var pocket_slots := int(Config.value(Config.BACKPACK,options,"hardware","pockets",0))
	for side in [-1.0,1.0]:
		var x: float=side*.079
		Toon.line(bag,[Vector3(x,.118,-.059),Vector3(x,.063,-.112),Vector3(x,-.074,-.113),Vector3(x,-.141,-.057)],.014 if strap_factor==1.0 else .022,edging)
		if pocket_slots==4 or (pocket_slots==2 and side<0):
			Toon.ellipsoid(bag,Vector3(side*.124,-.091,.012),Vector3(.029,.061,.059),edging,"Component pocket")
