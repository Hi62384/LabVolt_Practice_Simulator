extends SceneTree
const Projectiles=preload("res://scripts/campus/academics/classroom_projectiles.gd")
class Session extends Node:
	signal leaving
	signal restarted
	var roster: Dictionary={1:true}
	var online:=false
	var poses: Dictionary={1:{"position":Vector3.ZERO,"yaw":0.0,"pitch":0.0,"seated":false}}
class Registry extends RefCounted:
	func locate(point: Vector3) -> String:return "dc_lab" if point.z>-10.0 else "hall"
class Campus extends Node:
	var registry:=Registry.new()
class Health extends Node:
	func locked(_peer: int) -> bool:return false
class Faculty extends Node:
	var game: Node
	var observed: Array=[]
	func _teacher_position(_room: String) -> Vector3:return Vector3(50,0,50)
	func report_projectile_impact(id: int) -> void:observed.append(game.classroom_projectiles.impacts.get(id,{}).duplicate())
class Game extends Node3D:
	var session: Session
	var campus: Campus
	var health: Health
	var faculty: Faculty
	var classroom_projectiles: Node3D

func _initialize() -> void:call_deferred("_run")
func _run() -> void:
	var game:=Game.new();root.add_child(game)
	game.session=Session.new();game.add_child(game.session)
	game.campus=Campus.new();game.add_child(game.campus)
	game.health=Health.new();game.add_child(game.health)
	game.faculty=Faculty.new();game.faculty.game=game;game.add_child(game.faculty)
	var wall:=StaticBody3D.new();wall.position=Vector3(0,1.5,-3);game.add_child(wall)
	var shape:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(2,3,.1);shape.shape=box;wall.add_child(shape)
	game.classroom_projectiles=Projectiles.new();game.add_child(game.classroom_projectiles);game.classroom_projectiles.build(game)
	await physics_frame
	game.classroom_projectiles._accept(1)
	assert(game.classroom_projectiles.active.size()==1)
	game.classroom_projectiles._accept(1)
	assert(game.classroom_projectiles.active.size()==1)
	for i in 30:
		game.classroom_projectiles._step(1.0/30.0)
		if game.classroom_projectiles.active.is_empty():break
	assert(game.classroom_projectiles.active.is_empty())
	assert(game.classroom_projectiles.property_damage.get("dc_lab",0)==1)
	assert(game.faculty.observed.size()==1 and game.faculty.observed[0].peer==1 and game.faculty.observed[0].kind=="property")
	game.classroom_projectiles.last_throw.clear()
	game.session.poses[1].position=Vector3(0,0,-20)
	game.classroom_projectiles._accept(1)
	assert(game.classroom_projectiles.active.is_empty())
	game.session.poses[1].position=Vector3.ZERO
	game.session.poses[1].seated=true
	game.classroom_projectiles._accept(1)
	assert(game.classroom_projectiles.active.is_empty())
	game.session.poses[1].seated=false
	game.classroom_projectiles._accept(2)
	assert(game.classroom_projectiles.active.is_empty())
	print("CLASSROOM_PROJECTILES PASS")
	quit()
