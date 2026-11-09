extends SceneTree
func _initialize():call_deferred("run")
func run():
 var game=load("res://scenes/Main.tscn").instantiate();root.add_child(game)
 for i in 4:await process_frame
 var B=load("res://scripts/breadboard_model.gd");var source=B.empty();source.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1"}]
 var bp=B.blueprint(source,"64 indexed pins");bp.package="PCB";bp.footprint={"width":8,"height":8,"color":"24775b","thickness_mm":1.6};bp.layout={"rows":source.rows,"parts":source.parts.duplicate(true),"wires":[]}
 var original=bp.pins[0].node;bp.pins=[]
 for i in 64:bp.pins.append({"name":"Signal %d"%(i+1),"id":"stable_%d"%(i+1),"node":original,"position":{"x":i%8,"y":i/8},"role":"bidirectional","connector":"female_header"})
 var design=B.standalone("ic:64",{"ic:64":bp})
 var lab=game.dc_lab;assert(lab.benches[1].apply({"op":"board","design":design})=="");lab.benches[1].board_owner=1;lab.broadcast()
 for i in 4:await process_frame
 assert(lab.physical_boards[1].drawing.size==Vector2(1000,440))
 assert(lab.physical_boards[1].external_ports.size()==64)
 assert(lab.endpoint_available(1,"X64") and not lab.endpoint_available(1,"X65"))
 assert(lab.benches[1].apply({"op":"wire","a":"X64","b":"CH1+"})=="")
 var labels=lab.physical_boards[1].controls.get_children().filter(func(n):return n.get_meta("role","")=="dc_port" and n.get_meta("dc_port","")=="X64")
 assert(labels.size()==1 and labels[0].get_meta("pin_id","")=="stable_64")
 print("PASS: combined editor/renderer/core supports all 64 named positioned pins and X64 wiring without reordering")
 quit()

