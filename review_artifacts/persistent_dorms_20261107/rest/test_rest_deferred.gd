extends SceneTree
const State=preload("res://review_artifacts/persistent_dorms_20261107/rest/rest_state.gd")
class Authority:
	extends RefCounted
	func authenticated_identity(peer: int) -> String:return "owner" if peer==1 else "visitor"
	func can_enter(_identity: String,_room: String) -> bool:return true
	func is_owner(identity: String,_room: String) -> bool:return identity=="owner"
func _initialize() -> void:
	var state=State.new();var authority=Authority.new();var roster={1:{},2:{}}
	assert(state.register_bed("room",Transform3D.IDENTITY))
	assert(not state.begin(2,"room",Vector3.ZERO,authority,roster,false).ok)
	assert(state.begin(1,"room",Vector3.ZERO,authority,roster,false).ok)
	assert(not state.begin(1,"room",Vector3.ZERO,authority,roster,false).ok)
	assert(not state.end(1,null).ok);assert(state.resting.has(1))
	assert(state.end(1,Vector3(1,0,0)).ok);assert(state.resting.is_empty())
	assert(state.begin(1,"room",Vector3.ZERO,authority,roster,false).ok)
	state.disconnect(1);assert(state.resting.is_empty())
	print("REST state fixture passed; physics/network/visual acceptance separate")
	quit()
