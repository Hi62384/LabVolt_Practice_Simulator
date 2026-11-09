extends SceneTree
const Catalog=preload("res://scripts/electronics_catalog.gd")
const Board=preload("res://scripts/breadboard_model.gd")
func _initialize():
 var entries=Catalog.all();var checks=0
 for id in entries:
  var first=Catalog.simulation_entry(id)
  assert(first==entries[id],id);checks+=1
  first.name="Mutated caller copy";first.pins.append("Mutated pin")
  assert(Catalog.simulation_entry(id)==entries[id],id);checks+=1
 assert(Catalog.simulation_entry("not-a-component").is_empty());checks+=1
 var old=entries.r1000.duplicate(true);entries.r1000.value=9.
 assert(Catalog.simulation_entry("r1000")==old and Catalog.all().r1000==old);checks+=1
 var board=Board.empty();board.parts=[{"id":"r","type":"r1000","a":"A1","b":"F1"}]
 var expanded=Board.expand(board)
 assert(expanded.parts[0].kind=="R" and expanded.parts[0].value==1000.);checks+=1
 print("PASS simulation catalog immutable metadata parity/copy isolation and real resistor expansion: ",checks," checks")
 quit()
