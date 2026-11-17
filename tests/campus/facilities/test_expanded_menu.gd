extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
const Food=preload("res://scripts/campus/facilities/food_visual.gd")
const Room=preload("res://scripts/campus/facilities/facility_room.gd")
var profile=Host.empty_profile()
var clock:=1000
func _initialize():call_deferred("run")
func run():
 var host=Host.new()
 host.authority=func():return true
 host.clock=func():return clock
 host.context=func(_p):return {"identity":"student","position":Vector3.ZERO,"room_id":"test","allowed":true,"grounded":true}
 host.load_profile=func(_i):return profile.duplicate(true)
 host.commit_profile=func(_i,_d,p):profile=p.duplicate(true);return true
 for venue in ["tim_hortons","subway"]:
  var columns:=Room.restaurant_menu_columns(host.menu,venue)
  assert(columns.size()==2)
  var board_text: String=columns[0]+"\n"+columns[1]
  for column in columns:
   var lines: PackedStringArray=column.split("\n")
   assert(lines.size()<=8)
   for line in lines:assert(line.length()<=25)
  for board_id in Host.MENU:
   var board_item: Dictionary=Host.MENU[board_id]
   assert(board_text.count(str(board_item.name)+"  $")== (1 if board_item.venue==venue else 0))
  host.anchors["counter"]={"room_id":"test","position":Vector3.ZERO,"kind":"counter:"+venue}
  var count:=0
  for id in Host.MENU:
   var item: Dictionary=Host.MENU[id]
   if item.venue!=venue:continue
   assert(ResourceLoader.exists("res://assets/ui/food_menu/%s.svg" % item.art))
   var model=Food.build(id,item.servings)
   assert(model.get_child_count()>0)
   model.free()
   clock+=100
   var result=host.act(1,{"op":"buy","item":id,"station":"counter","sequence":profile.last_sequence+1})
   assert(result.ok)
   assert(Host.valid_profile(profile))
   count+=1
   profile.orders.clear()
  assert(count>=6)
  var room=Room.new();root.add_child(room)
  room.build({"id":venue,"kind":"restaurant","anchor":[0,0,0]},host.menu)
  assert(room.get_node_or_null("Cashier")!=null)
  room.queue_free()
 print("PASS expanded restaurant purchases, assets, models and cashiers")
 quit()
