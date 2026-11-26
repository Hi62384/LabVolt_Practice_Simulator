extends RefCounted

const Config = preload("res://scripts/campus/items/equipment_configuration.gd")
const Finish = preload("res://scripts/campus/items/equipment_finish.gd")

static func build(parent: Node3D, configuration: Dictionary = {}) -> Node3D:
	var book := Node3D.new()
	parent.add_child(book)
	update(book,configuration)
	return book

static func dimensions(configuration: Dictionary) -> Vector3:
	var sheet: Vector2=Config.value(Config.NOTEBOOK,configuration,"hardware","size",Vector2(780,1100))
	var width := sheet.x*.00029
	var length := sheet.y*.00028
	var landscape: bool=Config.value(Config.NOTEBOOK,configuration,"hardware","orientation",false)
	var pages: int=Config.value(Config.NOTEBOOK,configuration,"hardware","pages",32)
	var cover: float=Config.value(Config.NOTEBOOK,configuration,"appearance","cover",.006)
	var height := 2*cover+.005+pages*.00025
	return Vector3(length,height,width) if landscape else Vector3(width,height,length)

static func update(book: Node3D, configuration: Dictionary) -> void:
	for child in book.get_children():
		book.remove_child(child)
		child.queue_free()
	book.set_meta("equipment_shell",[])
	book.set_meta("equipment_trim",[])
	var size := dimensions(configuration)
	var width := size.x
	var length := size.z
	var cover: float=Config.value(Config.NOTEBOOK,configuration,"appearance","cover",.006)
	var block_height := size.y-2*cover
	var shade := Color(Config.value(Config.NOTEBOOK,configuration,"hardware","paper","fcfaf2"))
	_box(book,Vector3(0,cover*.5,0),Vector3(width,cover,length),Color("416b78"),"shell")
	_box(book,Vector3(0,cover+block_height*.5,0),Vector3(width-.008,block_height,length-.008),shade,"")
	_box(book,Vector3(0,cover*1.5+block_height,0),Vector3(width,cover,length),Color("416b78"),"shell")
	_box(book,Vector3(-width*.5+.008,cover+block_height*.5,0),Vector3(.02,2*cover+block_height,length+.001),Color("254854"),"trim")
	book.set_meta("decoration_anchor",{"part":book,"position":Vector3(.008,size.y+.0006,0),"rotation":Vector3(-PI/2,0,0),"area":Vector2(width-.044,length-.025)})
	Finish.apply_finish(book,Config.NOTEBOOK,configuration)

static func _box(parent: Node3D, center: Vector3, dimensions: Vector3, tint: Color, part: String) -> void:
	var mesh := BoxMesh.new()
	mesh.size=dimensions
	var material := StandardMaterial3D.new()
	material.albedo_color=tint
	material.roughness=.78
	var node := MeshInstance3D.new()
	node.mesh=mesh
	node.material_override=material
	node.position=center
	if not part.is_empty():
		var group: Array=parent.get_meta("equipment_"+part)
		group.append(node)
	parent.add_child(node)
