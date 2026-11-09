extends Node
## Candidate coordinator adapter. Host authority supplies owner and access decisions.
const Interior = preload("res://review_artifacts/persistent_dorms_20261107/room/room_interior.gd")
var game: Node
var authority: Object
var computer_session: Object
var room: Node3D
var room_id := ""
var occupant_count := 0
var open_wardrobe: Callable
var begin_rest: Callable
var use_desk_chair: Callable
var open_storage: Callable

func configure(owner_game: Node, dorm_authority: Object, m203_session: Object) -> void:
	game=owner_game;authority=dorm_authority;computer_session=m203_session

func bind_personal_actions(wardrobe: Callable, rest: Callable, chair: Callable, storage: Callable) -> void:
	open_wardrobe=wardrobe;begin_rest=rest;use_desk_chair=chair;open_storage=storage

func enter(contract: Dictionary, public_projection: Dictionary, authenticated_identity: String) -> bool:
	var id:=str(contract.get("dorm_id",""))
	if id.is_empty() or authority==null or not authority.has_method("can_enter") or not authority.call("can_enter",authenticated_identity,id):return false
	if is_instance_valid(room) and room_id!=id:return false
	if not is_instance_valid(room):
		room=Interior.new();add_child(room);room.build(contract,public_projection.get("style",{}));room_id=id
	occupant_count+=1
	return true

func leave() -> void:
	occupant_count=maxi(0,occupant_count-1)
	if occupant_count==0 and is_instance_valid(room):room.queue_free();room=null;room_id=""

func interact(target: Node, authenticated_identity: String) -> bool:
	if not is_instance_valid(room) or not is_instance_valid(target) or target.get_parent()!=room:return false
	if target.get_meta("role","")!="dorm_room_prop" or str(target.get_meta("room_id",""))!=room_id:return false
	var kind:=str(target.get_meta("kind",""))
	if kind in ["bedside_lamp","desk_lamp"]:return room.toggle_lamp(kind)
	if authority==null or not authority.has_method("is_owner") or not authority.call("is_owner",authenticated_identity,room_id):return true
	match kind:
		"kit_workshop","loadout","notes":
			var router=game.get("dorm_interactions")
			if is_instance_valid(router):
				var station_kind:=kind
				router.register_station(target,room_id,station_kind)
				return router.interact(target)
		"wardrobe":
			if open_wardrobe.is_valid():open_wardrobe.call()
		"storage":
			if open_storage.is_valid():open_storage.call(room_id)
		"computer":
			if authority.has_method("request_personal_computer"):
				authority.call("request_personal_computer",room_id)
		"bed":
			if begin_rest.is_valid():begin_rest.call(target.global_transform)
		"study_chair":
			if use_desk_chair.is_valid():use_desk_chair.call(target.global_transform)
	return true

func storage_transfer(authenticated_identity: String, operation_id: String, item_id: String, quantity: int, into_storage: bool) -> Dictionary:
	if authority==null or not authority.has_method("storage_transfer"):return {"ok":false,"error":"Dorm storage is unavailable"}
	if not authority.has_method("is_owner") or not authority.call("is_owner",authenticated_identity,room_id):return {"ok":false,"error":"Owner access required"}
	return authority.call("storage_transfer",authenticated_identity,room_id,operation_id,item_id,quantity,into_storage)
