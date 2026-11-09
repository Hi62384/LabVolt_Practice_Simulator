extends SceneTree
var failures := 0
func check(ok: bool, message: String) -> void:
 if not ok: failures+=1;push_error(message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
 var game=preload("res://tests/campus/world/shop_fixture.gd").new();root.add_child(game)
 var shop=preload("res://scripts/shop_room.gd").new();root.add_child(shop)
 var campus:=Node3D.new();root.add_child(campus)
 shop.build_campus(game,campus)
 var pages: Array=[]
 for child in shop.get_children():
  if child.get_meta("role","")=="shop_station":
   pages.append(child.get_meta("page"))
   shop.interact(child)
 check(pages.size()==6,"six preserved shop stations")
 check(game.electronics.opened==["shop","kits","ics","inventory","trade"],"all purchase/editor/trading pages dispatch to existing UI")
 check(game.player.position==Vector3(14.5,0,3),"campus return reaches hall without session change")
 var lights := 0
 for child in shop.get_children():
  if child is OmniLight3D: lights+=1
 check(lights==0,"campus shop adds no real-time lights")
 var legacy=preload("res://scripts/shop_room.gd").new();root.add_child(legacy);legacy.build(game)
 check(not legacy.campus_mode,"legacy build API preserved")
 var solids := 0
 for child in legacy.get_children():
  if child is StaticBody3D and child.get_meta("role","")=="": solids+=1
 check(solids==12,"legacy standalone shell and counters")
 print("SHOP_TESTS checks=6 failures=",failures)
 game.queue_free();shop.queue_free();legacy.queue_free();campus.queue_free();await process_frame
 quit(failures)
