extends Node3D
## Shared public workstations in the registered M209 shell.
const Station=preload("res://scripts/campus/presentation/decor/computer_rooms/computer_station.gd")
var stations: Dictionary={}
func mount(campus: Node3D,adapter: Node) -> bool:
	var room: Dictionary=campus.registry.get_room("computer_commons")
	if room.is_empty():return false
	var furniture:=Node3D.new();furniture.name="ComputerCommonsFurniture";campus.add_child(furniture)
	_finish(furniture,campus)
	for row in 2:
		for column in 4:
			var id:="commons_r%d_c%d"%[row,column]
			var station=Station.new();furniture.add_child(station)
			station.position=Vector3(20.0+column*4.0,5.0,63.0+row*2.8)
			station.configure(id);stations[id]=station
			if not adapter.register_station(id,station,true):push_error("Could not register "+id);return false
	if not campus.register_content("computer_commons",furniture):return false
	var lobby:=Node3D.new();lobby.name="LobbyWorkstations";campus.add_child(lobby)
	for index in 2:
		var id:="lobby_public_%d"%index
		var station=Station.new();lobby.add_child(station)
		station.position=[Vector3(10.52,0,-9.5),Vector3(15.48,0,-9.5)][index]
		station.configure(id)
		station.rotation.y=PI/2.0 if index==0 else -PI/2.0
		stations[id]=station
		if not adapter.register_station(id,station,true):push_error("Could not register "+id);return false
	# Small walk-up desks distributed between room entrances on both floors.
	# Their backs face the corridor walls; the central route stays clear.
	var scattered:=Node3D.new();scattered.name="HallwayWorkstations";campus.add_child(scattered)
	var locations := [
		# Desk backs sit 1 cm from each corridor wall's interior face. The
		# chair and user side face the corridor, like the classroom workstations.
		{"point":Vector3(10.52,0,11),"yaw":PI/2},
		{"point":Vector3(15.48,0,26),"yaw":-PI/2},
		{"point":Vector3(10.52,0,40),"yaw":PI/2},
		{"point":Vector3(15.48,5,11),"yaw":-PI/2},
		{"point":Vector3(10.52,5,26),"yaw":PI/2},
		{"point":Vector3(15.48,5,40),"yaw":-PI/2},
	]
	for index in locations.size():
		var id:="hall_public_%d"%index
		var station=Station.new();scattered.add_child(station)
		station.position=locations[index].point
		station.configure(id)
		station.rotation.y=float(locations[index].yaw)
		stations[id]=station
		if not adapter.register_station(id,station,true):push_error("Could not register "+id);return false
	return true

func _finish(root: Node3D,campus: Node3D) -> void:
	var tiles: Array=[]
	for x in range(16,36):
		for z in range(62,68):tiles.append(Vector3(x+.5,5.014,z+.5))
	preload("res://scripts/campus/performance/lit_tile_batches.gd").build(root,tiles,Vector3(.982,.018,.982),campus.material("89999b"))
	for z in [62.1,67.9]:
		campus.box(root,Vector3(26,5.58,z),Vector3(19.8,1.1,.025),"4e697e",false)
		campus.box(root,Vector3(26,6.15,z),Vector3(19.8,.055,.045),"bd936d",false)
		campus.box(root,Vector3(26,5.09,z),Vector3(19.8,.16,.045),"314757",false)
	campus.box(root,Vector3(35.9,5.58,65),Vector3(.025,1.1,5.7),"4e697e",false)
	campus.box(root,Vector3(35.89,6.15,65),Vector3(.045,.055,5.7),"bd936d",false)
	campus.box(root,Vector3(35.89,5.09,65),Vector3(.045,.16,5.7),"314757",false)
