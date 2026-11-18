extends RefCounted
## Server-only deterministic facility rules. Transport authenticates peer; adapters own saves.
signal public_event(room_id: String, peer: int, state: Dictionary)
const EXERCISES := {"pushup":1400,"pullup":1800,"benchpress":1800,"squat":1600,"curl":1400,"crunch":1600,"leg_raise":1800,"pike_pushup":1800,"hanging_leg_raise":2000,"dip":1800,"deadlift":2100,"romanian_deadlift":2000,"front_raise":1700,"upright_row":1700,"wrist_curl":1400,"overhead_extension":1800,"bent_over_row":1800,"shrug":1400,"lateral_raise":1700,"reverse_fly":1800,"calf_raise":1500,"overhead_press":1800,"good_morning":1800,"incline_press":1800,"chest_supported_row":1800,"chest_fly":1800,"cable_fly":1800,"cable_reverse_fly":1800,"cable_press":1800,"lat_pulldown":1800,"cable_row":1800,"tricep_pushdown":1600,"cable_crunch":1800}
const DUMBBELL_EXERCISES := ["squat","deadlift","romanian_deadlift","curl","front_raise","upright_row","wrist_curl","overhead_extension","bent_over_row","shrug","lateral_raise","reverse_fly","calf_raise"]
const BENCH_DUMBBELL_EXERCISES := ["overhead_press","front_raise","curl","wrist_curl","overhead_extension","good_morning","incline_press","benchpress","lateral_raise","chest_supported_row","reverse_fly","chest_fly"]
const BENCH_BARBELL_EXERCISES := ["overhead_press","front_raise","curl","wrist_curl","overhead_extension","good_morning","incline_press","benchpress","chest_supported_row"]
const BARBELL_EXERCISES := ["squat","deadlift","romanian_deadlift","curl","front_raise","upright_row","overhead_extension","bent_over_row","shrug","wrist_curl","calf_raise"]
const CABLE_EXERCISES := ["cable_fly","cable_reverse_fly","cable_press","lat_pulldown","cable_row","lateral_raise","front_raise","overhead_press","curl","tricep_pushdown","overhead_extension","cable_crunch"]
const STATION_EXERCISES := {"pushup":["pushup","crunch","leg_raise","pike_pushup"],"pullup":["pullup","hanging_leg_raise","dip"],"benchpress":BENCH_BARBELL_EXERCISES,"squat":["squat"],"curl":DUMBBELL_EXERCISES,"barbell":BARBELL_EXERCISES,"cable":CABLE_EXERCISES}
const WEIGHTS := {"pushup":[0],"pullup":[0],"benchpress":[10,20,40],"squat":[10,20,40],"curl":[5,10,20],"crunch":[0],"leg_raise":[0],"pike_pushup":[0],"hanging_leg_raise":[0],"dip":[0]}
const GymProgress = preload("res://scripts/campus/facilities/gym_progress.gd")
const EMOTES := {"wave":1800,"cheer":2200,"flex":2200,"victory":2600}
const MENU := {
 "coffee":{"venue":"tim_hortons","name":"Coffee","price":3,"servings":3,"kind":"drink","category":"Hot drinks","art":"coffee"},
 "tea":{"venue":"tim_hortons","name":"Tea","price":2,"servings":3,"kind":"drink","category":"Hot drinks","art":"tea"},
 "latte":{"venue":"tim_hortons","name":"Latte","price":4,"servings":3,"kind":"drink","category":"Hot drinks","art":"coffee"},
 "hot_chocolate":{"venue":"tim_hortons","name":"Hot chocolate","price":4,"servings":3,"kind":"drink","category":"Hot drinks","art":"coffee"},
 "iced_coffee":{"venue":"tim_hortons","name":"Iced coffee","price":4,"servings":3,"kind":"drink","category":"Cold drinks","art":"coffee"},
 "donut":{"venue":"tim_hortons","name":"Donut","price":2,"servings":2,"kind":"food","category":"Bakery","art":"donut"},
 "chocolate_donut":{"venue":"tim_hortons","name":"Chocolate donut","price":3,"servings":2,"kind":"food","category":"Bakery","art":"donut"},
 "bagel":{"venue":"tim_hortons","name":"Toasted bagel","price":3,"servings":2,"kind":"food","category":"Bakery","art":"donut"},
 "sandwich":{"venue":"subway","name":"Vegetable sub","price":7,"servings":4,"kind":"food","category":"Subs","art":"sandwich"},
 "chicken_sub":{"venue":"subway","name":"Chicken sub","price":9,"servings":4,"kind":"food","category":"Subs","art":"chicken_sub"},
 "turkey_sub":{"venue":"subway","name":"Turkey sub","price":9,"servings":4,"kind":"food","category":"Subs","art":"chicken_sub"},
 "cheese_sub":{"venue":"subway","name":"Cheese sub","price":7,"servings":4,"kind":"food","category":"Subs","art":"sandwich"},
 "water":{"venue":"subway","name":"Water","price":2,"servings":3,"kind":"drink","category":"Drinks","art":"water"},
 "soft_drink":{"venue":"subway","name":"Soft drink","price":3,"servings":3,"kind":"drink","category":"Drinks","art":"water"},
 "cookie":{"venue":"subway","name":"Cookie","price":2,"servings":2,"kind":"food","category":"Sides","art":"donut"}
}
var menu := MENU.duplicate(true)
var context := Callable()
var load_profile := Callable()
var commit_profile := Callable()
var clock := Callable()
var authority := Callable()
var table_surface := Callable()
var floor_surface := Callable()
var dumbbell_mass := Callable()
var barbell_mass := Callable()
var held_barbell_mass := Callable()
var worn_belt_mass := Callable()
var player_body_mass := Callable()
var anchors := {}
signal live_lift_result(peer: int, result: Dictionary)
var live_lifts := false
var cable_weights := {}
var active := {}
var seats := {}
var last_request := {}
var last_bite := {}
var gym_recovery_clock := {}
var last_assist := {}
var pending_sets := {}

static func empty_profile() -> Dictionary:
	return {"version":1,"revision":0,"xp":0,"records":{},"unlocks":["wave"],"held":{},"last_sequence":0}

static func valid_profile(p: Variant) -> bool:
	if not p is Dictionary or p.get("version",0)!=1:return false
	for key in p:
		if not key in ["version","revision","xp","records","unlocks","held","last_sequence","orders","gym"]:return false
	for key in ["revision","xp","last_sequence"]:
		var n: Variant=p.get(key,-1)
		if not (n is int or n is float) or not is_finite(float(n)) or n<0 or n>1000000000 or n!=floor(float(n)):return false
	if not p.get("records") is Dictionary or not p.get("unlocks") is Array or not p.get("held") is Dictionary:return false
	if p.has("gym") and not GymProgress.valid(p.gym):return false
	if p.records.size()>EXERCISES.size() or p.unlocks.size()>4:return false
	for key in p.records:
		if not EXERCISES.has(key) or not p.records[key] is Dictionary:return false
		if p.records[key].size()!=1:return false
		var n: Variant=p.records[key].get("reps",-1)
		if not (n is int or n is float) or not is_finite(float(n)) or n<0 or n>500 or n!=floor(float(n)):return false
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
	if not MENU.has(order.get("item","")):return false
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
	# Present host-timed recovery even between actions. profile() returns a copy;
	# the next committed action advances the saved state from the same timestamp.
	if p.has("gym") and gym_recovery_clock.has(c.identity):
		GymProgress.advance(p.gym,maxf(0.0,float(now()-int(gym_recovery_clock[c.identity]))/1000.0))
	return {"profile":p,"level":1+int(p.xp)/100,"active":active.get(peer,{}).duplicate(true),"menu":menu.duplicate(true),"pending_workouts":pending_sets.get(str(c.identity),[]).size()}

func commit_recovery(peer: int) -> bool:
	var c:=trusted(peer)
	if c.is_empty() or not commit_profile.is_valid():return false
	if not _flush_pending(str(c.identity)):return false
	var t:=now()
	if not gym_recovery_clock.has(c.identity):
		gym_recovery_clock[c.identity]=t
		return true
	var elapsed:=maxf(0.0,float(t-int(gym_recovery_clock[c.identity]))/1000.0)
	if elapsed<60.0:return true
	var p:=profile(c)
	if p.is_empty():return false
	if not p.has("gym") or p.gym.muscles.is_empty():
		gym_recovery_clock[c.identity]=t
		return true
	var next:=p.duplicate(true)
	GymProgress.advance(next.gym,elapsed)
	if next.gym==p.gym:
		gym_recovery_clock[c.identity]=t
		return true
	next.last_sequence=int(p.last_sequence)+1
	next.revision=int(p.revision)+1
	if not valid_profile(next) or not bool(commit_profile.call(str(c.identity),0,next)):return false
	gym_recovery_clock[c.identity]=t
	return true

func set_cable_weight(peer: int, station: String, weight: int) -> Dictionary:
	var c := trusted(peer)
	if c.is_empty() or not bool(c.get("allowed",false)) or active.has(peer) or not reachable(c,station) or anchors[station].get("kind") != "cable":
		return fail("Move within reach of the cable stack.")
	if seats.has(station):
		return fail("Wait until this cable machine is free.")
	if weight < 5 or weight > 100 or weight % 5 != 0:
		return fail("Select a marked weight from 5 to 100 kg.")
	cable_weights[station] = weight
	return {"ok":true}

func fail(message: String) -> Dictionary:return {"ok":false,"error":message}

func act(peer: int, request: Dictionary) -> Dictionary:
	var c:=trusted(peer)
	if c.is_empty() or not commit_profile.is_valid():return fail("Facilities unavailable")
	if not _flush_pending(str(c.identity)):return fail("Previous workout is waiting to save; retry after the profile is available")
	if request.size()>5 or var_to_bytes(request).size()>1024:return fail("Invalid request")
	var seq: Variant=request.get("sequence",null)
	if not seq is int or seq<1 or seq>1000000000:return fail("Invalid sequence")
	var t:=now()
	var op:=str(request.get("op",""))
	var urgent: bool = op in ["cancel","finish","lower"] and active.get(peer,{}).get("type") == "exercise"
	if not urgent and t-int(last_request.get(peer,-1000))<80:return fail("Please wait")
	last_request[peer]=t
	var p:=profile(c)
	if p.is_empty():return fail("Profile unavailable")
	if seq!=int(p.last_sequence)+1:return fail("Refresh facility state before retrying")
	var current: Dictionary=active.get(peer,{})
	# Cancellation remains available when class restrictions change.
	if op in ["cancel","stand","stop"]:
		if current.get("type","")=="trapped":return fail("Work the bar free, or ask for help")
		var saved:=true
		if current.get("type","")=="exercise":
			var stopped:=p.duplicate(true)
			if not stopped.has("gym"):stopped.gym=GymProgress.empty()
			GymProgress.record_set(stopped.gym,current,"cancelled",t)
			stopped.last_sequence=seq;stopped.revision=int(p.revision)+1
			saved=valid_profile(stopped) and bool(commit_profile.call(str(c.identity),0,stopped))
		if not saved:return fail("Set could not be saved; retry or wait for recovery")
		clear_activity(peer)
		return {"ok":true,"state":private_state(peer)}
	if not bool(c.get("allowed",false)) or not bool(c.get("grounded",false)):
		clear_activity(peer,"interrupted")
		return fail("Activity unavailable during class or while moving")
	# Enforce exercise expiry at request time too; tick may not have run yet.
	if current.get("type","")=="exercise" and (not activity_valid(c,current) or t-int(current.last_beat)>15000):
		clear_activity(peer,"input_failure" if t-int(current.last_beat)>15000 else "interrupted")
		return fail("Exercise interrupted; start a new set")
	if live_lifts and op == "effort":
		var result := _lift_effort(peer, current)
		if not result.get("failed", false):
			return result
		op = "rep_fail"
	var next:=p.duplicate(true)
	if not next.has("gym"):next.gym=GymProgress.empty()
	var recovery_since: int=int(gym_recovery_clock.get(c.identity,t))
	GymProgress.advance(next.gym,maxf(0.0,float(t-recovery_since)/1000.0))
	var dollars:=0
	var station:=str(request.get("station",""))
	var next_active:=current.duplicate(true)
	var event: Dictionary={}
	var rescue_target := 0
	var rescue_gain := 0.0
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
		var portable_bar: bool=station=="gym/barbell"
		var portable: bool=station=="gym/dumbbell" or portable_bar
		if not current.is_empty() or carried_order_count(p.orders)>0 or (not portable and not reachable(c,station)):return fail("Equipment unavailable")
		if portable and str(c.room_id)!="gym":return fail("Use the dumbbells in the gym")
		var station_type: String=("barbell" if portable_bar else "curl") if portable else str(anchors[station].get("kind",""))
		var bench_pair: bool=not portable and station_type=="benchpress" and request.get("equipment","")=="dumbbell"
		var bench_bar: bool=not portable and station_type=="benchpress" and request.get("equipment","")=="barbell"
		if portable:station=("gym/barbell/%d" if portable_bar else "gym/dumbbell/%d")%peer
		var exercise:=str(request.get("exercise",station_type))
		if seats.has(station) or (exercise not in BENCH_DUMBBELL_EXERCISES if bench_pair else (not STATION_EXERCISES.has(station_type) or exercise not in STATION_EXERCISES[station_type])):return fail("Exercise unavailable at this station")
		var weight: Variant=request.get("weight",WEIGHTS.get(exercise,[0])[0])
		if station_type=="curl" or bench_pair:
			weight=float(dumbbell_mass.call(peer)) if dumbbell_mass.is_valid() else 0.0
			if weight<=0:return fail("Take and equip a dumbbell pair first")
		elif portable_bar or bench_bar:
			weight=float(held_barbell_mass.call(peer)) if held_barbell_mass.is_valid() else 0.0
			if weight<=0:return fail("Pick up a barbell first")
			if bench_bar and (not barbell_mass.is_valid() or float(barbell_mass.call(station))>0.0):return fail("Clear the bench rack before using your carried bar")
		elif station_type=="cable":
			if not weight is int or weight<5 or weight>100 or weight%5!=0:return fail("Choose a cable resistance from 5 to 100 kg")
			if live_lifts and weight != cable_weights.get(station, 5):
				return fail("The selector pin changed. Check the stack before starting.")
		elif station_type in ["benchpress","squat"]:
			weight=float(barbell_mass.call(station)) if barbell_mass.is_valid() else 0.0
			if weight<=0:return fail("Barbell unavailable")
		elif not weight is int or not weight in WEIGHTS[exercise]:return fail("Unsupported exercise weight")
		if station_type in ["pushup","pullup"] and worn_belt_mass.is_valid():weight=float(weight)+maxf(0.0,float(worn_belt_mass.call(peer)))
		next_active={"type":"exercise","exercise":exercise,"station":station,"position":c.position,"room_id":c.room_id,"started":t,"last_beat":t,"phase":0,"reps":0,"weight":weight}
		next_active.identity=str(c.identity)
		next_active.initial_muscles=GymProgress.set_snapshot(next.gym,exercise)
		var body_mass: Variant=player_body_mass.call(peer) if player_body_mass.is_valid() else 70.0
		next_active.body_mass=clampf(float(body_mass),35.0,160.0) if (body_mass is int or body_mass is float) and is_finite(float(body_mass)) else 70.0
		if bench_pair or station_type=="curl":next_active.equipment="dumbbell"
		elif portable_bar or bench_bar:next_active.equipment="barbell"
		if station_type=="benchpress" and anchors[station].get("bench_position") is Vector3:
			next_active.bench_position=anchors[station].bench_position
		if station_type=="pullup":
			var grip_key: String="dip_grip" if exercise=="dip" else "pullup_grip"
			if anchors[station].get(grip_key) is Vector3:next_active.grip_anchor=anchors[station][grip_key]
		if station_type=="pushup" and anchors[station].get("mat_position") is Vector3:
			next_active.mat_position=anchors[station].mat_position
		next_active.half_ms=GymProgress.movement_ms(next.gym,exercise,float(weight),int(EXERCISES[exercise])/2,next_active.body_mass)
		if live_lifts:
			_prepare_raise(next_active, next.gym, t)
		event=_exercise_event(next_active)
		if next_active.has("equipment"):event.equipment=next_active.equipment
		if next_active.has("bench_position"):event.bench_position=next_active.bench_position
		if next_active.has("grip_anchor"):event.grip_anchor=next_active.grip_anchor
		if next_active.has("mat_position"):event.mat_position=next_active.mat_position
	elif op=="lower":
		if current.get("type","")!="exercise" or not activity_valid(c,current) or int(current.phase)!=0:return fail("Wait for the next repetition")
		next_active.phase=2 if live_lifts else 1
		next_active.last_beat=t
		if live_lifts:
			next_active.lift_progress = 1.0
		event=_exercise_event(next_active)
	elif op=="beat":
		if current.get("type","")!="exercise" or not activity_valid(c,current):return fail("Start an exercise first")
		if live_lifts:
			if int(current.phase) != 2 or t-int(current.last_beat) < int(current.half_ms):return fail("Wait until the weight is down")
		elif int(current.phase)!=1:return fail("Lower the weight first")
		var gap:=t-int(current.last_beat)
		if gap>15000:
			clear_activity(peer,"input_failure")
			return fail("Rhythm missed; start a new set")
		if int(current.reps)>=500:return fail("Set complete; finish to save")
		next_active.last_beat=t
		next_active.phase=0
		if int(next_active.phase)==0:
			var effort: Dictionary=GymProgress.rep(next.gym,str(current.exercise),float(current.weight),float(current.get("body_mass",70.0)))
			if effort.failure:
				GymProgress.record_set(next.gym,current,"failure",t)
				next_active = _failed_lift(next_active, next.gym, t)
				event = trap_event(next_active) if not next_active.is_empty() else {"activity":"idle"}
				event.failure = true
			else:next_active.reps+=1
		if not next_active.is_empty() and next_active.type=="exercise":
			next_active.half_ms=GymProgress.movement_ms(next.gym,str(current.exercise),float(current.weight),int(EXERCISES[current.exercise])/2,float(current.get("body_mass",70.0)))
			if live_lifts:
				_prepare_raise(next_active, next.gym, t)
			event=_exercise_event(next_active)
	elif op=="rep_fail":
		if current.get("type","")!="exercise" or not activity_valid(c,current) or int(current.phase)!=1:return fail("No repetition to fail")
		if live_lifts and not _effort_failed(current, t):return fail("The lift is still in progress")
		GymProgress.record_set(next.gym,current,"failure",t)
		next_active = _failed_lift(next_active, next.gym, t)
		event = trap_event(next_active) if not next_active.is_empty() else {"activity":"idle"}
		event.failure = true
	elif op=="wiggle":
		if current.get("type","")!="trapped" or not activity_valid(c,current):return fail("No trapped bar to move")
		var direction: Variant=request.get("direction",0)
		if not direction is int or direction!=int(current.direction):return fail("Move in the indicated direction")
		if t-int(current.last_wiggle)<650:return fail("Move steadily, then try again")
		var capacity: float=GymProgress.capacity(next.gym,str(current.exercise))
		var difficulty:=clampf(float(current.weight)/maxf(capacity,1.0),.5,4.0)
		next_active.progress=minf(1.0,float(current.progress)+.14/difficulty)
		next_active.last_wiggle=t;next_active.direction=-int(current.direction)
		if next_active.progress>=1.0:
			next_active={};event={"activity":"idle","escaped":true}
		else:event=trap_event(next_active)
	elif op=="assist":
		var target: Variant=request.get("target",0)
		if not target is int or target==peer or not current.is_empty() or not active.has(target):return fail("No player needs help")
		var trapped: Dictionary=active[target]
		if trapped.get("type","")!="trapped" or str(trapped.room_id)!=str(c.room_id) or c.position.distance_to(trapped.position)>2.5 or not reachable(c,str(trapped.station)) or not bool(c.get("allowed",false)) or not bool(c.get("grounded",false)) or not activity_valid(trusted(target),trapped):return fail("Move closer to the trapped player")
		if t-int(last_assist.get(peer,-1000))<1000:return fail("Take a moment before helping again")
		var helper_capacity: float=GymProgress.capacity(next.gym,str(trapped.exercise))
		if helper_capacity <= 0:return fail("You lack the strength to help")
		rescue_target=target;rescue_gain=clampf(.42*helper_capacity/maxf(float(trapped.weight),1.0),.01,.55)
		event={"activity":"assist","target":target}
	elif op=="finish":
		if current.get("type","")!="exercise" or not activity_valid(c,current) or int(current.reps)<1 or (int(current.phase)!=0 if not live_lifts else int(current.phase)!=1 or float(current.lift_progress)>0.0):return fail("Complete a repetition first")
		var reps:=int(current.reps)
		if t-int(current.started)<reps*120:return fail("Invalid exercise timing")
		next.xp=mini(1000000000,int(p.xp)+reps*(5+int(current.get("weight",0))/20))
		var old: Dictionary=p.records.get(current.exercise,{"reps":0})
		if reps>int(old.reps):next.records[current.exercise]={"reps":reps}
		GymProgress.record_set(next.gym,current,"voluntary",t)
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
	gym_recovery_clock[c.identity]=t
	if op=="consume":last_bite[c.identity]=t
	if current.has("station"):seats.erase(current.station)
	if next_active.is_empty():active.erase(peer)
	else:
		active[peer]=next_active
		if next_active.has("station"):seats[next_active.station]=peer
	public_event.emit(str(c.room_id),peer,event)
	if rescue_target!=0 and active.has(rescue_target):
		last_assist[peer]=t
		var trapped: Dictionary=active[rescue_target]
		trapped.progress=minf(1.0,float(trapped.progress)+rescue_gain)
		if trapped.progress>=1.0:clear_activity(rescue_target)
		else:public_event.emit(str(trapped.room_id),rescue_target,trap_event(trapped))
	return {"ok":true,"state":private_state(peer),"muscular_failure":bool(event.get("failure",false)),"spot_saved":bool(event.get("spot_saved",false))}

func _prepare_raise(value: Dictionary, gym: Dictionary, t: int) -> void:
	var exercise := str(value.exercise)
	value.lift_settings = GymProgress.lift_parameters(GymProgress.capacity(gym, exercise), GymProgress.effective_load(exercise, float(value.weight), float(value.body_mass)))
	value.phase = 1
	value.lift_progress = 0.0
	value.lift_at = t

func _progress_at(value: Dictionary, t: int) -> float:
	match int(value.phase):
		0:
			return 1.0
		2:
			return 1.0 - smoothstep(0.0, float(value.half_ms), float(t-int(value.last_beat)))
		_:
			var settings: Vector3 = value.lift_settings
			var elapsed := maxf(0.0, float(t-int(value.lift_at)-220)/1000.0)
			return maxf(0.0, float(value.lift_progress)-settings.y*elapsed)

func _effort_failed(value: Dictionary, t: int) -> bool:
	var settings: Vector3 = value.lift_settings
	return (settings.z < 1.0 and float(value.lift_progress) >= settings.z) or (float(value.lift_progress) > 0.0 and _progress_at(value, t) <= 0.0)

func _lift_effort(peer: int, value: Dictionary) -> Dictionary:
	if value.get("type") != "exercise" or int(value.phase) != 1:
		return fail("Wait until the weight is ready to raise")
	var t := now()
	if _effort_failed(value,t):
		return {"failed":true}
	var settings: Vector3 = value.lift_settings
	value.lift_progress = minf(settings.z, _progress_at(value, t)+settings.x)
	value.lift_at = t
	value.last_beat = t
	if value.lift_progress >= 1.0:
		value.phase = 0
	public_event.emit(str(value.room_id), peer, _exercise_event(value))
	if _effort_failed(value,t):
		return {"failed":true}
	return {"ok":true, "lift":{"phase":value.phase,"lift_progress":value.lift_progress}}

func _failed_lift(value: Dictionary, gym: Dictionary, t: int) -> Dictionary:
	if value.get("equipment","") == "dumbbell" or value.exercise not in ["benchpress","incline_press","squat"] or value.station not in ["gym/benchpress","gym/squat"]:
		return {}
	var capacity := GymProgress.capacity(gym, str(value.exercise))
	value.type = "trapped"
	value.progress = 0.0
	value.last_wiggle = t
	value.direction = -1
	value.trap_load_ratio = clampf(float(value.weight) / maxf(capacity, 1.0), .5, 4.0)
	return value

func trapped_damage_rate(peer: int) -> float:
	var value: Dictionary = active.get(peer, {})
	if value.get("type") != "trapped":
		return 0.0
	return 1.5 + 1.6 * float(value.get("trap_load_ratio", 1.0))

func trap_event(value: Dictionary) -> Dictionary:
	var event:={"activity":"trapped","station":value.station,"exercise":value.exercise,"weight":value.weight,"progress":value.progress}
	if value.has("bench_position"):event.bench_position=value.bench_position
	if value.has("equipment"):event.equipment=value.equipment
	return event

func _exercise_event(value: Dictionary) -> Dictionary:
	var event:={"activity":"exercise","exercise":value.exercise,"phase":value.phase,"reps":value.reps,"weight":value.weight,"station":value.station,"half_ms":value.get("half_ms",0)}
	if value.has("lift_settings"):
		var progress := _progress_at(value, now())
		event.lift_progress = progress
		event.phase = progress if str(value.station).begins_with("gym/cable_") else 1.0-progress
	for key in ["equipment","bench_position","grip_anchor","mat_position"]:
		if value.has(key):event[key]=value[key]
	return event

func activity_valid(c: Dictionary, a: Dictionary) -> bool:
	return str(c.get("room_id",""))==str(a.get("room_id","")) and c.position.distance_to(a.position)<0.35 and bool(c.get("allowed",false)) and bool(c.get("grounded",false))

func clear_activity(peer: int,outcome: String="") -> void:
	if not active.has(peer):return
	var a: Dictionary=active[peer]
	if a.get("type","")=="exercise" and outcome in ["input_failure","interrupted"]:
		var context:=trusted(peer)
		# Roster removal can precede peer_disconnected. The identity was captured by
		# the host when this set began; the profile adapter still requires a binding.
		if context.is_empty() and authority.is_valid() and bool(authority.call()) and not str(a.get("identity","")).is_empty():
			context={"identity":a.identity}
		var identity:=str(a.get("identity",context.get("identity","")))
		if not identity.is_empty():
			var queue: Array=pending_sets.get(identity,[])
			queue.append({"active":a.duplicate(true),"outcome":outcome,"at":now()})
			pending_sets[identity]=queue
			_flush_pending(identity)
	if a.has("station"):seats.erase(a.station)
	active.erase(peer)
	public_event.emit(str(a.get("room_id","")),peer,{"activity":"idle"})

func _flush_pending(identity: String) -> bool:
	if not pending_sets.has(identity):return true
	while not pending_sets[identity].is_empty():
		var previous:=profile({"identity":identity})
		if previous.is_empty() or not commit_profile.is_valid():return false
		var record: Dictionary=pending_sets[identity][0]
		var next:=previous.duplicate(true)
		if not next.has("gym"):next.gym=GymProgress.empty()
		GymProgress.record_set(next.gym,record.active,str(record.outcome),int(record.at))
		next.last_sequence=int(previous.last_sequence)+1;next.revision=int(previous.revision)+1
		if not valid_profile(next) or not bool(commit_profile.call(identity,0,next)):return false
		var queue: Array=pending_sets[identity]
		queue.pop_front()
	pending_sets.erase(identity)
	return true

func tick() -> void:
	for peer in active.keys():
		var c:=trusted(int(peer))
		var a: Dictionary=active[peer]
		if live_lifts and a.get("type") == "exercise" and not c.is_empty() and activity_valid(c,a):
			var t := now()
			var op := ""
			if int(a.phase) == 2 and t-int(a.last_beat) >= int(a.half_ms):
				op = "beat"
			elif int(a.phase) == 1 and _effort_failed(a, t):
				op = "rep_fail"
			if not op.is_empty() and t-int(last_request.get(peer,-1000)) >= 80:
				var current_profile := profile(c)
				if not current_profile.is_empty():
					var result := act(int(peer), {"op":op,"sequence":int(current_profile.last_sequence)+1})
					if result.get("ok",false):
						live_lift_result.emit(int(peer), result)
						continue
			if int(a.phase) == 2 or (int(a.phase) == 1 and float(a.lift_progress) > 0.0):
				public_event.emit(str(a.room_id), int(peer), _exercise_event(a))
		if c.is_empty() or not activity_valid(c,a) or (a.get("type","")=="emote" and now()>=int(a.until)) or (a.get("type","")=="exercise" and now()-int(a.last_beat)>15000):
			var outcome:="input_failure" if a.get("type","")=="exercise" and now()-int(a.last_beat)>15000 else "interrupted"
			clear_activity(int(peer),outcome)

func movement_locked(peer: int) -> bool:return active.has(peer)

func public_profile(peer: int, share_gym: bool=false) -> Dictionary:
	if not share_gym:return {}
	var s:=private_state(peer)
	if s.is_empty():return {}
	return {"gym_level":s.level,"gym_records":s.profile.records.duplicate(true),"emotes":s.profile.unlocks.duplicate()}
