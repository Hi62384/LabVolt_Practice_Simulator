extends Node
const Mass=preload("res://scripts/campus/facilities/carry_mass.gd")
const Gym=preload("res://scripts/campus/facilities/gym_progress.gd")
var game: Node

func profile_for(peer: int) -> Dictionary:
	if not is_instance_valid(game):return {}
	if game.session.online and multiplayer.is_server():
		return game.electronics_trade.authority.ledger.account(peer).get("profile",{})
	if peer==multiplayer.get_unique_id():return game.electronics.profile.data
	return {}

func mass_for(peer: int) -> float:
	var profile:=profile_for(peer)
	var total:=Mass.profile_mass(profile)
	if is_instance_valid(game.gym_barbells) and is_instance_valid(game.gym_weights):
		total+=Mass.gym_mass(peer,game.gym_weights.items,game.gym_barbells.bars,game.gym_barbells.belts,game.gym_barbells.plates)
	if is_instance_valid(game.ac_laptops):
		for item in game.ac_laptops.state.get("laptops",[]):
			if int(item.owner)==peer and item.where in ["held","stowed"]:total+=1.8
		for item in game.ac_laptops.state.get("cables",[]):
			if int(item.owner)==peer and item.where in ["held","stowed","partial"]:total+=.12
	if is_instance_valid(game.dc_lab):
		for state in game.dc_lab.states:
			if int(state.get("board_owner",0))==peer and (state.get("board_held",false) or state.get("board_stowed",false)):
				var board: Dictionary=state.get("board",{})
				var kit:=str(board.get("authority_kit_id",""))
				if kit.is_empty() or not _kit_carried(profile,kit):total+=Mass.board_mass(board)
		if multiplayer.is_server():
			total+=.15*float(game.dc_lab.stowed_leads.get(peer,{}).size())
			if game.dc_lab.carried_leads.has(peer):total+=.15
		elif peer==multiplayer.get_unique_id():
			total+=.15*float(game.dc_lab.local_stowed_leads.size())
			if game.dc_lab.lead_color>=0:total+=.15
	var labs: Array=game.session.labs if multiplayer.is_server() else []
	if multiplayer.is_server():
		for lab in labs:
			for cable in lab.cables:
				if int(cable.owner)==peer:total+=.15
			total+=.15*float(lab.stored_cables.get(peer,[]).size())
	elif peer==multiplayer.get_unique_id():
		for state in game.station_snapshots:
			for cable in state.get("cables",[]):
				if int(cable.owner)==peer:total+=.15
			total+=.15*float(state.get("stored_cables",{}).get(peer,state.get("stored_cables",{}).get(str(peer),[])).size())
	for paper in game.school.papers.values():
		if int(paper.get("owner",0))==peer and (paper.get("held",false) or paper.get("stowed",false)) and not paper.has("supply_id") and not paper.get("calculator",false) and not paper.get("notebook",false):total+=.01
	var facilities: Dictionary=profile.get("facilities",{})
	for order in facilities.get("orders",{}).values():
		if order.get("station","")=="":total+=.35
	return maxf(0.0,total)

func _kit_carried(profile: Dictionary,id: String) -> bool:
	return id in preload("res://scripts/campus/dorms/authority/backpack_inventory.gd").carried_kits(profile.get("dorm",{}))

func multiplier(peer: int) -> float:
	var profile:=profile_for(peer)
	var strength:=Gym.overall_strength(profile.get("facilities",{}).get("gym",{"muscles":{}}))
	return Mass.speed_multiplier(mass_for(peer),strength)
