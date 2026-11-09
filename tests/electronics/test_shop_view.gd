extends SceneTree
class Owner:
 extends Node
 var characters={"selected":"shop-view-test"}
func _initialize():call_deferred("run")
func make_ui(owner):
 var ui=load("res://scripts/electronics_ui.gd").new()
 ui.game=owner;ui.profile.open(owner.characters.selected);root.add_child(ui)
 ui.body=VBoxContainer.new();ui.add_child(ui.body);ui.active=true;ui.current_page="shop"
 return ui
func search_input(ui):
 for child in ui.body.get_children():
  if child is LineEdit:return child
 return null
func catalog_rows(ui):
 for child in ui.body.get_children():
  if child is VBoxContainer:return child.get_children()
 return []
func run():
 var owner=Owner.new();root.add_child(owner)
 var first=make_ui(owner);first.shop()
 var search=search_input(first);assert(search!=null)
 search.text="resistor";search.text_changed.emit(search.text)
 var matches=0
 for row in catalog_rows(first):
  assert(row.visible==("resistor" in str(row.get_meta("search"))))
  if row.visible:matches+=1
 assert(matches>0 and matches<catalog_rows(first).size())
 first.remember_view()
 var second=make_ui(owner);second.load_view();assert(second.shop_search=="resistor")
 second.shop();assert(search_input(second).text=="resistor")
 for row in catalog_rows(second):assert(row.visible==("resistor" in str(row.get_meta("search"))))
 owner.characters.selected="shop-view-other-profile";second.load_view();assert(second.shop_search=="")
 owner.characters.selected="shop-view-test"
 var cfg=ConfigFile.new();assert(cfg.load(second.view_path())==OK);cfg.set_value("view","shop_search",12345);assert(cfg.save(second.view_path())==OK)
 second.load_view();assert(second.shop_search=="")
 first.active=false;second.active=false
 first.queue_free();second.queue_free();owner.queue_free();await process_frame
 print("PASS: actual shop filters, reconstruct/reload, profile isolation and invalid saved search")
 quit()
