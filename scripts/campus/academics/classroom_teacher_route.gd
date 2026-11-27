extends RefCounted
## Short, host-planned floor routes. Every sampled actor position and every
## segment is checked against the classroom collision bodies before use.
const CELL:=0.65
const RADIUS:=0.34
const HEIGHT:=1.65
const MAX_CELLS:=38

static func plan(game: Node,room: String,start: Vector3,goal: Vector3,stand_off: float,allowed: Callable=Callable(),ignored_bodies: Array[RID]=[]) -> Array[Vector3]:
 var result: Array[Vector3]=[]
 if not start.is_finite() or not goal.is_finite() or not game.campus.registry.room_contains(room,start):return result
 var space: PhysicsDirectSpaceState3D=game.get_world_3d().direct_space_state
 var capsule:=CapsuleShape3D.new();capsule.radius=RADIUS;capsule.height=HEIGHT
 var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.collision_mask=3
 query.exclude=ignored_bodies
 var center: Vector3=(start+goal)*.5
 var half:=mini(MAX_CELLS/2,maxi(8,ceili(start.distance_to(goal)/CELL)+5))
 var graph:=AStar3D.new()
 var positions: Dictionary={}
 for x in range(-half,half+1):
  for z in range(-half,half+1):
   var at:=Vector3(center.x+float(x)*CELL,start.y,center.z+float(z)*CELL)
   if not game.campus.registry.room_contains(room,at) or (allowed.is_valid() and not allowed.call(at)) or not _clear(game,space,query,at):continue
   var id:=_id(x,z,half)
   graph.add_point(id,at);positions[Vector2i(x,z)]=id
 for cell in positions:
  for offset in [Vector2i(1,0),Vector2i(0,1),Vector2i(1,1),Vector2i(1,-1)]:
   var neighbor: Vector2i=cell+offset
   if not positions.has(neighbor):continue
   var a: Vector3=graph.get_point_position(positions[cell])
   var b: Vector3=graph.get_point_position(positions[neighbor])
   if _segment_clear(game,space,query,a,b,allowed):graph.connect_points(positions[cell],positions[neighbor])
 if positions.is_empty():return result
 var first: int=-1;var first_distance:=INF;var goals: Array=[]
 for cell in positions:
  var id: int=positions[cell]
  var at: Vector3=graph.get_point_position(id)
  var from_start:=at.distance_squared_to(start)
  if from_start<first_distance and _segment_clear(game,space,query,start,at,allowed):first=id;first_distance=from_start
  if at.distance_to(goal)>=stand_off:goals.append({"id":id,"gap":absf(at.distance_to(goal)-stand_off)})
 if first<0 or goals.is_empty():return result
 goals.sort_custom(func(a,b):return float(a.gap)<float(b.gap))
 var ids:=PackedInt64Array()
 for candidate in goals:
  ids=graph.get_id_path(first,int(candidate.id))
  if not ids.is_empty():break
 if ids.is_empty():return result
 for id in ids:result.append(graph.get_point_position(id))
 return result

static func _id(x: int,z: int,half: int) -> int:
 return (x+half)*(half*2+1)+z+half

static func _clear(game: Node,space: PhysicsDirectSpaceState3D,query: PhysicsShapeQueryParameters3D,at: Vector3) -> bool:
 query.transform=Transform3D(Basis(),at+Vector3.UP*(HEIGHT*.5+.035))
 if not space.intersect_shape(query,1).is_empty():return false
 var local: Vector3=game.player.global_position
 if _actor_near(at,local):return false
 for peer in game.session.roster:
  if int(peer)==game.multiplayer.get_unique_id():continue
  var remote: Vector3=game.session.poses.get(peer,{}).get("position",Vector3.INF)
  if _actor_near(at,remote):return false
 return true

static func _actor_near(at: Vector3,actor: Vector3) -> bool:
 if not actor.is_finite() or absf(at.y-actor.y)>1.5:return false
 var delta:=Vector2(at.x-actor.x,at.z-actor.z)
 return delta.length_squared()<.78*.78

static func _segment_clear(game: Node,space: PhysicsDirectSpaceState3D,query: PhysicsShapeQueryParameters3D,a: Vector3,b: Vector3,allowed: Callable=Callable()) -> bool:
 var steps:=maxi(1,ceili(a.distance_to(b)/.22))
 for i in range(steps+1):
  var at:=a.lerp(b,float(i)/float(steps))
  if (allowed.is_valid() and not allowed.call(at)) or not _clear(game,space,query,at):return false
 return true

static func clear_step(game: Node,a: Vector3,b: Vector3,allowed: Callable=Callable(),ignored_bodies: Array[RID]=[]) -> bool:
 var capsule:=CapsuleShape3D.new();capsule.radius=RADIUS;capsule.height=HEIGHT
 var query:=PhysicsShapeQueryParameters3D.new();query.shape=capsule;query.collision_mask=3
 query.exclude=ignored_bodies
 return _segment_clear(game,game.get_world_3d().direct_space_state,query,a,b,allowed)
