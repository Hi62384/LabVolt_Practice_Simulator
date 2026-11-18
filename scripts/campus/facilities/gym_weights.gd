extends Node3D
const GymLayout = preload("res://scripts/campus/facilities/gym_layout.gd")
## Host-owned session equipment: rack, hand, hotbar and floor are exclusive states.
# Keep existing inventory IDs stable; the new pairs occupy the last twelve slots.
const SIZES := [2.5,5.0,7.5,10.0,12.5,15.0,17.5,20.0,25.0,30.0,35.0,40.0,45.0,50.0,60.0,70.0,80.0,90.0,100.0,120.0,140.0,160.0,180.0,200.0,22.5,27.5,55.0,65.0,75.0,85.0,95.0,110.0,130.0,150.0,170.0,190.0]
const RACK := GymLayout.ORIGIN + GymLayout.DUMBBELLS
const RACK_SLOTS := 36
const RACK_COLUMNS := 9
const RACK_SPACING := .62
const RACK_TIER_SPACING := .47
const LB_TO_KG := .45359237
var game: Node
var items: Array=[]
var models:={}
var rack_models:={}
var rack_slot_ids := {}
var rack_order: Array[int] = []
var rack_frame: Node3D
var remote_models:={}
var last_sent:=0.0
var panel: PanelContainer
var choices: ItemList
var held_visual: Node3D
func _init() -> void:
 for id in SIZES.size():rack_order.append(id)
 rack_order.sort_custom(func(a: int,b: int):return float(SIZES[a]) > float(SIZES[b]))

func build(owner: Node) -> void:
 game=owner
 for i in SIZES.size():items.append({"lb":SIZES[i],"owner":0,"where":"rack","position":Vector3.ZERO,"rack_slot":rack_order.find(i)})
 _build_rack()
 game.session.roster_changed.connect(_roster_changed)
 game.session.restarted.connect(_reset)
 _render()

func _radius(lb: float) -> float:
 return lerpf(.035, .13, sqrt(lb / 200.0))

func _slot_position(slot: int) -> Vector3:
 var tier := int(slot / RACK_COLUMNS)
 var column := slot % RACK_COLUMNS
 return RACK + Vector3((float(column) - 4.0) * RACK_SPACING, .26 + float(tier) * RACK_TIER_SPACING + _radius(SIZES[rack_order[slot]]), 0)

func _build_rack() -> void:
 rack_frame=StaticBody3D.new();rack_frame.name="DumbbellRackFrame";rack_frame.collision_layer=1;rack_frame.collision_mask=0;add_child(rack_frame)
 var steel:=StandardMaterial3D.new();steel.albedo_color=Color("53616a");steel.metallic=.62;steel.roughness=.42
 var rubber:=StandardMaterial3D.new();rubber.albedo_color=Color("313a41");rubber.roughness=.92
 for x in [-2.78, 0.0, 2.78]:
  _rack_bar(Vector3(x,.055,0),Vector3(.16,.11,.78),steel)
  _rack_bar(Vector3(x,.865,-.25),Vector3(.09,1.73,.1),steel)
 for tier in 4:
  _rack_bar(Vector3(0,.204+float(tier)*RACK_TIER_SPACING,0),Vector3(5.64,.064,.62),steel)
 for slot in RACK_SLOTS:
  var rest := _slot_position(slot) - RACK - Vector3.UP * (_radius(SIZES[rack_order[slot]]) + .012)
  _rack_bar(rest,Vector3(.57,.024,.56),rubber)

func _rack_bar(at: Vector3,size: Vector3,steel: Material) -> void:
 var visual:=MeshInstance3D.new();var mesh:=BoxMesh.new();mesh.size=size;visual.mesh=mesh;visual.material_override=steel;visual.position=RACK+at;rack_frame.add_child(visual)
 var hit:=CollisionShape3D.new();var shape:=BoxShape3D.new();shape.size=size;hit.shape=shape;hit.position=RACK+at;rack_frame.add_child(hit)
func _pair_model(lb: float) -> Node3D:
 var root:=Node3D.new()
 var metal:=StandardMaterial3D.new();metal.albedo_color=Color("aabcc0");metal.metallic=.7;metal.roughness=.35
 var rubber:=StandardMaterial3D.new();rubber.albedo_color=Color("252e35");rubber.roughness=.84
 var radius:=_radius(lb);var width:=lerpf(.05,.15,sqrt(lb/200.0))
 for side in [-1.0,1.0]:
  var dumbbell:=Node3D.new();dumbbell.name="LeftDumbbell" if side<0 else "RightDumbbell";dumbbell.position.x=side*(radius+.018);root.add_child(dumbbell)
  # Each dumbbell runs front-to-back on the tray; the pair sits shoulder to
  # shoulder across the rack instead of extending down the shelf in a line.
  var bar:=MeshInstance3D.new();var shaft:=CylinderMesh.new();shaft.height=.19;shaft.top_radius=.015;shaft.bottom_radius=.015;shaft.radial_segments=10;bar.mesh=shaft;bar.material_override=metal;bar.rotation.x=PI/2;dumbbell.add_child(bar)
  for end in [-1.0,1.0]:
   var collar:=MeshInstance3D.new();var collar_mesh:=CylinderMesh.new();collar_mesh.height=.025;collar_mesh.top_radius=.025;collar_mesh.bottom_radius=.025;collar_mesh.radial_segments=12
   collar.mesh=collar_mesh;collar.material_override=metal;collar.rotation.x=PI/2;collar.position=Vector3(0,0,end*.092);dumbbell.add_child(collar)
   var disk:=MeshInstance3D.new();var mesh:=CylinderMesh.new();mesh.height=width;mesh.top_radius=radius;mesh.bottom_radius=radius;mesh.radial_segments=12;disk.mesh=mesh;disk.material_override=rubber;disk.rotation.x=PI/2;disk.position=Vector3(0,0,end*(.10+width*.5));dumbbell.add_child(disk)
   var cap:=MeshInstance3D.new();var cap_mesh:=CylinderMesh.new()
   cap_mesh.height=.008;cap_mesh.top_radius=radius*.77;cap_mesh.bottom_radius=radius*.82;cap_mesh.radial_segments=12
   cap.mesh=cap_mesh;cap.material_override=metal;cap.rotation.x=end*PI/2;cap.position.z=end*(.10+width+.002);dumbbell.add_child(cap)
   var marking:=Label3D.new();marking.text=_weight_mark(lb);marking.font_size=36;marking.pixel_size=radius*.022;marking.modulate=Color("263239");marking.outline_size=0
   marking.position=Vector3(0,0,end*(.10+width+.007));marking.rotation.y=PI if end<0 else 0.0;dumbbell.add_child(marking)
 return root

func _weight_mark(lb: float) -> String:
 return str(roundi(lb)) if is_equal_approx(lb,roundf(lb)) else "%.1f" % lb
func _refresh_panel() -> void:
 choices.clear()
 for i in items.size():
  var entry: Dictionary=items[i]
  choices.add_item("%s lb each  ·  %s" % [_weight_mark(float(entry.lb)),"Available" if entry.where=="rack" else "In use"])
  choices.set_item_disabled(i,entry.where!="rack")
func interact(target: Node) -> bool:
 if not is_instance_valid(target):return false
 var role:=str(target.get_meta("role",""))
 if role=="gym_dumbbell_pair":
  var id:=int(target.get_meta("id",-1))
  if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return true
  if game.hotbar.stow():request("pickup",id)
  return true
 if role=="gym_dumbbell_rack_slot":
  var held:=held_id(multiplayer.get_unique_id())
  if held>=0:request("return",held,null,int(target.get_meta("slot",-1)))
  return true
 if role=="gym_dumbbell_rack":
  return true
 if role=="gym_dumbbell_floor":
  if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return true
  if not game.hotbar.stow():return true
  request("pickup",int(target.get_meta("id",-1)));return true
 return false
func _take() -> void:
 var selected:=choices.get_selected_items()
 if selected.is_empty():return
 if not game.hotbar.slots.any(func(slot):return slot.is_empty()):game.ui.log_message("Free a hotbar slot first.");return
 if not game.hotbar.stow():return
 request("pickup",int(selected[0]));_close()
func _return() -> void:
 var id:=held_id(multiplayer.get_unique_id())
 if id>=0:request("return",id);_close()
func _close() -> void:
 panel.hide()
 if game.front.in_game:game.capture()
func held_id(peer: int) -> int:
 for i in items.size():
  if int(items[i].owner)==peer and items[i].where=="held":return i
 return -1
func held_mass(peer: int) -> float:
 var id:=held_id(peer)
 return float(items[id].lb)*2.0*LB_TO_KG if id>=0 else 0.0
func request(op: String,id: int,point: Variant=null,rack_slot: int=-1) -> void:
 if multiplayer.is_server():_accept(multiplayer.get_unique_id(),op,id,point,rack_slot)
 elif game.session.online:_command.rpc_id(1,op,id,point,rack_slot)
@rpc("any_peer","call_remote","reliable")
func _command(op: String,id: int,point: Variant,rack_slot: int) -> void:
 if multiplayer.is_server():_accept(multiplayer.get_remote_sender_id(),op,id,point,rack_slot)
func _accept(peer: int,op: String,id: int,point: Variant=null,rack_slot: int=-1) -> void:
 if not game.session.roster.has(peer) or id not in range(items.size()):return
 if point!=null and (not point is Vector3 or not point.is_finite()):return
 if is_instance_valid(game.campus_services) and game.campus_services.facilities.controller.host.movement_locked(peer):return
 var item: Dictionary=items[id]
 var pos: Vector3=game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
 if not pos.is_finite():return
 if op=="pickup":
  if held_id(peer)>=0:return
  var target: Vector3=_slot_position(int(item.get("rack_slot",id))) if item.where=="rack" else item.position
  if item.where not in ["rack","floor"] or pos.distance_to(target)>3.0:return
  item.owner=peer;item.where="held"
 elif op=="stow":
  if item.owner!=peer or item.where!="held":return
  item.where="stowed"
 elif op=="equip":
  if item.owner!=peer or item.where!="stowed" or held_id(peer)>=0:return
  item.where="held"
 elif op=="return":
  if item.owner!=peer or item.where!="held":return
  var chosen:=rack_slot
  if chosen not in range(RACK_SLOTS):
   chosen=-1
   for candidate in RACK_SLOTS:
    var occupied:=false
    for other in items:
     if other.where=="rack" and int(other.get("rack_slot",-1))==candidate:occupied=true;break
    if not occupied and rack_order[candidate] == id and pos.distance_to(_slot_position(candidate))<=3.0:chosen=candidate;break
  if chosen not in range(RACK_SLOTS) or rack_order[chosen] != id or pos.distance_to(_slot_position(chosen))>3.0:return
  for other in items:
   if other.where=="rack" and int(other.get("rack_slot",-1))==chosen:return
  item.owner=0;item.where="rack";item.rack_slot=chosen
 elif op=="drop":
  if item.owner!=peer or item.where!="held":return
  var ground: Variant=preload("res://scripts/campus/items/placement_target.gd").host_position(game.school,point,pos,peer)
  if not ground is Vector3:return
  item.owner=0;item.where="floor";item.position=ground
 else:return
 _publish()
func _publish() -> void:
 _render()
 _broadcast()
func _broadcast() -> void:
 if not game.session.online:return
 for peer in game.session.roster:
  if int(peer)!=multiplayer.get_unique_id() and game.session.peer_connected_now(int(peer)):_receive.rpc_id(int(peer),items)
@rpc("authority","call_remote","reliable")
func _receive(snapshot: Array) -> void:
 if snapshot.size()!=SIZES.size() or snapshot==items:return
 items=snapshot.duplicate(true);_render()
func _render() -> void:
 var occupied_slots:={}
 for id in items.size():
  var entry: Dictionary=items[id]
  if entry.where=="rack":occupied_slots[int(entry.get("rack_slot",id))]=id
 for slot in RACK_SLOTS:
  var item_id := int(occupied_slots.get(slot, -1))
  if rack_slot_ids.get(slot, -2) == item_id:
   continue
  if rack_models.has(slot) and is_instance_valid(rack_models[slot]):
   remove_child(rack_models[slot])
   rack_models[slot].queue_free()
  rack_slot_ids[slot] = item_id
  var target:=StaticBody3D.new();target.position=_slot_position(slot);target.collision_layer=4;target.collision_mask=0
  if occupied_slots.has(slot):
   var id:=int(occupied_slots[slot]);target.set_meta("role","gym_dumbbell_pair");target.set_meta("id",id);target.set_meta("label","Pick up %.1f lb dumbbell pair" % float(items[id].lb))
   var visual:=_pair_model(float(items[id].lb));target.add_child(visual)
  else:
   target.set_meta("role","gym_dumbbell_rack_slot");target.set_meta("slot",slot);target.set_meta("label","Empty dumbbell rack slot")
  var hit:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.60,.30,.54);hit.shape=box;target.add_child(hit)
  add_child(target);rack_models[slot]=target
 for node in models.values():
  if is_instance_valid(node):node.queue_free()
 models.clear()
 for i in items.size():
  var entry: Dictionary=items[i]
  if entry.where!="floor":continue
  var target:=StaticBody3D.new();target.position=entry.position;target.collision_layer=4;target.collision_mask=0;target.set_meta("role","gym_dumbbell_floor");target.set_meta("id",i);target.set_meta("label","%.1f lb dumbbell pair"%entry.lb);add_child(target)
  var visual:=_pair_model(float(entry.lb));visual.position.y=_radius(float(entry.lb));target.add_child(visual)
  var hit:=CollisionShape3D.new();var box:=BoxShape3D.new();box.size=Vector3(.6,.3,.35);hit.shape=box;hit.position.y=.15;target.add_child(hit);models[i]=target
func _roster_changed() -> void:
 if not multiplayer.is_server():return
 for entry in items:
  if int(entry.owner)!=0 and not game.session.roster.has(int(entry.owner)):entry.owner=0;entry.where="rack"
 _publish()
func _reset() -> void:
 for entry in items:entry.owner=0;entry.where="rack"
 _render()
func _sync_remote_visuals() -> void:
 var wanted:={}
 var local:=multiplayer.get_unique_id()
 for id in items.size():
  var entry: Dictionary=items[id]
  var peer:=int(entry.owner)
  if peer<=0 or peer==local or entry.where!="held" or not game.avatars.has(peer):continue
  var avatar: Node3D=game.avatars[peer]
  var body:=avatar.get_node_or_null("CharacterModel") as Node3D
  if not is_instance_valid(body):continue
  wanted[peer]=id
  var previous: Dictionary=remote_models.get(peer,{})
  if int(previous.get("id",-1))==id and previous.get("body")==body:
   _update_remote_hands(previous)
   continue
  _clear_remote(peer)
  var parts:=[];var joints:=[]
  for spec in [["ArmL",-1.0],["ArmR",1.0]]:
   var arm:=body.find_child(str(spec[0]),true,false) as Node3D
   if arm==null:continue
   var visual:=_pair_model(float(entry.lb))
   for child in visual.get_children():
    if signf(child.position.x)!=float(spec[1]):visual.remove_child(child);child.queue_free()
    else:child.position=Vector3.ZERO
   var hand: Node3D=preload("res://scripts/campus/facilities/arm_bend.gd").hand_for(arm)
   arm.add_child(visual)
   if is_instance_valid(hand):joints.append({"visual":visual,"hand":hand})
   else:visual.position=Vector3(0,-.48,.05)
   parts.append(visual)
  remote_models[peer]={"id":id,"body":body,"parts":parts,"joints":joints}
  _update_remote_hands(remote_models[peer])
 for peer in remote_models.keys():
  if not wanted.has(peer):_clear_remote(peer)
func _update_remote_hands(entry: Dictionary) -> void:
 for joint in entry.get("joints",[]):
  var hand: Node3D=joint.hand;var visual: Node3D=joint.visual
  if not is_instance_valid(hand) or not is_instance_valid(visual):continue
  # Hand meshes have non-uniform shape scale; use only their orientation so
  # the dumbbell does not inherit that tiny mesh scale.
  var orientation:=hand.transform.basis.orthonormalized()
  visual.transform=Transform3D(orientation,hand.position+orientation*Vector3(0,0,.038))
func _clear_remote(peer: int) -> void:
 if not remote_models.has(peer):return
 for visual in remote_models[peer].parts:
  if is_instance_valid(visual):visual.queue_free()
 remote_models.erase(peer)

func _process(delta: float) -> void:
 if not is_instance_valid(game):return
 if multiplayer.is_server() and game.session.online:
  last_sent+=delta
  if last_sent>=5:last_sent=0;_broadcast()
 var id:=held_id(multiplayer.get_unique_id())
 if id!=int(get_meta("visual_id",-2)):
  set_meta("visual_id",id)
  if is_instance_valid(held_visual):held_visual.queue_free();held_visual=null
  if id>=0:
   held_visual=_pair_model(float(items[id].lb));game.camera.add_child(held_visual)
   for child in held_visual.get_children():child.position=Vector3(-.23 if child.name=="LeftDumbbell" else .23,-.28,-.52)
 if is_instance_valid(held_visual):
  var hide_idle_gear: bool=game.workout_hides_carried_items()
  var exercise: Dictionary=game.campus_services.facility_panel.state.get("active",{})
  held_visual.visible=game.front.in_game and game.player.enabled and (not hide_idle_gear or exercise.get("equipment")=="dumbbell")
  if not hide_idle_gear:
   for child in held_visual.get_children():
    child.position=Vector3(-.23 if child.name=="LeftDumbbell" else .23,-.28,-.52)
    child.rotation=Vector3.ZERO
 _sync_remote_visuals()
