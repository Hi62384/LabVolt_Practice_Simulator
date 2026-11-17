extends SceneTree

const Target = preload("res://scripts/campus/items/placement_target.gd")

class Ground:
	extends RefCounted
	var feet := Vector3(2,0,3)
	var clear := true
	func _table_position(point: Vector3,_peer: int) -> bool:
		return absf(point.y-.8)<.01 and point.distance_to(feet)<3.0
	func resolve(point: Vector3) -> Variant:
		if not clear or not point.is_finite() or point.distance_to(feet)>1.8:return null
		return Vector3(point.x,0,point.z)
	func ground_drop_position(point: Variant,_peer: int) -> Variant:
		if not point is Vector3:return null
		return resolve(point)

func _initialize() -> void:
	var ground:=Ground.new()
	var floor:=Callable(ground,"resolve")
	var table:=StaticBody3D.new();table.set_meta("role","table")
	var table_hit:={"position":Vector3(2.5,.8,3),"normal":Vector3.UP,"collider":table}
	assert(Target.choose(table_hit,ground.feet,floor)=={"position":table_hit.position,"table":true})
	assert(Target.host_position(ground,table_hit.position,ground.feet,1)==table_hit.position+Vector3.UP*.01)
	assert(Target.host_position(ground,Vector3.INF,ground.feet,1)==null)
	var floor_hit:={"position":Vector3(2.5,0,3),"normal":Vector3.UP}
	assert(Target.choose(floor_hit,ground.feet,floor)=={"position":floor_hit.position,"table":false})
	var far_hit:={"position":Vector3(5,0,3),"normal":Vector3.UP}
	assert(Target.choose(far_hit,ground.feet,floor)=={"position":ground.feet,"table":false})
	assert(Target.host_position(ground,far_hit.position,ground.feet,1)==null)
	var wall_hit:={"position":Vector3(2.5,.8,3),"normal":Vector3.RIGHT,"collider":table}
	assert(Target.choose(wall_hit,ground.feet,floor)=={"position":ground.feet,"table":false})
	assert(Target.choose({"position":Vector3.INF,"normal":Vector3.UP,"collider":table},ground.feet,floor)=={"position":ground.feet,"table":false})
	ground.clear=false
	assert(Target.choose({},ground.feet,floor).is_empty())
	table.free()
	print("PLACEMENT_TARGET PASS")
	quit(0)
