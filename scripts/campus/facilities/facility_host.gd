extends RefCounted
## Server-only deterministic facility rules. Transport authenticates peer; adapters own saves.
signal public_event(room_id: String, peer: int, state: Dictionary)
const EXERCISES := {"pushup":1400,"pullup":1800,"benchpress":1800,"squat":1600,"curl":1400}
const WEIGHTS := {"pushup":[0],"pullup":[0],"benchpress":[10,20,40],"squat":[10,20,40],"curl":[5,10,20]}
const EMOTES := {"wave":1800,"cheer":2200,"flex":2200,"victory":2600}
var menu := {
	"coffee":{"venue":"tim_hortons","name":"Coffee","price":3,"servings":3,"kind":"drink"},
	"tea":{"venue":"tim_hortons","name":"Tea","price":2,"servings":3,"kind":"drink"},
	"donut":{"venue":"tim_hortons","name":"Donut","price":2,"servings":2,"kind":"food"},
	"sandwich":{"venue":"subway","name":"Vegetable sub","price":7,"servings":4,"kind":"food"},
	"chicken_sub":{"venue":"subway","name":"Chicken sub","price":9,"servings":4,"kind":"food"},
	"water":{"venue":"subway","name":"Water","price":2,"servings":3,"kind":"drink"}
}
var context := Callable()
var load_profile := Callable()
var commit_profile := Callable()
var clock := Callable()
var authority := Callable()
var table_surface := Callable()
var floor_surface := Callable()
var anchors := {}
var active := {}
var seats := {}
var last_request := {}
var last_bite := {}

static func empty_profile() -> Dictionary:
	return {"version":1,"revision":0,"xp":0,"records":{},"unlocks":["wave"],"held":{},"last_sequence":0}

static func valid_profile(p: Variant) -> bool:
	if not p is Dictionary or p.get("version",0)!=1:return false
	for key in p:
		if not key in ["version","revision","xp","records","unlocks","held","last_sequence","orders"]:return false
	for key in ["revision","xp","last_sequence"]:
		var n: Variant=p.get(key,-1)
		if not (n is int or n is float) or not is_finite(float(n)) or n<0 or n>1000000000 or n!=floor(float(n)):return false
	if not p.get("records") is Dictionary or not p.get("unlocks") is Array or not p.get("held") is Dictionary:return false
	if p.records.size()>5 or p.unlocks.size()>4:return false
	for key in p.records:
		if not EXERCISES.has(key) or not p.records[key] is Dictionary:return false
		if p.records[key].size()!=1:return false
		var n: Variant=p.records[key].get("reps",-1)
		if not (n is int or n is float) or not is_finite(float(n)) or n<0 or n>30 or n!=floor(float(n)):return false
	for key in p.unlocks:
		if not EMOTES.has(key):return false
	if not p.held.is_empty() and not valid_order(p.held):return false
	var orders: Variant=p.get("orders",{})
	if not orders is Dictionary or orders.size()>24:return false
	for id in orders:
		if not id is String or not id.is_valid_int() or not valid_order(orders[id]):return false
	return true

static func valid_order(order: Variant) -> bool:
	if not order is Dictionary or not order.get("station") is String:return false
	if order.station=="table":
		if order.size()!=5 or not order.get("room") is String:return false
		var coords: Variant=order.get("position")
		if not coords is Array or coords.size()!=3:return false
		for coord in coords:
			if not (coord is float or coord is int) or not is_finite(float(coord)):return false
	elif order.size()!=3:return false
	if not order.get("item","") in ["coffee","tea","donut","sandwich","chicken_sub","water"]:return false
	var n: Variant=order.get("servings",0)
	return (n is int or n is float) and is_finite(float(n)) and n>=1 and n<=4 and n==floor(float(n))

static func carried_order_count(orders: Dictionary) -> int:
	var count := 0
	for order in orders.values():
		if order.station=="":count+=1
	return count

func now() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()

func trusted(peer: int) -> Dictionary:
	if not authority.is_valid() or not bool(authority.call()) or not context.is_valid():return {}
	var c: Variant=context.call(peer)
	if not c is Dictionary or str(c.get("identity","")).is_empty():return {}
	if not c.get("position") is Vector3 or not c.position.is_finite():return {}
	return c

func profile(c: Dictionary) -> Dictionary:
	if not load_profile.is_valid():return {}
	var p: Variant=load_profile.call(str(c.identity))
	if not valid_profile(p):return {}
	var value: Dictionary=p.duplicate(true)
	if not value.has("orders"):
		value.orders={}
		if not value.held.is_empty():value.orders["0"]=value.held
	value.held={}
	return value

func reachable(c: Dictionary, id: String) -> bool:
	if not anchors.has(id):return false
	var a: Dictionary=anchors[id]
	return a.get("position") is Vector3 and a.position.is_finite() and str(a.get("room_id",""))==str(c.get("room_id","")) and c.position.distance_to(a.position)<=2.5

func private_state(peer: int) -> Dictionary:
	var c:=trusted(peer)
	if c.is_empty():return {}
	var p:=profile(c)
	if p.is_empty():return {}
	return {"profile":p,"level":1+int(p.xp)/100,"active":active.get(peer,{}).duplicate(true),"menu":menu.duplicate(true)}

func fail(message: String) -> Dictionary:return {"ok":false,"error":message}

func act(peer: int, request: Dictionary) -> Dictionary:
	var c:=trusted(peer)
	if c.is_empty() or not commit_profile.is_valid():return fail("Facilities unavailable")
	if request.size()>5 or var_to_bytes(request).size()>1024:return fail("Invalid request")
	var seq: Variant=request.get("sequence",null)
	if not seq is int or seq<1 or seq>1000000000:return fail("Invalid sequence")
	var t:=now()
	if t-int(last_request.get(peer,-1000))<80:return fail("Please wait")
	last_request[peer]=t
	var p:=profile(c)
	if p.is_empty():return fail("Profile unavailable")
	if seq!=int(p.last_sequence)+1:return fail("Refresh facility state before retrying")
	var op:=str(request.get("op",""))
	var current: Dictionary=active.get(peer,{})
	# Cancellation remains available when class restrictions change.
	if op in ["cancel","stand","stop"]:
		clear_activity(peer)
		return {"ok":true,"state":private_state(peer)}
	if not bool(c.get("allowed",false)) or not bool(c.get("grounded",false)):
		clear_activity(peer)
		return fail("Activity unavailable during class or while moving")
	# Enforce exercise expiry at request time too; tick may not have run yet.
	if current.get("type","")=="exercise" and (not activity_valid(c,current) or t-int(current.last_beat)>3000):
		clear_activity(peer)
		return fail("Exercise interrupted; start a new set")
	var next:=p.duplicate(true)
	var dollars:=0
	var station:=str(request.get("station",""))
	var next_active:=current.duplicate(true)
	var event: Dictionary={}
	if op=="buy":
		if not current.is_empty():return fail("Finish the current activity first")
		if p.orders.size()>=24 or carried_order_count(p.orders)>=6:return fail("No room for another order")
		var item:=str(request.get("item",""))
		if not menu.has(item) or not reachable(c,station):return fail("Approach the ordering counter")
		var entry: Dictionary=menu[item]
		if anchors[station].get("kind","")!="counter:"+str(entry.venue):return fail("Wrong restaurant")
		if not entry.price is int or int(entry.price)<0 or int(entry.price)>10000:return fail("Invalid host price")
		dollars=-int(entry.price)
		var order := {"item":item,"servings":int(entry.servings),"station":""}
		next.orders[str(seq)]=order
		event={"activity":"holding","order_id":str(seq),"held":order.duplicate(true)}
	elif op in ["consume","place","pickup"]:
		var order_id := str(request.get("order_id",""))
		if order_id.is_empty() and p.orders.size()==1:order_id=str(p.orders.keys()[0])
		var order: Dictionary=next.orders.get(order_id,{})
		if order.is_empty() or (not current.is_empty() and current.get("type","")!="seat"):return fail("No available food or drink")
		var placed:=str(order.station)
		if op=="place":
			var point: Variant=request.get("position")
			if placed!="":return fail("Pick up your order first")
			if request.get("ground",false):
				point=floor_surface.call(point,peer) if floor_surface.is_valid() else null
				if not point is Vector3:return fail("Choose a clear spot on the floor")
			elif not point is Vector3 or not point.is_finite() or point.distance_to(c.position)>3.6 or not table_surface.is_valid() or not table_surface.call(point,peer):
				return fail("Aim at a nearby tabletop")
			order.station="table"
			order.position=[point.x,point.y,point.z]
			order.room=str(c.room_id)
		elif op=="pickup":
			if carried_order_count(p.orders)>=6:return fail("No room for another order")
			if placed=="table":
				var coords: Array=order.position
				var point := Vector3(coords[0],coords[1],coords[2])
				if str(c.room_id)!=str(order.room) or point.distance_to(c.position)>3.6:return fail("Approach your order")
				order.erase("position")
				order.erase("room")
			elif placed=="" or not reachable(c,placed):return fail("Approach your table")
			order.station=""
		else:
			if placed!="":return fail("Pick up your order first")
			if t-int(last_bite.get(c.identity,-1000))<700:return fail("Finish the current bite")
			order.servings-=1
			if order.servings<=0:
				next.orders.erase(order_id)
				order={}
		event={"activity":op,"order_id":order_id,"held":order.duplicate(true)}
	elif op=="sit":
		if not current.is_empty() or not reachable(c,station) or anchors[station].get("kind","")!="seat" or seats.has(station):return fail("Seat unavailable")
		next_active={"type":"seat","station":station,"position":c.position,"room_id":c.room_id}
		event={"activity":"seat","station":station}
		if anchors[station].has("seat_position"):
			event.seat_position=anchors[station].seat_position
			event.seat_yaw=anchors[station].seat_yaw
	elif op=="start":
		if not current.is_empty() or carried_order_count(p.orders)>0 or not reachable(c,station):return fail("Equipment unavailable")
		var exercise:=str(anchors[station].get("kind",""))
		if not EXERCISES.has(exercise) or seats.has(station):return fail("Equipment occupied")
		var weight: Variant=request.get("weight",WEIGHTS[exercise][0])
		if not weight is int or not weight in WEIGHTS[exercise]:return fail("Unsupported exercise weight")
		next_active={"type":"exercise","exercise":exercise,"station":station,"position":c.position,"room_id":c.room_id,"started":t,"last_beat":t,"phase":0,"reps":0,"weight":weight}
		event={"activity":"exercise","exercise":exercise,"phase":0,"reps":0,"weight":weight,"station":station}
	elif op=="beat":
		if current.get("type","")!="exercise" or not activity_valid(c,current):return fail("Start an exercise first")
		var gap:=t-int(current.last_beat)
		var half:=int(EXERCISES[current.exercise])/2
		if gap<half-150:return fail("Too early; follow the rhythm")
		if gap>half+700:
			clear_activity(peer)
			return fail("Rhythm missed; start a new set")
		if int(current.reps)>=30:return fail("Set complete; finish to save")
		next_active.last_beat=t
		next_active.phase=1-int(current.phase)
		if int(next_active.phase)==0:next_active.reps+=1
		event={"activity":"exercise","exercise":current.exercise,"phase":next_active.phase,"reps":next_active.reps,"weight":current.weight,"station":current.station}
	elif op=="finish":
		if current.get("type","")!="exercise" or not activity_valid(c,current) or int(current.reps)<1:return fail("Complete a repetition first")
		var reps:=int(current.reps)
		if t-int(current.started)<reps*(int(EXERCISES[current.exercise])-300):return fail("Invalid exercise timing")
		next.xp=mini(1000000000,int(p.xp)+reps*(5+int(current.get("weight",0))/20))
		var old: Dictionary=p.records.get(current.exercise,{"reps":0})
		if reps>int(old.reps):next.records[current.exercise]={"reps":reps}
		for unlock in [[100,"cheer"],[300,"flex"],[600,"victory"]]:
			if int(next.xp)>=int(unlock[0]) and not unlock[1] in next.unlocks:next.unlocks.append(unlock[1])
		next_active={}
		event={"activity":"idle"}
	elif op=="emote":
		var emote:=str(request.get("emote",""))
		if not current.is_empty() or not emote in p.unlocks or not EMOTES.has(emote):return fail("Emote unavailable")
		next_active={"type":"emote","emote":emote,"position":c.position,"room_id":c.room_id,"until":t+int(EMOTES[emote])}
		event={"activity":"emote","emote":emote,"duration_ms":int(EMOTES[emote])}
	else:return fail("Unknown facility action")
	next.last_sequence=seq
	next.revision=int(p.revision)+1
	if not valid_profile(next) or not bool(commit_profile.call(str(c.identity),dollars,next.duplicate(true))):return fail("Purchase or save failed; nothing changed")
	if op=="consume":last_bite[c.identity]=t
	if current.has("station"):seats.erase(current.station)
	if next_active.is_empty():active.erase(peer)
	else:
		active[peer]=next_active
		if next_active.has("station"):seats[next_active.station]=peer
	public_event.emit(str(c.room_id),peer,event)
	return {"ok":true,"state":private_state(peer)}

func activity_valid(c: Dictionary, a: Dictionary) -> bool:
	return str(c.get("room_id",""))==str(a.get("room_id","")) and c.position.distance_to(a.position)<0.35 and bool(c.get("allowed",false)) and bool(c.get("grounded",false))

func clear_activity(peer: int) -> void:
	if not active.has(peer):return
	var a: Dictionary=active[peer]
	if a.has("station"):seats.erase(a.station)
	active.erase(peer)
	public_event.emit(str(a.get("room_id","")),peer,{"activity":"idle"})

func tick() -> void:
	for peer in active.keys():
		var c:=trusted(int(peer))
		var a: Dictionary=active[peer]
		if c.is_empty() or not activity_valid(c,a) or (a.get("type","")=="emote" and now()>=int(a.until)) or (a.get("type","")=="exercise" and now()-int(a.last_beat)>3000):clear_activity(int(peer))

func movement_locked(peer: int) -> bool:return active.has(peer)

func public_profile(peer: int, share_gym: bool=false) -> Dictionary:
	if not share_gym:return {}
	var s:=private_state(peer)
	if s.is_empty():return {}
	return {"gym_level":s.level,"gym_records":s.profile.records.duplicate(true),"emotes":s.profile.unlocks.duplicate()}
