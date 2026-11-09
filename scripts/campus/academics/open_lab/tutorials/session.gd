extends RefCounted
const Catalog = preload("res://scripts/campus/academics/open_lab/tutorials/catalog.gd")
var peer_id := -1
var lab_id := ""
var bench_index := -1
var device_id := ""
var step_index := 0
var skipped: Array[int] = []
var active := false
var tour: Array[String] = []
var tour_index := 0

func configure(peer: int,lab: String,bench: int) -> void:
	assert(peer>=0 and Catalog.COURSES.has(lab))
	peer_id=peer;lab_id=lab;bench_index=bench

func choose(id: String) -> bool:
	if Catalog.find(lab_id,id).is_empty():return false
	device_id=id;step_index=0;skipped.clear();active=true;tour.clear();tour_index=0
	return true

func start_tour() -> bool:
	tour.clear()
	for device in Catalog.devices(lab_id):tour.append(device.id)
	if tour.is_empty():return false
	tour_index=0;device_id=tour[0];step_index=0;skipped.clear();active=true
	return true

func acknowledge() -> bool:
	if not active:return false
	var step: Dictionary=_step()
	if not step.check.is_empty():return false
	_advance();return true

func observe(event: Dictionary,snapshot: Dictionary) -> bool:
	if not active or int(event.get("peer_id",-1))!=peer_id:return false
	if str(event.get("lab_id",""))!=lab_id or int(event.get("bench_index",-1))!=bench_index:return false
	var check: Dictionary=_step().check
	if check.is_empty():return false
	if not _matches(check,event,snapshot):return false
	_advance();return true

func skip() -> void:
	if not active:return
	skipped.append(step_index);_advance()

func restart() -> void:
	if not active:return
	step_index=0;skipped.clear()

func exit() -> void:
	active=false;device_id="";tour.clear();skipped.clear();step_index=0

func view() -> Dictionary:
	if not active:return {"active":false,"lab_id":lab_id,"peer_id":peer_id}
	var device := Catalog.find(lab_id,device_id)
	return {"active":true,"lab_id":lab_id,"course_id":Catalog.COURSES[lab_id],"peer_id":peer_id,"bench_index":bench_index,"device_id":device_id,"title":device.title,"purpose":device.purpose,"output":device.output,"controls":device.controls,"ports":device.ports,"mistakes":device.mistakes,"detail":device.detail,"step_index":step_index,"step_count":device.steps.size(),"step":_step(),"skipped":skipped.duplicate(),"tour":not tour.is_empty(),"tour_index":tour_index}

func _step() -> Dictionary:
	var steps: Array=Catalog.find(lab_id,device_id).get("steps",[])
	return steps[step_index] if step_index<steps.size() else {}

func _advance() -> void:
	step_index+=1
	var steps: Array=Catalog.find(lab_id,device_id).get("steps",[])
	if step_index<steps.size():return
	if not tour.is_empty() and tour_index+1<tour.size():
		tour_index+=1;device_id=tour[tour_index];step_index=0;skipped.clear();return
	active=false

func _matches(check: Dictionary,event: Dictionary,snapshot: Dictionary) -> bool:
	var op := str(check.get("op",""))
	if not op.is_empty():
		if not bool(event.get("accepted",false)) or str(event.get("op",""))!=op:return false
		for key in ["key","index","channel","kind","mode","value","pressed"]:
			if check.has(key) and event.get(key)!=check[key]:return false
		if check.has("port"):
			var port := str(check.port)
			if op=="wire":
				if port not in [str(event.get("a","")),str(event.get("b",""))]:return false
				var present := false
				for wire in snapshot.get("wires",[]):
					if port in wire:present=true;break
				if not present:return false
			elif str(event.get("port",""))!=port:return false
	if check.has("state"):
		var value: Variant=snapshot
		for key in check.state:
			if not value is Dictionary or not value.has(key):return false
			value=value[key]
		if check.has("equals") and value!=check.equals:return false
		if check.get("nonempty",false) and (str(value).is_empty() or str(value)=="—"):return false
		if check.has("contains") and not str(value).contains(str(check.contains)):return false
		if check.has("min_size") and (not value is Array or value.size()<int(check.min_size)):return false
	return true
