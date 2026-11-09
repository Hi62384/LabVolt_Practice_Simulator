extends RefCounted
const Profiles = preload("res://scripts/campus/social/public_profiles.gd")
var profiles := {}
var revisions := {}
func receive(packet: Dictionary) -> bool:
	var identity := str(packet.get("id",""))
	var revision := int(packet.get("revision",-1))
	if identity.is_empty() or identity.length()>128 or revision<=int(revisions.get(identity,-1)): return false
	revisions[identity]=revision
	if packet.get("clear",false): profiles.erase(identity)
	else: profiles[identity]=Profiles.apply_delta(profiles.get(identity,{}),packet)
	return true
func clear() -> void:
	profiles.clear(); revisions.clear()
