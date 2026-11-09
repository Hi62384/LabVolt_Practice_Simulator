extends SceneTree
var fails := 0
func check(ok: bool,label: String):
 print("PASS " if ok else "FAIL ",label)
 if not ok:fails+=1
func _initialize():
 var M=load("res://scripts/stateful_devices.gd");var S=load("res://scripts/electronics_solver.gd").new()
 var nodes=["g","cap","out","v","ctrl","cap","dis","v"];var state={};var result={};var edges=[];var last=false
 for step in 1600:
  state=M.tick("timer555",nodes,result.get("v",{}),state,.0005)
  var parts=M.expand("timer555","timer",nodes,state).filter(func(p):return p.kind!="stateful")
  parts.append_array([{"id":"s","kind":"V","a":"v","b":"g","value":5.},{"id":"ra","kind":"R","a":"v","b":"dis","value":1000.},{"id":"rb","kind":"R","a":"dis","b":"cap","value":10000.},{"id":"c","kind":"C","a":"cap","b":"g","value":.00001}])
  result=S.solve(parts,[],.0005)
  if not result.ok:break
  var high=state.get("q",false)
  if high and not last:edges.append(S.time)
  last=high
 check(result.ok and edges.size()>=4,"555 oscillates from resistor/capacitor charging and discharge")
 if edges.size()>=3:check(abs((edges[2]-edges[1])-.693*21000*.00001)<.006,"555 period matches RC timing within step resolution")
 var f=[]
 for i in 14:f.append(str(i))
 var volt={"13":5.,"6":0.,"0":5.,"3":5.,"12":5.,"9":5.,"1":5.,"2":0.}
 var flip=M.tick("flip74",f,volt,{},.0005);volt["2"]=5.;flip=M.tick("flip74",f,volt,flip,.0005)
 check(flip.a,"D flip-flop captures data on rising edge")
 volt["1"]=0.;flip=M.tick("flip74",f,volt,flip,.0005);check(flip.a,"D flip-flop retains data without a clock edge")
 volt["0"]=0.;flip=M.tick("flip74",f,volt,flip,.0005);check(not flip.a,"asynchronous clear overrides stored data")
 var station=load("res://scripts/dc_station.gd").new();var B=load("res://scripts/breadboard_model.gd");var board=B.empty()
 var code="mode D0 out\nmode D1 out\nmode PWM out\nwrite PWM 0\n"
 for byte in [0,72,73]:
  for bit in range(7,-1,-1):code+="write D1 0\nwrite D0 %d\nwait 1\nwrite D1 1\nwait 1\n"%((byte>>bit)&1)
 code+="write PWM 1\nhalt"
 board.parts=[{"id":"cpu","type":"lv_mcu","a":"A1","b":"A2","pins":["A1","A2","A3","A4","A5","A6"],"firmware":code},{"id":"screen","type":"spi_display","a":"B1","b":"B2","pins":["B1","B2","B3","B4","B6"]},{"id":"sound","type":"buzzer","a":"C1","b":"C2"}];board.ports=["A1","A2","A3","A4"]
 check(station.apply({"op":"board","design":board})=="","wired programmable display board validates")
 station.master=true;station.channels[0].enabled=true;station.wires=[["CH1+","B1"],["CH1-","B2"]]
 for i in 500:station.step(.0005)
 var display=station.firmware_states.get("board/screen",{})
 check(display.get("cells",[]).size()==32 and display.cells[0]==72 and display.cells[1]==73,"firmware sends HI through actual DATA CLK CS connections")
 check(float(station.result.i.get("board/sound",0))>.004,"active buzzer draws actual circuit current")
 station.master=false
 for i in 8:station.step()
 check(not station.firmware_states["board/screen"].powered and abs(float(station.result.i.get("board/sound",0)))<.0001,"screen and buzzer lose power on disconnect")
 print("STATEFUL FAILURES: ",fails);quit(fails)
