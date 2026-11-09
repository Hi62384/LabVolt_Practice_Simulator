extends Node
## Presentation-only activation. Never sleeps authoritative electrical state.
signal zone_activation_changed(room_id: String, active: bool)
var registry = preload("res://scripts/campus/world/room_registry.gd").new()
var active: Dictionary = {}
var contents: Dictionary = {}
var queue: Array = []
var loaders: Dictionary = {}
var loaded: Dictionary = {}
var loader_usec := 0
var loader_overruns := 0
var activation_budget_usec := 1500
var frame_gate_usec := 25000
var view_distance := 34.0
var last_activation_usec := 0
var total_activation_usec := 0
var activations := 0
var deferred_frames := 0
var slow_streak := 0
var recovery_admissions := 0
var viewer := Vector3(13,0,-18)
var _menu_mode := false
var _menu_rooms := PackedStringArray()

func register_content(id: String, root: Node3D) -> bool:
	if not registry.rooms.has(id) or not is_instance_valid(root): return false
	if not contents.has(id): contents[id]=[]
	if not contents[id].has(root): contents[id].append(root)
	root.visible=bool(active.get(id,false))
	return true

## loader() performs ONE bounded initialization stage, returns true when complete.
## Register presentation content from the loader; never construct/mutate circuit authority here.
func register_loader(id: String, loader: Callable) -> bool:
	if not registry.rooms.has(id) or not loader.is_valid(): return false
	loaders[id]=loader
	loaded[id]=false
	if bool(active.get(id,false)):
		active[id]=false
		for root in contents.get(id,[]):
			if is_instance_valid(root): root.visible=false
	set_viewer_position(viewer)
	return true

func set_menu_rooms(rooms: PackedStringArray) -> void:
	_menu_mode = true
	_menu_rooms = rooms
	_update_desired_rooms()

func clear_menu_rooms() -> void:
	_menu_mode = false
	_menu_rooms = PackedStringArray()
	_update_desired_rooms()

func set_viewer_position(point: Vector3) -> void:
	viewer=point
	if not _menu_mode:
		_update_desired_rooms()

func _update_desired_rooms() -> void:
	var point := viewer
	for id in registry.rooms:
		var room: Dictionary=registry.rooms[id]
		var center: Vector3=registry.vector(room.center)
		var same_floor := absf(point.y-center.y)<2.6
		var wanted := _menu_rooms.has(id) if _menu_mode else (same_floor and Vector2(point.x-center.x,point.z-center.z).length()<view_distance)
		# No request churn: replace pending desire for the same zone.
		for index in range(queue.size()-1,-1,-1):
			if queue[index].id==id: queue.remove_at(index)
		if wanted!=bool(active.get(id,false)): queue.append({"id":id,"active":wanted})

func request_room(id: String) -> void:
	if registry.rooms.has(id) and not bool(active.get(id,false)):
		for item in queue:
			if item.id==id: item.active=true; return
		queue.push_front({"id":id,"active":true})

func advance(frame_usec: int) -> int:
	var allowed_usec := activation_budget_usec
	if frame_usec>frame_gate_usec:
		deferred_frames+=1
		slow_streak+=1
		if slow_streak<5: return 0
		# A lower-end 30 FPS client must not starve room initialization forever.
		allowed_usec=mini(activation_budget_usec,250)
		slow_streak=0
		recovery_admissions+=1
	else: slow_streak=0
	var begin := Time.get_ticks_usec()
	var count := 0
	while not queue.is_empty() and Time.get_ticks_usec()-begin<allowed_usec:
		var change: Dictionary=queue.pop_front()
		if change.active and loaders.has(change.id) and not bool(loaded.get(change.id,false)):
			var stage_begin := Time.get_ticks_usec()
			loaded[change.id]=bool(loaders[change.id].call())
			loader_usec=Time.get_ticks_usec()-stage_begin
			if loader_usec>activation_budget_usec: loader_overruns+=1
			if not loaded[change.id]:
				queue.append(change)
				break
		active[change.id]=change.active
		for root in contents.get(change.id,[]):
			if is_instance_valid(root): root.visible=change.active
		zone_activation_changed.emit(str(change.id),bool(change.active))
		count+=1
	last_activation_usec=Time.get_ticks_usec()-begin
	total_activation_usec+=last_activation_usec
	activations+=count
	return count

func _process(delta: float) -> void:
	advance(int(delta*1000000.0))

func metrics() -> Dictionary:
	return {"pending":queue.size(),"active_zones":active.values().count(true),"activations":activations,"last_activation_usec":last_activation_usec,"total_activation_usec":total_activation_usec,"deferred_frames":deferred_frames,"budget_usec":activation_budget_usec,"last_loader_usec":loader_usec,"loader_overruns":loader_overruns,"recovery_admissions":recovery_admissions}
