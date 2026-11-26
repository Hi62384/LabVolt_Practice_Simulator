extends SceneTree
const LaptopModel = preload("res://scripts/campus/ac_laptops/model.gd")
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var svc=game.ac_laptops
 var cabinet_position := LaptopModel.CABINET
 game.player.global_position=cabinet_position+Vector3(0,0,-1.4)
 var side_ray:=PhysicsRayQueryParameters3D.create(cabinet_position+Vector3(1,.55,0),cabinet_position+Vector3(.4,.55,0),1)
 var side_hit:=game.get_world_3d().direct_space_state.intersect_ray(side_ray) as Dictionary
 assert(not side_hit.is_empty() and side_hit.collider.get_meta("role","")=="ac_laptop_cabinet")
 var blocked_ray:=PhysicsRayQueryParameters3D.create(cabinet_position+Vector3(.3,1,-.9),cabinet_position+Vector3(.3,1,-.2),1)
 var blocked_hit:=game.get_world_3d().direct_space_state.intersect_ray(blocked_ray) as Dictionary
 assert(not blocked_hit.is_empty() and blocked_hit.collider.get_meta("role","")=="ac_laptop_cabinet_door")
 var ray:=PhysicsRayQueryParameters3D.create(cabinet_position+Vector3(0,.85,-1.3),cabinet_position+Vector3(0,.85,-.35),5)
 var hit: Dictionary=game.get_world_3d().direct_space_state.intersect_ray(ray)
 assert(not hit.is_empty() and hit.collider.get_meta("role","")=="ac_laptop_cabinet_door")
 assert(svc.interact(hit.collider,false) and svc.state.cabinet_open)
 var opened_door: Node3D = svc.cabinet_doors.get_node("Left")
 assert(is_zero_approx(opened_door.rotation.y))
 await create_timer(svc.CABINET_SWING_SECONDS*.5,false,true).timeout
 assert(opened_door.rotation.y>0.0 and opened_door.rotation.y<PI/2)
 await svc.cabinet_motion.finished
 await physics_frame
 var door_point := opened_door.to_global(Vector3(.32,.85,0))
 ray=PhysicsRayQueryParameters3D.create(door_point-Vector3(.6,0,0),door_point+Vector3(.06,0,0),1)
 hit=game.get_world_3d().direct_space_state.intersect_ray(ray)
 assert(not hit.is_empty() and hit.collider.get_parent()==opened_door)
 assert(svc.interact(hit.collider,false) and not svc.state.cabinet_open)
 assert(is_equal_approx(opened_door.rotation.y,PI/2))
 await svc.cabinet_motion.finished
 assert(is_zero_approx(opened_door.rotation.y))
 svc.request("cabinet");svc.request("take_laptop",0)
 assert(svc.state.laptops[0].where=="held")
 var usb: StaticBody3D
 for child in svc.laptop_roots[0].get_children():
  if child.get_meta("role","")=="ac_laptop_usb":usb=child
 assert(is_instance_valid(usb))
 var inset: MeshInstance3D
 for child in usb.get_children():
  if child is MeshInstance3D:inset=child
 assert(is_instance_valid(inset) and inset.position.x>0 and inset.mesh.size.y<.02)
 var lid: Node3D=svc.laptop_roots[0].get_node("Lid")
 assert(is_equal_approx(lid.rotation.x,PI/2.0))
 var top: Vector3=lid.transform*Vector3(0,.26,0)
 assert(top.z>0.0 and absf(top.y-.06)<.001)
 game.hotbar._sync_ac_items()
 assert(game.hotbar.has_item("ac_laptop"))
 svc.request("stow_laptop")
 assert(svc.state.laptops[0].where=="stowed")
 svc.request("equip_laptop",0)
 assert(svc.state.laptops[0].where=="held")
 var bench_point := Vector3(-7.8,.77,-2.5)
 var bench_player := Vector3(bench_point.x,0,bench_point.z+.6)
 game.player.global_position=bench_player
 svc.laptop_roots[0].rotation=Vector3(.5,.4,.3)
 svc.request("place_laptop",-1,bench_point)
 assert(svc.laptop_roots[0].rotation.is_equal_approx(Vector3.ZERO))
 svc.request("open",0)
 assert(svc.state.laptops[0].open)
 game.player.global_position=cabinet_position+Vector3(0,0,-1.4)
 svc.request("take_cable",0)
 game.player.global_position=bench_player
 svc.request("attach_laptop",0)
 # Host verifies the DAQ port rather than the client-supplied coordinate.
 var daq:Vector3=game.session.labs[1].positions.daq
 game.player.global_position=Vector3(daq.x,0,daq.z+.5)
 svc.request("attach_daq",-1,Vector3.ZERO,1)
 assert(svc.state.cables[0].where=="connected")
 var daq_target: Node = game.stations[0].equipment.control_bodies.daq
 assert(svc.hint(daq_target).begins_with("Right-click"))
 assert(svc.interact(daq_target,true) and svc.state.cables[0].where=="partial")
 assert(svc.state.cables[0].station==-1 and svc.state.cables[0].laptop==0)
 assert(svc.interact(daq_target,false) and svc.state.cables[0].where=="connected")
 svc._open_view(0)
 assert("no low power" in svc.subtitle.text)
 var station=game.session.labs[1]
 station.powered=true
 station.cables.append_array([{"id":1,"a":"LOW_0","b":"DAQ_POWER_A","owner":0,"creator":1,"color":0},{"id":2,"a":"P_A","b":"DAQ_E0_P","owner":0,"creator":1,"color":0},{"id":3,"a":"P_N","b":"DAQ_E0_N","owner":0,"creator":1,"color":0}])
 station.readings.daq_v[0]=Vector2(120,0)
 game.session.broadcast();svc._refresh_view()
 assert(svc.plot.connected.size()==1 and svc.plot.connected[0].name=="E1")
 assert("120.000 V" in svc.values.text)
 assert("E1" in svc.legend.text and "cos(" in svc.legend.text)
 assert(is_equal_approx(svc.plot.frequency,60.0))
 assert(absf(svc.plot.sample(svc.plot.connected[0],0.0)-sqrt(2.0)*120.0)<.01)
 svc._set_view("table")
 assert(svc.table_scroll.visible and not svc.plot.visible)
 assert(svc.table_grid.columns==2 and svc.table_grid.get_child_count()==20)
 assert(svc.table_grid.get_child(1).text=="E1 (V)")
 assert(svc.table_grid.get_child(3).text.begins_with("+169.7"))
 svc._set_view("graph")
 var indicator=game.stations[0].equipment.terminal_bodies.DAQ_POWER_A.get_parent().get_node("DaqPowerIndicator")
 assert(indicator.material_override.emission_enabled)
 svc.plot.mode="phasor";svc._refresh_view()
 assert(svc.plot.mode=="phasor" and svc.plot.connected[0].value==Vector2(120,0))
 svc._close_view(true)
 game.player.global_position=bench_player
 svc.request("close",0);svc.request("pickup",0)
 assert(svc.state.laptops[0].where=="held" and svc.cable_views.has(0))
 var cable_mesh: MeshInstance3D=svc.cable_views[0].mesh
 var previous: Vector3=svc.cable_views[0].a
 svc.laptop_roots[0].global_position+=Vector3(.08,0,0)
 svc._update_moving_cables()
 assert(svc.cable_views[0].mesh==cable_mesh and svc.cable_views[0].a.distance_to(previous)>.07)
 svc.request("place_laptop",-1,bench_point)
 assert(game.control_bodies.frequency.get_meta("id")=="frequency")
 assert(game.session.lab.frequency==60.0)
 var pos:Vector3=game.session.lab.positions.frequency
 assert(game.session.lab.act(1,{"op":"frequency","delta":-5},pos).is_empty())
 assert(game.session.lab.frequency==55.0)
 print("PASS laptop scene workflow, DAQ gating, graph channels and frequency control")
 quit()
