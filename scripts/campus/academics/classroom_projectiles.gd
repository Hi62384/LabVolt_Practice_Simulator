extends Node3D
## Small host-simulated paper balls. Clients send only an intent; the host supplies pose,
## trajectory and collision evidence. Visuals never decide attribution or damage.
const ROOMS=["ac_lab","dc_lab","elm253_lecture","ety155_lecture"]
const SPEED:=10.0
const GRAVITY:=Vector3(0,-9.8,0)
const STEP:=1.0/30.0
const MAX_ACTIVE:=24
var game: Node
var active: Dictionary={}
var visuals: Dictionary={}
var marks: Array=[]
var last_throw: Dictionary={}
var serial:=0
var clock:=0.0
var step_count:=0
var impacts: Dictionary={}
var property_damage: Dictionary={}
var ball_mesh: SphereMesh
var ball_material: StandardMaterial3D

func build(owner: Node) -> void:
	game=owner
	ball_mesh=SphereMesh.new();ball_mesh.radius=.065;ball_mesh.height=.13
	ball_material=StandardMaterial3D.new();ball_material.albedo_color=Color(.9,.88,.78)
	game.session.leaving.connect(clear_session)
	game.session.restarted.connect(clear_session)

func clear_session() -> void:
	active.clear();impacts.clear();last_throw.clear();property_damage.clear()
	for node in visuals.values():if is_instance_valid(node):node.queue_free()
	visuals.clear()
	for mark in marks:if is_instance_valid(mark.node):mark.node.queue_free()
	marks.clear();clock=0.0;step_count=0

func request_throw() -> void:
	if multiplayer.is_server():_accept(multiplayer.get_unique_id())
	elif game.session.online:_throw.rpc_id(1)

@rpc("any_peer","call_remote","reliable",7)
func _throw() -> void:
	if multiplayer.is_server():_accept(multiplayer.get_remote_sender_id())

func _accept(peer: int) -> void:
	if not multiplayer.is_server() or not game.session.roster.has(peer) or active.size()>=MAX_ACTIVE:return
	var now:=Time.get_ticks_msec()
	if now-int(last_throw.get(peer,-5000))<1800:return
	var pose: Dictionary=game.session.poses.get(peer,{})
	var base: Vector3=pose.get("position",Vector3.INF)
	if not base.is_finite() or bool(pose.get("seated",false)) or game.health.locked(peer):return
	var room:=str(game.campus.registry.locate(base))
	if room not in ROOMS:return
	var yaw:=float(pose.get("yaw",0.0));var pitch:=float(pose.get("pitch",0.0))
	if not is_finite(yaw) or not is_finite(pitch):return
	var direction:=Basis(Vector3.UP,yaw)*Vector3(0,-sin(pitch),-cos(pitch))
	if direction.length_squared()<.9:return
	var origin:=base+Vector3.UP*1.5+direction.normalized()*.45
	last_throw[peer]=now;serial+=1
	var id:=serial
	active[id]={"peer":peer,"room":room,"position":origin,"velocity":direction.normalized()*SPEED+Vector3.UP*1.0,"age":0.0}
	_spawn_visual(id,origin)
	if game.session.online:_spawn.rpc(id,origin)

func _physics_process(delta: float) -> void:
	if not multiplayer.is_server():return
	clock+=minf(delta,.2)
	while clock>=STEP:
		clock-=STEP
		_step(STEP)
	var now:=Time.get_ticks_msec()
	for i in range(marks.size()-1,-1,-1):
		if now-int(marks[i].until)>0:
			if is_instance_valid(marks[i].node):marks[i].node.queue_free()
			marks.remove_at(i)

func _step(dt: float) -> void:
	step_count+=1
	for id in active.keys():
		var item: Dictionary=active[id]
		var start: Vector3=item.position
		var velocity: Vector3=item.velocity+GRAVITY*dt
		var finish:=start+velocity*dt
		var hit:=_impact_target(item,start,finish)
		if not hit.is_empty():
			_impact(id,item,hit)
			continue
		item.position=finish;item.velocity=velocity;item.age=float(item.age)+dt
		if item.age>2.2 or str(game.campus.registry.locate(finish))!=str(item.room):_remove(id);continue
		if is_instance_valid(visuals.get(id)):visuals[id].global_position=finish
		if game.session.online and step_count%3==0:_move.rpc(id,finish)

func _impact_target(item: Dictionary,start: Vector3,finish: Vector3) -> Dictionary:
	var peer:=int(item.peer)
	for other in game.session.roster:
		if int(other)==peer:continue
		var pose: Dictionary=game.session.poses.get(other,{})
		var position: Vector3=pose.get("position",Vector3.INF)
		if position.is_finite() and str(game.campus.registry.locate(position))==str(item.room) and finish.distance_to(position+Vector3.UP*1.1)<.42:return {"kind":"student","position":finish,"target":int(other)}
	var teacher: Vector3=game.faculty._teacher_position(str(item.room))
	if teacher.is_finite() and finish.distance_to(teacher+Vector3.UP*1.3)<.42:return {"kind":"teacher","position":finish}
	var query:=PhysicsRayQueryParameters3D.create(start,finish,1)
	var result:=get_world_3d().direct_space_state.intersect_ray(query)
	if not result.is_empty():return {"kind":"property","position":result.position}
	return {}

func _impact(id: int,item: Dictionary,hit: Dictionary) -> void:
	var room:=str(item.room);var kind:=str(hit.kind);var point: Vector3=hit.position
	impacts[id]={"peer":int(item.peer),"room":room,"kind":kind,"position":point,"time":Time.get_ticks_msec()}
	if impacts.size()>64:impacts.erase(impacts.keys()[0])
	if kind=="property":
		property_damage[room]=mini(10000,int(property_damage.get(room,0))+1)
		_mark(point)
	if is_instance_valid(game.faculty):game.faculty.report_projectile_impact(id)
	_remove(id)
	if game.session.online:_hit.rpc(id,point,kind)

func _remove(id: int) -> void:
	active.erase(id)
	if is_instance_valid(visuals.get(id)):visuals[id].queue_free()
	visuals.erase(id)

func _spawn_visual(id: int,point: Vector3) -> void:
	var node:=MeshInstance3D.new();node.mesh=ball_mesh;node.material_override=ball_material;node.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;add_child(node);node.global_position=point;visuals[id]=node

func _mark(point: Vector3) -> void:
	if marks.size()>=96:
		if is_instance_valid(marks[0].node):marks[0].node.queue_free()
		marks.pop_front()
	var node:=MeshInstance3D.new();node.mesh=ball_mesh;node.material_override=ball_material;node.scale=Vector3(.6,.2,.6);add_child(node);node.global_position=point;marks.append({"node":node,"until":Time.get_ticks_msec()+30000})

@rpc("authority","call_remote","reliable",7)
func _spawn(id: int,point: Vector3) -> void:if multiplayer.get_remote_sender_id()==1:_spawn_visual(id,point)
@rpc("authority","call_remote","unreliable",7)
func _move(id: int,point: Vector3) -> void:if multiplayer.get_remote_sender_id()==1 and is_instance_valid(visuals.get(id)):visuals[id].global_position=point
@rpc("authority","call_remote","reliable",7)
func _hit(id: int,point: Vector3,kind: String) -> void:
	if multiplayer.get_remote_sender_id()!=1:return
	_remove(id)
	if kind=="property":_mark(point)
