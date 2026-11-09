class_name DormPersonalStationRouter
extends Node

## Routes furnished dorm props to the existing electronics UI without copying
## profile, inventory, kit, or notebook state into the room scene.
##
## Ownership provider contract (host-backed data only):
##   room_for_peer(peer_id: int) -> String
##   authenticated_identity(peer_id: int) -> String
##   owner_identity(room_id: String) -> String
## Optional:
##   assignment_revision() -> int

const ROLE := "dorm_personal_station"
const PAGES := {
	"loadout": "inventory",
	"notes": "notes",
}

var game: Node
var ownership_provider: Object
var _stations := {}
var _opened_room := ""
var _opened_page := ""
var _observed_revision := -1

func configure(owner_game: Node, provider: Object) -> void:
	game=owner_game
	ownership_provider=provider
	_observed_revision=_provider_revision()

func register_station(station: Node, room_id: String, station_kind: String) -> bool:
	if not is_instance_valid(station) or room_id.is_empty() or not PAGES.has(station_kind):return false
	station.set_meta("role",ROLE)
	station.set_meta("dorm_room_id",room_id)
	station.set_meta("station_kind",station_kind)
	station.set_meta("page",PAGES[station_kind])
	station.set_meta("label",_prompt_for(station_kind))
	_stations[station.get_instance_id()]=station
	return true

func unregister_station(station: Node) -> void:
	if is_instance_valid(station):_stations.erase(station.get_instance_id())
	reconcile_assignment()

func interact(target: Node) -> bool:
	if not is_instance_valid(target) or target.get_meta("role","")!=ROLE:return false
	if not _stations.has(target.get_instance_id()) or _stations[target.get_instance_id()]!=target:return true
	var room_id := str(target.get_meta("dorm_room_id",""))
	var page := str(target.get_meta("page",""))
	if not PAGES.values().has(page) or not _local_peer_owns(room_id):
		_notice("This is the resident's personal workstation.")
		return true
	if not is_instance_valid(game) or not is_instance_valid(game.get("electronics")):
		_notice("Your personal workstation is not ready yet. The shop remains available.")
		return true
	game.electronics.open(page)
	_opened_room=room_id
	_opened_page=page
	return true

func prompt_for(target: Node) -> String:
	if not is_instance_valid(target) or target.get_meta("role","")!=ROLE:return ""
	var room_id := str(target.get_meta("dorm_room_id",""))
	if not _local_peer_owns(room_id):return "Resident's personal workstation"
	return _prompt_for(str(target.get_meta("station_kind","")))

func replacements_ready_for_local_owner() -> bool:
	var peer := _local_peer_id()
	var room_id := _provider_string("room_for_peer",[peer])
	if peer<=0 or room_id.is_empty() or not _local_peer_owns(room_id):return false
	var found := {}
	for station in _stations.values():
		if is_instance_valid(station) and str(station.get_meta("dorm_room_id",""))==room_id:
			found[str(station.get_meta("station_kind",""))]=true
	return found.has("loadout") and found.has("notes")

func shop_page_has_dorm_replacement(page: String) -> bool:
	return replacements_ready_for_local_owner() and page in ["kits","inventory","notes"]

func reconcile_assignment() -> void:
	var revision := _provider_revision()
	if revision==_observed_revision and _opened_room.is_empty():return
	_observed_revision=revision
	if not _opened_room.is_empty() and not _local_peer_owns(_opened_room):_close_owned_ui()

func assignment_changed() -> void:
	## Ownership providers may connect their assignment signal directly here.
	_observed_revision=-1
	reconcile_assignment()

func _process(_delta: float) -> void:
	if not _opened_room.is_empty() or _provider_revision()!=_observed_revision:reconcile_assignment()

func _exit_tree() -> void:
	_close_owned_ui()

func _close_owned_ui() -> void:
	if is_instance_valid(game):
		var electronics=game.get("electronics")
		if is_instance_valid(electronics) and bool(electronics.get("active")) and str(electronics.get("current_page"))==_opened_page:
			electronics.close()
	_opened_room=""
	_opened_page=""

func _local_peer_owns(room_id: String) -> bool:
	if room_id.is_empty() or ownership_provider==null:return false
	var peer := _local_peer_id()
	if peer<=0:return false
	var assigned_room := _provider_string("room_for_peer",[peer])
	var authenticated := _provider_string("authenticated_identity",[peer])
	var owner := _provider_string("owner_identity",[room_id])
	return assigned_room==room_id and not authenticated.is_empty() and authenticated==owner

func _local_peer_id() -> int:
	if not is_inside_tree() or multiplayer==null:return 0
	return multiplayer.get_unique_id()

func _provider_string(method: StringName, args: Array) -> String:
	if ownership_provider==null or not ownership_provider.has_method(method):return ""
	return str(ownership_provider.callv(method,args))

func _provider_revision() -> int:
	if ownership_provider!=null and ownership_provider.has_method("assignment_revision"):
		return int(ownership_provider.call("assignment_revision"))
	return 0

func _notice(message: String) -> void:
	if is_instance_valid(game):
		var ui=game.get("ui")
		if is_instance_valid(ui) and ui.has_method("log_message"):ui.log_message(message)

func _prompt_for(kind: String) -> String:
	match kind:
		"loadout":return "Organize backpack loadout"
		"notes":return "Open personal notes"
	return "Use workstation"
