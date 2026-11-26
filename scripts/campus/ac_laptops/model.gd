extends RefCounted
const COUNT := 6
const CABINET := Vector3(-4.4, 0.0, 9.53)
var cabinet_open := false
var laptops: Array = []
var cables: Array = []
var revision := 0

func _init() -> void:
 reset()
func reset() -> void:
 cabinet_open = false
 laptops.clear(); cables.clear()
 for i in COUNT:
  laptops.append({"where":"cabinet", "owner":0, "position":Vector3.ZERO, "open":false})
  cables.append({"where":"cabinet", "owner":0, "laptop":-1, "station":-1, "position":Vector3.ZERO})
 revision += 1
func snapshot() -> Dictionary:
 return {"cabinet_open":cabinet_open,"laptops":laptops.duplicate(true),"cables":cables.duplicate(true),"revision":revision}
func held_laptop(peer: int) -> int:
 for i in COUNT:
  if laptops[i].where == "held" and laptops[i].owner == peer:return i
 return -1
func held_cable(peer: int) -> int:
 for i in COUNT:
  if cables[i].where in ["held","partial"] and cables[i].owner == peer:return i
 return -1
func attached_to_laptop(id: int) -> int:
 for i in COUNT:
  if cables[i].where in ["partial","connected"] and cables[i].laptop == id:return i
 return -1
static func connected_to_daq(entries: Array, station: int) -> int:
 for i in entries.size():
  if entries[i].where=="connected" and entries[i].station==station:return i
 return -1
func apply(peer: int, position: Vector3, op: String, id: int = -1, point: Vector3 = Vector3.ZERO, station: int = -1, thrown := false) -> String:
 if peer < 1 or not position.is_finite():return "Invalid player position."
 var near_cabinet := position.distance_to(CABINET + Vector3(0,1,0)) < 3.0
 if op == "cabinet":
  if not near_cabinet:return "Move closer to the laptop cabinet."
  cabinet_open = not cabinet_open
 elif op == "take_laptop":
  if id not in range(COUNT) or not cabinet_open or not near_cabinet:return "Open the cabinet and move closer."
  if laptops[id].where != "cabinet" or held_laptop(peer)>=0 or held_cable(peer)>=0:return "Put down the item you are carrying first."
  laptops[id].where="held";laptops[id].owner=peer
 elif op == "store_laptop":
  var item := held_laptop(peer)
  if item<0 or not near_cabinet:return "Carry the laptop to the cabinet."
  laptops[item].where="cabinet";laptops[item].owner=0;laptops[item].open=false
  cabinet_open=false
 elif op == "place_laptop":
  var item := held_laptop(peer)
  if item<0 or not point.is_finite() or (point.distance_to(position)>3.0 and not thrown):return "Choose a nearby surface."
  if not thrown and (point.x < -9.8 or point.x > 9.8 or point.z < -3.8 or point.z > 9.8 or point.y < 0 or point.y > 2.5):return "Place the laptop inside the AC lab."
  laptops[item].where="placed";laptops[item].owner=0;laptops[item].position=point
 elif op in ["open", "close", "pickup"]:
  if id not in range(COUNT) or laptops[id].where!="placed" or position.distance_to(laptops[id].position)>3.0:return "Move closer to the laptop."
  if op=="open":laptops[id].open=true
  elif op=="close":laptops[id].open=false
  else:
   if laptops[id].open:return "Close the laptop before picking it up."
   if held_laptop(peer)>=0 or held_cable(peer)>=0:return "Put down the item you are carrying first."
   laptops[id].where="held";laptops[id].owner=peer
 elif op=="stow_laptop":
  var item:=held_laptop(peer)
  if item<0:return "No laptop is held."
  if attached_to_laptop(item)>=0:return "Disconnect the USB cable before stowing the laptop."
  laptops[item].where="stowed"
 elif op=="equip_laptop":
  if id not in range(COUNT) or laptops[id].where!="stowed" or laptops[id].owner!=peer or held_laptop(peer)>=0 or held_cable(peer)>=0:return "Laptop unavailable."
  laptops[id].where="held"
 elif op=="stow_cable":
  var item:=held_cable(peer)
  if item<0 or cables[item].where!="held":return "Disconnect the USB cable first."
  cables[item].where="stowed"
 elif op=="equip_cable":
  if id not in range(COUNT) or cables[id].where!="stowed" or cables[id].owner!=peer or held_cable(peer)>=0 or held_laptop(peer)>=0:return "USB cable unavailable."
  cables[id].where="held"
 elif op=="take_cable":
  if id not in range(COUNT) or not cabinet_open or not near_cabinet or cables[id].where!="cabinet":return "Take a cable from the open cabinet."
  if held_laptop(peer)>=0 or held_cable(peer)>=0:return "Put down the item you are carrying first."
  cables[id].where="held";cables[id].owner=peer
 elif op=="store_cable":
  var item:=held_cable(peer)
  if item<0 or cables[item].where!="held" or not cabinet_open or not near_cabinet:return "Carry a loose cable to the open cabinet."
  cables[item]={"where":"cabinet","owner":0,"laptop":-1,"station":-1,"position":Vector3.ZERO}
 elif op=="drop_cable":
  var item:=held_cable(peer)
  if item<0 or cables[item].where!="held" or not point.is_finite() or position.distance_to(point)>3.0:return "Choose nearby ground for the USB cable."
  cables[item].where="placed";cables[item].position=point
 elif op=="pickup_cable":
  if id not in range(COUNT) or cables[id].where!="placed" or position.distance_to(cables[id].position)>3.0:return "Move closer to the USB cable."
  if cables[id].owner!=peer:return "This USB cable belongs to another player."
  if held_laptop(peer)>=0 or held_cable(peer)>=0:return "Put down the item you are carrying first."
  cables[id].where="held";cables[id].owner=peer
 elif op=="attach_laptop":
  var cable:=held_cable(peer)
  if cable<0 or cables[cable].where!="held" or id not in range(COUNT) or laptops[id].where!="placed" or position.distance_to(laptops[id].position)>3.0:return "Carry a USB cable to a placed laptop."
  if attached_to_laptop(id)>=0:return "This laptop already has a USB cable."
  cables[cable].where="partial";cables[cable].laptop=id
 elif op=="attach_daq":
  var cable:=held_cable(peer)
  if cable<0 or cables[cable].where!="partial" or station not in range(3):return "Connect the cable to a laptop first."
  if connected_to_daq(cables,station)>=0:return "This DAQ already has a USB cable."
  if not point.is_finite() or position.distance_to(point)>3.0 or point.distance_to(laptops[cables[cable].laptop].position)>5.0:return "Move the laptop closer to the DAQ."
  cables[cable].where="connected";cables[cable].owner=0;cables[cable].station=station
 elif op=="detach_daq":
  var cable:=connected_to_daq(cables,station)
  if cable<0:return "No USB cable connected."
  if held_cable(peer)>=0 or held_laptop(peer)>=0:return "Put down the item you are carrying first."
  if not point.is_finite() or position.distance_to(point)>3.0:return "Move closer to the DAQ."
  cables[cable].where="partial";cables[cable].owner=peer;cables[cable].station=-1
 elif op=="disconnect":
  if id not in range(COUNT) or cables[id].where not in ["connected","partial"]:return "No USB cable connected."
  if cables[id].where=="partial" and cables[id].owner!=peer:return "Another player is holding this USB cable."
  if held_cable(peer) not in [-1,id] or held_laptop(peer)>=0:return "Put down the item you are carrying first."
  if position.distance_to(laptops[cables[id].laptop].position)>3.0:return "Move closer to the laptop."
  cables[id].where="held";cables[id].owner=peer;cables[id].laptop=-1;cables[id].station=-1
 else:return "Unsupported laptop action."
 revision+=1
 return ""
func release(peer: int) -> void:
 for laptop in laptops:
  if laptop.where in ["held","stowed"] and laptop.owner==peer:
   laptop.where="cabinet";laptop.owner=0;laptop.open=false
 for cable in cables:
  if cable.owner==peer:
   cable.where="cabinet";cable.owner=0;cable.laptop=-1;cable.station=-1;cable.position=Vector3.ZERO
 revision+=1
static func daq_powered(station: Dictionary) -> bool:
 if not station.get("powered",false):return false
 for wire in station.get("cables",[]):
  var a:=str(wire.get("a",""));var b:=str(wire.get("b",""))
  if (a in ["LOW_0","LOW_1"] and b in ["DAQ_POWER_A","DAQ_POWER_B"]) or (b in ["LOW_0","LOW_1"] and a in ["DAQ_POWER_A","DAQ_POWER_B"]):return true
 return false
