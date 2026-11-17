extends Node3D
const Model = preload("res://scripts/campus/ac_laptops/model.gd")
const CableMesh = preload("res://scripts/cable_mesh.gd")
var game: Node
var model = Model.new()
var state: Dictionary = {}
var visuals: Node3D
var cabinet_doors: Node3D
var cabinet_items: Node3D
var cabinet_front: StaticBody3D
var laptop_roots: Array = []
var floor_cables: Array = []
var panel: CanvasLayer
var plot: Control
var values: Label
var legend: RichTextLabel
var table_scroll: ScrollContainer
var table_grid: GridContainer
var selected_view := "graph"
var table_signature := ""
var subtitle: Label
var view_id := -1
var refresh_clock := 0.0
var cable_views := {}
var keyboard_instances: MultiMesh
var keyboard_material: StandardMaterial3D
var held_cable_visual: Node3D

func build(owner_game: Node) -> void:
 game=owner_game
 state=model.snapshot()
 visuals=Node3D.new();visuals.name="LaptopVisuals";add_child(visuals)
 _build_cabinet()
 held_cable_visual=Node3D.new();game.camera.add_child(held_cable_visual)
 held_cable_visual.position=Vector3(.35,-.3,-.65)
 var loop:=TorusMesh.new();loop.inner_radius=.045;loop.outer_radius=.06;loop.rings=16;loop.ring_segments=8
 var coil:=MeshInstance3D.new();coil.mesh=loop;coil.material_override=_material(Color("202d34"));coil.rotation.x=PI/2;held_cable_visual.add_child(coil)
 for i in Model.COUNT:
  var root:=Node3D.new();root.name="Laptop%d"%i;visuals.add_child(root);laptop_roots.append(root)
  _build_laptop(root,i)
  var floor_cable:=_target(visuals,"ac_usb_floor",i,Vector3.ZERO,Vector3(.25,.08,.25))
  floor_cable.name="FloorUSB%d"%i;_coiled_cable(floor_cable);floor_cables.append(floor_cable)
 game.session.roster_changed.connect(_roster_changed)
 game.session.leaving.connect(_session_end)
 game.session.restarted.connect(_session_end)
 multiplayer.peer_disconnected.connect(_peer_left)
 _render()

func _material(color: Color) -> StandardMaterial3D:
 var m:=StandardMaterial3D.new();m.albedo_color=color;m.roughness=.72;return m
func _box(parent: Node3D, pos: Vector3, size: Vector3, color: Color) -> MeshInstance3D:
 var mesh:=BoxMesh.new();mesh.size=size
 var item:=MeshInstance3D.new();item.mesh=mesh;item.position=pos;item.material_override=_material(color);parent.add_child(item);return item
func _target(parent: Node3D, role: String, id: int, pos: Vector3, size: Vector3) -> StaticBody3D:
 var body:=StaticBody3D.new();body.position=pos;body.collision_layer=4;body.collision_mask=0
 body.set_meta("role",role);body.set_meta("laptop_id",id);parent.add_child(body)
 var shape:=BoxShape3D.new();shape.size=size
 var hit:=CollisionShape3D.new();hit.shape=shape;body.add_child(hit)
 return body
func _build_cabinet() -> void:
 var cabinet:=Node3D.new();cabinet.name="LaptopCabinet";cabinet.position=Model.CABINET;add_child(cabinet)
 _box(cabinet,Vector3(0,.85,.31),Vector3(1.3,1.7,.06),Color("415b68"))
 for x in [-.62,.62]:_box(cabinet,Vector3(x,.85,0),Vector3(.06,1.7,.65),Color("536f79"))
 for y in [.03,.83,1.67]:_box(cabinet,Vector3(0,y,0),Vector3(1.3,.06,.65),Color("536f79"))
 cabinet_doors=Node3D.new();cabinet.add_child(cabinet_doors)
 for side in [-1,1]:
  var hinge:=Node3D.new();hinge.name="Left" if side<0 else "Right";hinge.position=Vector3(side*.62,0,-.34);cabinet_doors.add_child(hinge)
  _box(hinge,Vector3(-side*.31,.85,0),Vector3(.60,1.62,.06),Color("647e83"))
  _box(hinge,Vector3(-side*.51,.85,-.04),Vector3(.025,.22,.025),Color("cfddd1"))
 cabinet_front=_target(cabinet,"ac_laptop_cabinet",-1,Vector3(0,.85,-.4),Vector3(1.3,1.7,.14))
 _target(cabinet,"ac_laptop_cabinet",-1,Vector3(-.68,.85,-.2),Vector3(.12,1.7,.5))
 cabinet_items=Node3D.new();cabinet.add_child(cabinet_items)
 for i in Model.COUNT:
  var x:float=-.43+(i%3)*.43;var shelf:float=.06+int(i/3)*.80
  var body:=_target(cabinet_items,"ac_laptop_stored",i,Vector3(x,shelf+.035,-.12),Vector3(.36,.075,.27))
  _closed_laptop(body)
  var cable:=_target(cabinet_items,"ac_usb_stored",i,Vector3(x,shelf+.025,.18),Vector3(.30,.05,.22))
  _coiled_cable(cable)
func _closed_laptop(parent: Node3D) -> void:
 _box(parent,Vector3(0,-.012,0),Vector3(.35,.025,.25),Color("273a47"))
 _box(parent,Vector3(0,.012,0),Vector3(.35,.025,.25),Color("718892"))
 _box(parent,Vector3(0,.026,0),Vector3(.09,.002,.014),Color("c1d4d2"))
 _box(parent,Vector3(0,-.025,-.10),Vector3(.27,.012,.015),Color("101d24"))
func _coiled_cable(parent: Node3D) -> void:
 var points: Array[Vector3]=[]
 for j in 65:
  var t:=float(j)/64.0
  var angle:=TAU*2.1*t
  var radius:=.067+.006*t
  points.append(Vector3(cos(angle)*radius,.002+t*.006,sin(angle)*radius))
 var coil:=MeshInstance3D.new();coil.mesh=CableMesh.tube(points,.006,.006);coil.material_override=CableMesh.jacket_material(Color("343f48"));parent.add_child(coil)
 for x in [-.10,.10]:
  _box(parent,Vector3(x,0,0),Vector3(.045,.018,.025),Color("202d34"))
  _box(parent,Vector3(x+(.025 if x>0 else -.025),0,0),Vector3(.014,.012,.018),Color("c0c8c4"))
func _build_laptop(root: Node3D,id: int) -> void:
 var body:=_target(root,"ac_laptop",id,Vector3(0,.035,0),Vector3(.46,.10,.33))
 _box(body,Vector3.ZERO,Vector3(.46,.045,.32),Color("667b84"))
 _box(body,Vector3(0,.026,-.035),Vector3(.40,.007,.185),Color("273a46"))
 if keyboard_instances==null:
  keyboard_instances=MultiMesh.new();keyboard_instances.transform_format=MultiMesh.TRANSFORM_3D
  var key_mesh:=BoxMesh.new();key_mesh.size=Vector3(.029,.006,.027);keyboard_instances.mesh=key_mesh;keyboard_instances.instance_count=40
  for row in 4:
   for col in 10:keyboard_instances.set_instance_transform(row*10+col,Transform3D(Basis.IDENTITY,Vector3(-.174+col*.038,.031,-.108+row*.041)))
  keyboard_material=_material(Color("a4b5b4"))
 var keys:=MultiMeshInstance3D.new();keys.multimesh=keyboard_instances;keys.material_override=keyboard_material;keys.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF;body.add_child(keys)
 _box(body,Vector3(0,.028,.108),Vector3(.13,.004,.065),Color("91a5a9"))
 var lid:=Node3D.new();lid.name="Lid";lid.position=Vector3(0,.06,-.15);root.add_child(lid)
 _box(lid,Vector3(0,.13,0),Vector3(.46,.26,.025),Color("718892"))
 _box(lid,Vector3(0,.13,.014),Vector3(.42,.225,.006),Color("182b36"))
 _box(lid,Vector3(0,.13,.018),Vector3(.385,.188,.003),Color("315e70"))
 _box(lid,Vector3(0,.13,-.014),Vector3(.08,.012,.003),Color("c1d4d2"))
 var port:=_target(root,"ac_laptop_usb",id,Vector3(.23,.045,0),Vector3(.055,.08,.12))
 _box(port,Vector3(.002,0,0),Vector3(.002,.014,.055),Color("10151b"))

func _roster_changed() -> void:
 if multiplayer.is_server():_publish()
func _session_end() -> void:
 if multiplayer.is_server():model.reset();_publish()
 _close_view(false)
func _peer_left(peer: int) -> void:
 if multiplayer.is_server():model.release(peer);_publish()
func _actor_position(peer: int) -> Vector3:
 return game.player.global_position if peer==multiplayer.get_unique_id() else game.session.poses.get(peer,{}).get("position",Vector3.INF)
func request(op: String,id := -1,point := Vector3.ZERO,station := -1) -> void:
 if op in ["take_laptop","take_cable","pickup","pickup_cable","disconnect"]:
  game.hotbar._sync_dorm_items()
  if game.hotbar.slots.count({})==0:
   game.ui.log_message("Free a hotbar slot first.");return
 if game.session.online and not multiplayer.is_server():_request.rpc_id(1,op,id,point,station)
 else:_apply(multiplayer.get_unique_id(),op,id,point,station)
@rpc("any_peer","call_remote","reliable")
func _request(op: String,id: int,point: Vector3,station: int) -> void:
 if multiplayer.is_server():_apply(multiplayer.get_remote_sender_id(),op,id,point,station)
func _apply(peer: int,op: String,id: int,point: Vector3,station: int) -> void:
 if not game.session.roster.has(peer):return
 if op in ["take_laptop","take_cable","pickup","pickup_cable"] and not game.dc_lab._can_hold_lead(peer):
  if peer==multiplayer.get_unique_id():game.ui.log_message("Put down the item you are holding first.")
  else:_notice.rpc_id(peer,"Put down the item you are holding first.")
  return
 if op=="place_laptop":
  var laptop_id:=model.held_laptop(peer)
  if laptop_id<0 or not point.is_finite() or not _actor_position(peer).is_finite() or point.distance_to(_actor_position(peer))>3.0:return
  var surface:=get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(point+Vector3.UP*.08,point-Vector3.UP*.13,5))
  if surface.is_empty() or surface.normal.y<.8 or surface.position.distance_to(point)>.08:
   if peer==multiplayer.get_unique_id():game.ui.log_message("Choose a flat surface for the laptop.")
   else:_notice.rpc_id(peer,"Choose a flat surface for the laptop.")
   return
  point=surface.position+Vector3.UP*.04
  var cable_id:=model.attached_to_laptop(laptop_id) if laptop_id>=0 else -1
  if cable_id>=0 and model.cables[cable_id].where=="connected":
   var linked_station:int=model.cables[cable_id].station
   if point.distance_to(game.session.labs[linked_station].positions.daq)>5.0:
    if peer==multiplayer.get_unique_id():game.ui.log_message("The USB cable cannot reach that far.")
    else:_notice.rpc_id(peer,"The USB cable cannot reach that far.")
    return
 if op=="attach_daq":
  if station not in range(game.session.labs.size()):return
  point=game.session.labs[station].positions.get("daq",Vector3.INF)
 if op=="drop_cable":
  var ground:Variant=game.school.ground_drop_position(point,peer)
  if ground==null:return
  point=ground+Vector3.UP*.025
 var error: String=model.apply(peer,_actor_position(peer),op,id,point,station)
 if not error.is_empty():
  if peer==multiplayer.get_unique_id():game.ui.log_message(error)
  else:_notice.rpc_id(peer,error)
  return
 _publish()
@rpc("authority","call_remote","reliable")
func _notice(message: String) -> void:game.ui.log_message(message)
func _publish() -> void:
 state=model.snapshot();_render()
 if game.session.online and multiplayer.is_server():
  for peer in game.session.connected_peers():_receive.rpc_id(peer,state)
@rpc("authority","call_remote","reliable")
func _receive(next: Dictionary) -> void:
 if multiplayer.get_remote_sender_id()!=1:return
 if next.get("laptops",[]).size()!=Model.COUNT or next.get("cables",[]).size()!=Model.COUNT:return
 state=next;_render()
func _held(kind: String) -> int:
 var peer:=multiplayer.get_unique_id()
 for i in Model.COUNT:
  var entry: Dictionary=state[kind][i]
  if entry.owner==peer and entry.where in (["held"] if kind=="laptops" else ["held","partial"]):return i
 return -1
func _attached(id: int) -> int:
 for i in Model.COUNT:
  if state.cables[i].where in ["partial","connected"] and state.cables[i].laptop==id:return i
 return -1
func _render() -> void:
 if not is_instance_valid(visuals):return
 cabinet_doors.get_node("Left").rotation.y=PI/2 if state.cabinet_open else 0.0
 cabinet_doors.get_node("Right").rotation.y=-PI/2 if state.cabinet_open else 0.0
 cabinet_front.collision_layer=0 if state.cabinet_open else 4
 cabinet_items.visible=state.cabinet_open
 for child in cabinet_items.get_children():
  var role:=str(child.get_meta("role",""));var id:=int(child.get_meta("laptop_id",-1))
  if id>=0:child.visible=state.laptops[id].where=="cabinet" if role=="ac_laptop_stored" else state.cables[id].where=="cabinet"
  if child is CollisionObject3D:child.collision_layer=4 if child.visible else 0
 for i in Model.COUNT:
  var info: Dictionary=state.laptops[i];var root: Node3D=laptop_roots[i]
  var was_visible:bool=root.visible
  root.visible=info.where in ["held","placed"]
  for body in root.find_children("*","StaticBody3D",true,false):
   if body.get_meta("role","")=="ac_laptop":body.collision_layer=4 if info.where=="placed" else 0
  root.get_node("Lid").rotation.x=0 if info.open else PI/2.0
  if info.where=="placed":
   root.position=info.position
   root.rotation=Vector3.ZERO
  elif info.where=="held":
   if not was_visible:
    var pose:Vector3=_actor_position(int(info.owner))
    if pose.is_finite():root.position=pose+Vector3(0,1.0,0)
  for child in root.get_children():
   if child is CollisionObject3D:child.collision_layer=4 if info.where=="placed" else 0
  var floor_cable:StaticBody3D=floor_cables[i]
  floor_cable.visible=state.cables[i].where=="placed"
  floor_cable.collision_layer=4 if floor_cable.visible else 0
  if floor_cable.visible:floor_cable.position=state.cables[i].position
 _draw_cables()
 update_indicators()
func update_indicators() -> void:
 for i in mini(3,game.station_snapshots.size()):
  var equipment: Node = game if i==0 else game.stations[i-1].equipment
  if not equipment.terminal_bodies.has("DAQ_POWER_A"):continue
  var lamp := equipment.terminal_bodies.DAQ_POWER_A.get_parent().get_node_or_null("DaqPowerIndicator") as MeshInstance3D
  if lamp==null:continue
  var active: bool=Model.daq_powered(game.station_snapshots[i])
  var material := lamp.material_override as StandardMaterial3D
  if material!=null:
   material.albedo_color=Color("6cfa8e") if active else Color("254b32")
   material.emission_enabled=active
   material.emission=Color("49e675")
func _cable_endpoints(c: Dictionary) -> Array:
 if c.where not in ["connected","partial"] or c.laptop not in range(Model.COUNT):return []
 var a:Vector3=laptop_roots[c.laptop].to_global(Vector3(.23,.045,0))
 var b:Vector3
 if c.where=="partial":
  b=game.held_cable_position() if c.owner==multiplayer.get_unique_id() else _actor_position(c.owner)+Vector3(0,1.1,0)
 else:
  if c.station not in range(game.session.labs.size()):return []
  var equipment: Node=game if c.station==0 else game.stations[c.station-1].equipment
  b=equipment.control_bodies.daq.global_position if equipment.control_bodies.has("daq") else game.session.labs[c.station].positions.get("daq",a)
 return [a,b]

func _draw_cables() -> void:
 var group:=visuals.get_node_or_null("USBCables") as Node3D
 if group==null:
  group=Node3D.new();group.name="USBCables";visuals.add_child(group)
 for i in state.cables.size():
  var endpoints:=_cable_endpoints(state.cables[i])
  if endpoints.is_empty():
   if cable_views.has(i):
    var old:Dictionary=cable_views[i]
    old.mesh.queue_free();old.plug_a.queue_free();old.plug_b.queue_free()
    cable_views.erase(i)
   continue
  if cable_views.has(i):continue
  var a:Vector3=endpoints[0];var b:Vector3=endpoints[1]
  var mesh:=CableMesh.build(a,b,Color("343f48"),game.cable_obstacles);group.add_child(mesh)
  var plug_a:=_box(group,a,Vector3(.045,.025,.075),Color("202d34"))
  var plug_b:=_box(group,b,Vector3(.045,.025,.075),Color("202d34"))
  if a.distance_squared_to(b)>.000001:plug_a.look_at(b,Vector3.UP);plug_b.look_at(a,Vector3.UP)
  cable_views[i]={"mesh":mesh,"plug_a":plug_a,"plug_b":plug_b,"a":a,"b":b}
 _update_moving_cables()

func _update_moving_cables() -> void:
 for i in cable_views:
  var cable:Dictionary=state.cables[i]
  var endpoints:=_cable_endpoints(cable)
  if endpoints.is_empty():continue
  var a:Vector3=endpoints[0];var b:Vector3=endpoints[1]
  var view:Dictionary=cable_views[i]
  if a.distance_squared_to(view.a)<.00000001 and b.distance_squared_to(view.b)<.00000001:continue
  view.mesh.mesh=CableMesh.geometry(a,b,game.cable_obstacles)
  view.plug_a.position=a;view.plug_b.position=b
  if a.distance_squared_to(b)>.000001:view.plug_a.look_at(b,Vector3.UP);view.plug_b.look_at(a,Vector3.UP)
  view.a=a;view.b=b
func _process(delta: float) -> void:
 if not is_instance_valid(game):return
 for i in Model.COUNT:
  if state.laptops[i].where=="held":
   if int(state.laptops[i].owner)==multiplayer.get_unique_id():
    laptop_roots[i].global_transform=Transform3D(game.camera.global_basis,game.camera.to_global(Vector3(.30,-.38,-.65)))
   else:
    var target_position:Vector3=_actor_position(int(state.laptops[i].owner))+Vector3(0,1.0,0)
    if target_position.is_finite():
     laptop_roots[i].position=laptop_roots[i].position.lerp(target_position,1.0-exp(-14.0*delta))
    var target_yaw:float=float(game.session.poses.get(int(state.laptops[i].owner),{}).get("yaw",0.0))
    laptop_roots[i].rotation.y=lerp_angle(laptop_roots[i].rotation.y,target_yaw,1.0-exp(-14.0*delta))
 _update_moving_cables()
 held_cable_visual.visible=_held("cables")>=0 and game.player.enabled
 if is_instance_valid(panel) and panel.visible:
  refresh_clock+=delta
  if refresh_clock>=.1:refresh_clock=0;_refresh_view()
func place_held(point: Vector3) -> bool:
 if _held("laptops")<0:return false
 request("place_laptop",-1,point);return true
func interact(target: Node, right: bool) -> bool:
 if not is_instance_valid(target):return false
 var role:=str(target.get_meta("role",""));var id:=int(target.get_meta("laptop_id",-1))
 if role=="ac_laptop_cabinet":
  if _held("laptops")>=0:request("store_laptop")
  elif _held("cables")>=0:request("store_cable")
  else:request("cabinet")
  return true
 if role=="ac_laptop_stored":request("take_laptop",id);return true
 if role=="ac_usb_stored":request("take_cable",id);return true
 if role=="ac_usb_floor":request("pickup_cable",id);return true
 if role=="ac_laptop_usb" and not right:
  if _held("cables")>=0:request("attach_laptop",id)
  elif _attached(id)>=0:request("disconnect",_attached(id))
  else:game.ui.log_message("Take a USB cable from the cabinet first.")
  return true
 if role=="ac_daq_usb" and not right:
  request("attach_daq",-1,Vector3.ZERO,int(target.get_meta("station",0)));return true
 if role=="ac_laptop":
  if right:
   if state.laptops[id].open:_open_view(id)
   else:request("open",id)
  elif state.laptops[id].open:request("close",id)
  else:request("pickup",id)
  return true
 return false
func hint(target: Node) -> String:
 if not is_instance_valid(target):return ""
 var role:=str(target.get_meta("role",""));var id:=int(target.get_meta("laptop_id",-1))
 match role:
  "ac_laptop_cabinet":return "Click: return laptop or USB cable" if _held("laptops")>=0 or _held("cables")>=0 else "Click: open / close cabinet"
  "ac_laptop_stored":return "Click: take laptop"
  "ac_usb_stored":return "Click: take USB cable"
  "ac_usb_floor":return "Click: pick up USB cable"
  "ac_laptop_usb":return "Click: connect or disconnect laptop cable"
  "ac_daq_usb":return "Click: connect laptop cable to DAQ"
  "ac_laptop":return "Right-click: view - Left-click: close" if state.laptops[id].open else "Right-click: open - Left-click: pick up"
 return ""
func _open_view(id: int) -> void:
 view_id=id
 if not is_instance_valid(panel):
  panel=CanvasLayer.new();panel.layer=50;add_child(panel)
  var background:=ColorRect.new();background.color=Color(0.02,0.06,0.09,.48);background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);panel.add_child(background)
  var frame:=PanelContainer.new();frame.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
  frame.offset_left=-460;frame.offset_right=460;frame.offset_top=-305;frame.offset_bottom=305
  var frame_style:=StyleBoxFlat.new();frame_style.bg_color=Color("102b39");frame_style.border_color=Color("537a86");frame_style.set_border_width_all(2);frame_style.set_corner_radius_all(14)
  frame.add_theme_stylebox_override("panel",frame_style);panel.add_child(frame)
  var margin:=MarginContainer.new()
  margin.add_theme_constant_override("margin_left",24);margin.add_theme_constant_override("margin_right",24);margin.add_theme_constant_override("margin_top",20);margin.add_theme_constant_override("margin_bottom",20);frame.add_child(margin)
  var column:=VBoxContainer.new();column.theme=preload("res://scripts/ui/design_system/theme.gd").create();column.add_theme_constant_override("separation",10);margin.add_child(column)
  var heading:=Label.new();heading.text="DATA ACQUISITION";heading.add_theme_font_size_override("font_size",28);column.add_child(heading)
  subtitle=Label.new();subtitle.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;column.add_child(subtitle)
  var buttons:=HBoxContainer.new();column.add_child(buttons)
  for entry in [["Graph","graph"],["Phasor display","phasor"],["Table","table"]]:
   var button:=Button.new();button.text=entry[0];buttons.add_child(button)
   button.pressed.connect(_set_view.bind(str(entry[1])))
  plot=preload("res://scripts/campus/ac_laptops/plot.gd").new();plot.size_flags_vertical=Control.SIZE_EXPAND_FILL;plot.custom_minimum_size=Vector2(500,240);column.add_child(plot)
  table_scroll=ScrollContainer.new();table_scroll.size_flags_vertical=Control.SIZE_EXPAND_FILL;table_scroll.custom_minimum_size=Vector2(500,240);column.add_child(table_scroll)
  table_grid=GridContainer.new();table_grid.add_theme_constant_override("h_separation",20);table_grid.add_theme_constant_override("v_separation",8);table_scroll.add_child(table_grid)
  legend=RichTextLabel.new();legend.bbcode_enabled=true;legend.fit_content=false;legend.scroll_active=true;legend.custom_minimum_size.y=60;column.add_child(legend)
  values=Label.new();values.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;values.custom_minimum_size.y=48;column.add_child(values)
  _set_view("graph")
  var back:=Button.new();back.text="Return to laboratory";column.add_child(back);back.pressed.connect(func():_close_view(true))
 panel.show();game.release_mouse();_refresh_view()
func _set_view(view: String) -> void:
 selected_view=view
 if not is_instance_valid(plot):return
 plot.visible=view!="table"
 table_scroll.visible=view=="table"
 if view!="table":plot.mode=view;plot.queue_redraw()
 if view=="table":_refresh_table()

func _refresh_table() -> void:
 if not is_instance_valid(table_grid):return
 var signature:=str([plot.connected,plot.frequency])
 if signature==table_signature:return
 table_signature=signature
 for child in table_grid.get_children():child.queue_free();table_grid.remove_child(child)
 table_grid.columns=1+plot.connected.size()
 var headings: Array=["Time (ms)"]
 for c in plot.connected:headings.append("%s (%s)"%[c.name,c.kind])
 for heading in headings:_table_cell(str(heading),true)
 if plot.connected.is_empty():
  _table_cell("No connected channels",false);return
 for row in 9:
  var cycles:=float(row)*.25
  _table_cell("%.2f"%(cycles/maxf(.001,plot.frequency)*1000.0),false)
  for c in plot.connected:_table_cell("%+.3f"%plot.sample(c,cycles),false)

func _table_cell(text: String,header: bool) -> void:
 var label:=Label.new();label.text=text;label.custom_minimum_size.x=105
 label.add_theme_font_size_override("font_size",14)
 if header:label.add_theme_color_override("font_color",Color("9aefdd"))
 table_grid.add_child(label)

func _close_view(recapture: bool) -> void:
 if not is_instance_valid(panel) or not panel.visible:return
 panel.hide();view_id=-1
 if recapture:game.capture()
func _refresh_view() -> void:
 if view_id not in range(Model.COUNT) or not state.laptops[view_id].open:
  _close_view(true);return
 var cable:=_attached(view_id)
 if cable<0 or state.cables[cable].where!="connected":
  subtitle.text="Connect a laptop cable to this laptop and the DAQ Computer I/O port."
  plot.connected=[];plot.queue_redraw();values.text="";legend.text="";_refresh_table();return
 var station:int=state.cables[cable].station
 if station not in range(game.station_snapshots.size()):return
 var data: Dictionary=game.station_snapshots[station]
 plot.frequency=maxf(.001,float(data.get("frequency",60.0)))
 if not Model.daq_powered(data):
  subtitle.text="DAQ has no low power: connect a low-power supply socket to a DAQ low-power input and turn on the supply."
  plot.connected=[];plot.queue_redraw();values.text="";legend.text="";_refresh_table();return
 subtitle.text="Connected to AC station %d Â· measured RMS phasors" % (station+1)
 var ports:={}
 for wire in data.get("cables",[]):
  if str(wire.get("a",""))!="" and str(wire.get("b",""))!="":ports[wire.a]=true;ports[wire.b]=true
 var data_readings: Dictionary=data.get("readings",{})
 var channels:=[];var lines:=[]
 for i in 4:
  for entry in [["E","V","daq_v","daq_dc_v"],["I","A","daq_i","daq_dc_i"]]:
   var prefix:String="DAQ_%s%d_"%[entry[0],i]
   var is_connected:bool=ports.has(prefix+"N") and (ports.has(prefix+"P") if entry[0]=="E" else ports.has(prefix+"4") or ports.has(prefix+"40"))
   if not is_connected:continue
   var arr:Array=data_readings.get(entry[2],[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
   var dc_arr:Array=data_readings.get(entry[3],[Vector2.ZERO,Vector2.ZERO,Vector2.ZERO,Vector2.ZERO])
   var phasor:Vector2=arr[i];var dc:Vector2=dc_arr[i]
   var name:String="%s%d"%[entry[0],i+1]
   channels.append({"name":name,"kind":entry[1],"value":phasor,"dc":dc.x,"color":i+(0 if entry[0]=="E" else 4)})
   lines.append("%s  %.3f %s âˆ  %.1fÂ°  DC %+.3f %s"%[name,phasor.length(),entry[1],rad_to_deg(phasor.angle()),dc.x,entry[1]])
 plot.connected=channels;plot.queue_redraw()
 var legend_entries:=PackedStringArray()
 for c in channels:
  var rgb: String=plot.COLORS[int(c.color)].to_html(false)
  var angle:=rad_to_deg(c.value.angle())
  legend_entries.append("[color=#%s]● %s[/color]  %s(t) = %.3f cos(2π × %.1f t + %.1f°) %+.3f %s"%[rgb,c.name,c.name,sqrt(2.0)*c.value.length(),plot.frequency,angle,c.dc,c.kind])
 legend.text="\n".join(legend_entries)
 _refresh_table()
 values.text="     ".join(lines) if not lines.is_empty() else "No voltage or current channels are connected."
