extends SceneTree
const Host=preload("res://scripts/campus/facilities/facility_host.gd")
const Food=preload("res://scripts/campus/facilities/food_visual.gd")
const Sandwich=preload("res://scripts/campus/facilities/sandwich_recipe.gd")
const Room=preload("res://scripts/campus/facilities/facility_room.gd")
var profile=Host.empty_profile()
var clock:=1000
var last_charge:=0
func _initialize():call_deferred("run")
func run():
 var host=Host.new()
 host.authority=func():return true
 host.clock=func():return clock
 host.context=func(_p):return {"identity":"student","position":Vector3.ZERO,"room_id":"test","allowed":true,"grounded":true}
 host.load_profile=func(_i):return profile.duplicate(true)
 host.commit_profile=func(_i,delta,p):profile=p.duplicate(true);last_charge=delta;return true
 for venue in ["tim_hortons","subway"]:
  var columns:=Room.restaurant_menu_columns(host.menu,venue)
  assert(columns.size()==2)
  var board_text: String=columns[0]+"\n"+columns[1]
  for column in columns:
   var lines: PackedStringArray=column.split("\n")
   assert(lines.size()<=(10 if venue=="tim_hortons" else 8))
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
  assert(count>= (12 if venue=="tim_hortons" else 6))
  var room=Room.new();root.add_child(room)
  room.build({"id":venue,"kind":"restaurant","anchor":[0,0,0]},host.menu)
  assert(room.get_node_or_null("Cashier")!=null)
  room.queue_free()
 host.anchors["counter"]={"room_id":"test","position":Vector3.ZERO,"kind":"counter:subway"}
 host.table_surface=func(_point,_peer):return true
 var first:=Sandwich.DEFAULT.duplicate(true)
 first.vegetables=["lettuce","tomato"]
 var second:=Sandwich.DEFAULT.duplicate(true)
 second.merge({"bread":"wheat","size":"foot","protein":"chicken","cheese":"swiss","heated":true,"sauces":["mustard"]},true)
 var invalid:=second.duplicate(true)
 invalid.vegetables=["invalid"]
 clock+=100
 assert(not host.act(1,{"op":"buy","item":"sandwich","station":"counter","sequence":profile.last_sequence+1,"recipe":invalid}).ok)
 invalid=second.duplicate(true)
 invalid.price=0
 clock+=100
 assert(not host.act(1,{"op":"buy","item":"sandwich","station":"counter","sequence":profile.last_sequence+1,"recipe":invalid}).ok)
 for recipe in [first,second]:
  clock+=100
  assert(host.act(1,{"op":"buy","item":"sandwich","station":"counter","sequence":profile.last_sequence+1,"recipe":recipe}).ok)
  assert(last_charge==-Sandwich.price(recipe))
 var ids: Array=profile.orders.keys()
 assert(ids.size()==2 and profile.orders[ids[0]].recipe==first and profile.orders[ids[1]].recipe==second)
 assert(profile.orders[ids[0]].servings==3 and profile.orders[ids[1]].servings==6)
 for op in ["place","pickup","consume"]:
  clock+=800
  var request := {"op":op,"order_id":ids[1],"sequence":profile.last_sequence+1}
  if op=="place":request.position=Vector3.ZERO
  assert(host.act(1,request).ok and profile.orders[ids[1]].recipe==second)
 assert(profile.orders[ids[1]].servings==5)
 assert(Host.valid_profile(profile))
 host.physical_sandwich_orders=true
 host.context=func(peer):return {"identity":"test:"+str(peer),"room_id":"subway","position":Vector3.ZERO,"allowed":true,"grounded":true}
 host.anchors["counter"]={"room_id":"subway","position":Vector3.ZERO,"kind":"counter:subway"}
 for key in ["bread/wheat","size/foot","protein/chicken","cheese/swiss","toast/yes","vegetables/lettuce","sauces/mustard"]:
  host.sandwich_targets[key]=Vector3.ZERO
 clock+=100
 assert(not host.act(1,{"op":"buy","item":"sandwich","station":"counter","sequence":profile.last_sequence+1,"recipe":second}).ok)
 assert(host.sandwich_action(1,"counter","begin").ok)
 assert(not host.sandwich_action(2,"counter","begin").ok)
 assert(not host.sandwich_action(2,"counter","bread/wheat").ok)
 assert(not host.sandwich_action(1,"counter","toast/yes").ok)
 for key in ["bread/wheat","size/foot","protein/chicken","cheese/swiss","advance/next","toast/yes"]:
  assert(host.sandwich_action(1,"counter",key).ok)
 assert(host.sandwich_counter.snapshot(clock).oven_ms==10800)
 clock+=10799
 host.tick()
 assert(host.sandwich_counter.step==3)
 assert(not host.sandwich_action(1,"counter","vegetables/lettuce").ok)
 assert(not host.act(1,{"op":"sandwich_checkout","sequence":profile.last_sequence+1}).ok)
 clock+=100
 host.tick()
 for key in ["vegetables/lettuce","advance/next","sauces/mustard","advance/next"]:
  assert(host.sandwich_action(1,"counter",key).ok)
 clock+=100
 assert(host.act(1,{"op":"sandwich_checkout","sequence":profile.last_sequence+1}).ok)
 assert(last_charge==-Sandwich.price(second))
 assert(profile.orders.values().back().recipe.vegetables==["lettuce"])
 assert(host.sandwich_counter.owner==0)
 assert(host.sandwich_action(2,"counter","begin").ok)
 assert(host.sandwich_action(2,"counter","cancel").ok)
 assert(host.sandwich_counter.owner==0)
 print("CUSTOM_SUBWAY_HOST PASS")
 print("PASS expanded restaurant purchases, assets, models and cashiers")
 quit()
