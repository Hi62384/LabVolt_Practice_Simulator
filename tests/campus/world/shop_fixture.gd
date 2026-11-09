extends Node3D
var opened: Array=[]
var captures := 0
var electronics: Node
var player: CharacterBody3D
class Electronics extends Node:
 var opened: Array=[]
 func open(page: String) -> void: opened.append(page)
func _ready() -> void:
 electronics=Electronics.new();add_child(electronics)
 player=CharacterBody3D.new();add_child(player)
func capture() -> void: captures+=1
func _box(parent: Node3D,pos: Vector3,size: Vector3,_color: Color) -> MeshInstance3D:
 var node:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;node.mesh=mesh;node.position=pos;parent.add_child(node);return node
func _text3(parent: Node3D,text: String,pos: Vector3,_size: float,_color: Color) -> Label3D:
 var node:=Label3D.new();node.text=text;node.position=pos;parent.add_child(node);return node
