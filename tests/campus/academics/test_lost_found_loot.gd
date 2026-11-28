extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await physics_frame
 var world=game.discarded_items
 var cable={"wire":true,"dc":false,"station":0,"color":2}
 assert(world.track_ground(1,cable,"Yellow cable").is_empty())
 var legacy_cable: String=Crypto.new().generate_random_bytes(16).hex_encode()
 assert(world._save_entries({legacy_cable:{"parcel":cable,"label":"Yellow cable","ground":true}}))
 var lesson: Dictionary=load("res://scripts/course_generator.gd").generate(0,0,123)
 var paper_id: int=game.school._give(1,lesson,true,false,true)
 var paper: Dictionary=game.school.papers[paper_id]
 game.school.papers.erase(paper_id)
 var token: String=world.track_ground(1,{"paper":paper},"Worksheet")
 assert(world._local_entries().has(token))
 world._leaving()
 assert(not world._local_entries()[token].ground)
 world._import_local(1)
 assert(world.drops.size()==1 and not world._local_entries().has(legacy_cable))
 var id: int=world.drops.keys()[0]
 assert(world.drops[id].owner==1 and world.drops[id].token==token)
 game.player.global_position=world.drops[id].position
 world._pickup(1,id,6)
 assert(not world.drops.has(id))
 assert(not world._local_entries().has(token))
 assert(game.school.held(1)!=0)
 world.drops[2000]={"position":Vector3.ZERO,"expires":1,"label":"Yellow cable","owner":1,"parcel":cable,"token":""}
 world._process(0)
 assert(world.drops.is_empty() and world.queued_entries.is_empty())
 assert(world._visual_kind({"parcel":{"paper":{"calculator":true}}})=="calculator")
 assert(world._visual_kind({"parcel":{"paper":{"notebook":true}}})=="notebook")
 for supply in ["flashlight","pencil_case"]:
  var lost_supply: Dictionary={"position":world._available_table_position(),"expires":0,"label":supply,"parcel":{"paper":{"supply_id":supply}}}
  assert(world._visual_kind(lost_supply)==supply)
  var supply_view: StaticBody3D=world._make_view(1200 if supply=="flashlight" else 1201,lost_supply)
  assert(supply_view.get_child(0).find_children("*","MeshInstance3D",true,false).size()>0)
  assert(supply_view.global_position.y>.5)
  supply_view.queue_free()
 var component={"position":Vector3.ZERO,"expires":0,"label":"Resistor","parcel":{"item":{"kind":"component","type":"r1000"}}}
 var component_view: StaticBody3D=world._make_view(1234,component)
 assert(world._visual_kind(component)=="component:r1000")
 assert(component_view.get_child(0).find_children("*","MeshInstance3D",true,false).size()>=2)
 component_view.queue_free()
 var blueprint: Dictionary=preload("res://tests/remaining/pcb/pcb_tests.gd").fixture()
 var board: Dictionary=preload("res://scripts/breadboard_model.gd").standalone("ic:test",{"ic:test":blueprint})
 assert(not board.is_empty())
 var preview: Dictionary=world.PcbPreview.describe(board)
 assert(preview.outline.size()==4 and preview.routes.size()==3 and preview.pads.size()==6 and preview.devices.size()==2)
 assert(not str(preview).contains("firmware") and not preview.has("definitions"))
 world.drops[99]={"position":Vector3.ZERO,"expires":0,"label":"Circuit board","parcel":{"pcb":board}}
 var published: Dictionary=world._public_drops()[99]
 assert(published.visual=="pcb" and published.pcb_preview==preview and not published.has("parcel"))
 world.drops.erase(99)
 var pcb_view: StaticBody3D=world._make_view(1235,{"position":Vector3.ZERO,"expires":0,"label":"Circuit board","visual":"pcb","pcb_preview":preview})
 assert(pcb_view.get_child(0).has_node("PCB outline"))
 assert(pcb_view.get_child(0).find_children("*","MeshInstance3D",true,false).size()>4)
 pcb_view.queue_free()
 var bad_parent:=Node3D.new()
 assert(not world.PcbPreview.build(game,bad_parent,{"outline":[Vector2(NAN,0),Vector2.ZERO,Vector2.ONE]}))
 bad_parent.free()
 var first: Vector3=world._available_table_position()
 world.drops[100]={"position":first}
 var second: Vector3=world._available_table_position()
 world.drops[101]={"position":second}
 world.drops.erase(100)
 assert(world._available_table_position()==first)
 assert(world._available_table_position()!=second)
 world.drops.clear()
 print("PASS lost-and-found save, return and pickup")
 quit()
