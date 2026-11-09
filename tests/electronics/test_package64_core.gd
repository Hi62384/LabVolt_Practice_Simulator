extends SceneTree
func _initialize():
 var S=load("res://scripts/dc_station.gd");var station=S.new();var pins=[]
 for i in 64:pins.append("A%d"%(i+1))
 station.board={"standalone":true,"parts":[{"pins":pins}]}
 assert(station.pcb_pin_available("X1") and station.pcb_pin_available("X17") and station.pcb_pin_available("X64"))
 for bad in ["X0","X65","X064","X-1","X1.0","X999999999999"]:assert(not station.pcb_pin_available(bad))
 assert(station.apply({"op":"wire","a":"X64","b":"CH1+"})=="")
 assert(station.wires[0][0]=="X64")
 assert(station.apply({"op":"wire","a":"X65","b":"CH1-"})!="")
 station.board.parts[0].pins=pins.slice(0,63);assert(not station.pcb_pin_available("X64"))
 station.board.parts=[];assert(not station.pcb_pin_available("X1"))
 assert(not S.board_port("Bread") and not S.board_port("X65"))
 print("PASS: X1-X64 canonical acceptance, unchanged index mapping, unavailable pin and malformed bounds rejected")
 quit()
