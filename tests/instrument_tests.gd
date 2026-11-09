extends SceneTree
var failures := 0
func check(ok: bool,message: String):
 if not ok: failures+=1;printerr("FAIL INSTRUMENT: "+message)
func _initialize():call_deferred("run")
func run():
 var builder=preload("res://scripts/equipment_builder.gd").new()
 root.add_child(builder)
 builder._reset_switches()
 builder._build_station()
 var solver=preload("res://scripts/circuit_solver.gd").new()
 var switches={"R":[false,false,true,false,false,false,false,false,false],"L":[false,false,false,false,false,false,false,false,false],"C":[false,false,false,false,false,false,false,false,false]}
 var leads=[{"a":"P_A","b":"DAQ_I0_4"},{"a":"DAQ_I0_N","b":"R0_P"},{"a":"R0_N","b":"P_N"},{"a":"DAQ_E0_P","b":"R0_P"},{"a":"DAQ_E0_N","b":"P_N"}]
 var result: Dictionary=solver.solve(builder.terminal_ids,leads,switches,true,1)
 check(result.fault=="","DAQ circuit solves")
 check(absf(result.daq_v[0].length()-120)<.01,"DAQ measures 120 V across resistor")
 check(absf(result.daq_i[0].length()-.4)<.001,"DAQ measures series current")
 leads=[{"a":"P_A","b":"TX_1"},{"a":"P_N","b":"TX_2"},{"a":"TX_5","b":"R0_P"},{"a":"TX_6","b":"R0_N"}]
 result=solver.solve(builder.terminal_ids,leads,switches,true,1)
 check(result.fault=="","loaded transformer solves")
 check(absf((result.voltages.TX_3-result.voltages.TX_4).length()-208)<.02,"208 V series secondary")
 check(absf((result.voltages.TX_5-result.voltages.TX_9).length()-60)<.01,"60 V center tap")
 check(absf(result.bank_currents.R0-.4)<.001,"transformer supplies load current")
 check(absf(result.source_currents.P_A-.412)<.002,"transformer reflects load and magnetizing current")
 var load_catalog: Dictionary=preload("res://scripts/equipment_catalog.gd").LOADS
 for kind in ["R","L","C"]:
  for bank in 3:
   var positive := "%s%d_P"%[kind,bank]
   var negative := "%s%d_N"%[kind,bank]
   var bank_id := "%s%d"%[kind,bank]
   for setting in 3:
    for group in switches.values():group.fill(false)
    switches[kind][bank*3+setting]=true
    var value: float=load_catalog[kind].values[setting]
    var impedance := value
    if kind=="L":impedance=TAU*60.0*value
    elif kind=="C":impedance=1.0/(TAU*60.0*value)
    result=solver.solve(builder.terminal_ids,[{"a":"P_A","b":positive},{"a":negative,"b":"P_N"}],switches,true,1)
    check(result.fault=="" and absf(result.bank_currents.get(bank_id,0.0)-120.0/impedance)<.002,"load bank %s switch %d"%[bank_id,setting+1])
 for channel in 4:
  switches.R.fill(false)
  switches.R[2]=true
  for tap in ["4","40"]:
   leads=[{"a":"P_A","b":"DAQ_I%d_%s"%[channel,tap]},{"a":"DAQ_I%d_N"%channel,"b":"R0_P"},{"a":"R0_N","b":"P_N"},{"a":"DAQ_E%d_P"%channel,"b":"R0_P"},{"a":"DAQ_E%d_N"%channel,"b":"P_N"}]
   result=solver.solve(builder.terminal_ids,leads,switches,true,1)
   check(result.fault=="" and absf(result.daq_v[channel].length()-120.0)<.02 and absf(result.daq_i[channel].length()-.4)<.002,"DAQ channel %d current tap %s"%[channel+1,tap])
 for channel in 3:
  for tap in ["150","300"]:
   leads=[{"a":"P_A","b":"V%d_%s"%[channel,tap]},{"a":"P_N","b":"V%d_COM"%channel}]
   result=solver.solve(builder.terminal_ids,leads,switches,true,1)
   var expected_range := 100.0 if tap=="150" else 250.0
   check(result.fault=="" and absf(result.voltmeters[channel]-120.0)<.01 and result.voltmeter_ranges[channel]==expected_range,"voltmeter %d range %.0f"%[channel+1,expected_range])
  for tap in ["IN","2_5","8","25"]:
   var terminal := "AM%d_%s"%[channel,tap]
   if not builder.terminal_bodies.has(terminal):continue
   leads=[{"a":"P_A","b":terminal},{"a":"AM%d_OUT"%channel,"b":"R0_P"},{"a":"R0_N","b":"P_N"}]
   result=solver.solve(builder.terminal_ids,leads,switches,true,1)
   var expected_range: float={"IN":.5,"2_5":2.5,"8":8.0,"25":25.0}[tap]
   check(result.fault=="" and absf(result.ammeters[channel]-.4)<.002 and result.ammeter_ranges[channel]==expected_range,"ammeter %d range %.1f"%[channel+1,expected_range])
 for channel in 2:
  leads=[{"a":"P_A","b":"W%d_IN"%channel},{"a":"W%d_OUT"%channel,"b":"R0_P"},{"a":"R0_N","b":"P_N"},{"a":"W%d_VN"%channel,"b":"P_N"}]
  result=solver.solve(builder.terminal_ids,leads,switches,true,1)
  check(result.fault=="" and absf(result.wattmeters[channel]-48.0)<.02,"wattmeter %d reads resistive load"%[channel+1])
 for id in ["TX_9","DAQ_I3_40","IGBT_5"]:check(builder.terminal_bodies.has(id),"physical port "+id)
 var wattmeter: Node3D=builder.terminal_bodies.W0_IN.get_parent()
 var numbers := {}
 var caption_row := INF
 for child in wattmeter.get_children():
  if not child is Label3D:continue
  if child.get_meta("terminal_legend",false):numbers[child.text]=child
  elif child.text=="Three-Phase Wattmeter":caption_row=child.position.y
 check(numbers.size()==6,"wattmeter has six terminal numbers")
 for number in ["1","2","3","4","5","6"]:
  var legend: Label3D=numbers.get(number)
  check(legend!=null and legend.modulate==builder.TEXT_LIGHT and legend.pixel_size*legend.font_size>=.04 and absf(legend.position.y-caption_row)>.15,"readable wattmeter terminal "+number)
 print("INSTRUMENTS: %d failures"%failures)
 builder.queue_free()
 await process_frame
 quit(1 if failures else 0)
