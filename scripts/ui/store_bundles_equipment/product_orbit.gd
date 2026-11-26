extends RefCounted

const LIMIT:=PI*.494
var initial:=Vector3.ZERO
var angles:=Vector2.ZERO
var target:=Vector3.ZERO
var distance:=1.
var initial_distance:=1.
var camera: Camera3D

func setup(subject: Camera3D, orientation: Vector3, view_distance: float) -> void:
	camera=subject
	initial=orientation
	initial_distance=view_distance
	reset()

func reset() -> void:
	target=Vector3.ZERO
	distance=initial_distance
	angles=Vector2(initial.y,initial.x)
	_apply()

func preset(index: int) -> void:
	if index==0:reset();return
	var views: Array[Vector2]=[Vector2.ZERO,Vector2.ZERO,Vector2(PI,0),Vector2(-PI*.5,0),Vector2(PI*.5,0),Vector2(0,LIMIT),Vector2(0,-LIMIT)]
	angles=views[index]
	_apply()

func orbit(delta: Vector2) -> void:
	angles.x=wrapf(angles.x-delta.x*.012,-PI,PI)
	angles.y=clampf(angles.y+delta.y*.012,-LIMIT,LIMIT)
	_apply()

func pan(delta: Vector2) -> void:
	target+=(-camera.basis.x*delta.x+camera.basis.y*delta.y)*distance*.002
	_apply()

func zoom(direction: float) -> void:
	distance=clampf(distance*direction,initial_distance*.34,initial_distance*3.)
	_apply()

func _apply() -> void:
	var point:=Vector3(sin(angles.x)*cos(angles.y),sin(angles.y),cos(angles.x)*cos(angles.y))
	camera.look_at_from_position(target+point*distance,target,Vector3.UP)
