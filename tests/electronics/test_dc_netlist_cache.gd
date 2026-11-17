extends SceneTree
const Station=preload("res://scripts/dc_station.gd")
func _initialize() -> void:
 var station=Station.new();station.prune_disconnected_passives=false
 for i in 20:
  station.solver.time=float(i)*.013
  match i:
   2:station.master=true;station.channels[0].enabled=true
   4:station.channels[0].voltage=12.0
   6:station.current_source.enabled=true
   8:station.auxiliary_sources[0].enabled=true
   10:station.resistance[0]=220.0
   12:station.capacitance=.00047
   14:station.fuse=true
   16:station.generator.enabled=true;station.generator.wave="DC";station.generator.offset=3.0
   18:station.generator.wave="Sine"
  var cached: Array=station.netlist_active().duplicate(true)
  var fresh: Array=station.netlist()
  if cached!=fresh:push_error("DC cached netlist differs after edit %d"%i);quit(1);return
 print("PASS: cached DC netlist matches fresh netlist after source, circuit and waveform changes")
 quit()
