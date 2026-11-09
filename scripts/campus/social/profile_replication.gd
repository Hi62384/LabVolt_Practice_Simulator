extends RefCounted
const Profiles = preload("res://scripts/campus/social/public_profiles.gd")
var identity_map := preload("res://scripts/campus/social/public_identity.gd").new()
var published := {}
var revisions := {}
var peer_cache := {}
var peer_sequences := {}
func publish(identity: String, name: String, private_source: Dictionary, visibility: Dictionary) -> void:
	if identity.is_empty(): return
	var safe := Profiles.project(identity_map.public_id(identity),name,private_source,visibility)
	if published.get(identity)==safe: return
	published[identity]=safe
	revisions[identity]=int(revisions.get(identity,0))+1
func remove(identity: String) -> void:
	published.erase(identity)
	revisions[identity]=int(revisions.get(identity,0))+1
func collect(peer_id: int, relevant_identities: Array) -> Array:
	var previous: Dictionary=peer_cache.get(peer_id,{})
	var packets: Array=[]
	var next := {}
	for identity in relevant_identities:
		if not published.has(identity): continue
		var current: Dictionary=published[identity]
		if previous.get(identity)!=current:
			peer_sequences[peer_id]=int(peer_sequences.get(peer_id,0))+1
			packets.append(Profiles.delta(previous.get(identity,{}),current,int(peer_sequences[peer_id])))
		next[identity]=current.duplicate(true)
	for identity in previous:
		if not next.has(identity):
			peer_sequences[peer_id]=int(peer_sequences.get(peer_id,0))+1
			packets.append({"id":previous[identity].id,"revision":int(peer_sequences[peer_id]),"clear":true})
	peer_cache[peer_id]=next
	return packets
func forget_peer(peer_id: int) -> void:
	peer_cache.erase(peer_id)
	peer_sequences.erase(peer_id)
