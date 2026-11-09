extends Node
var tree: SceneTree
@rpc("authority","call_remote","reliable")
func deliver(packet: Dictionary) -> void:
	tree.deliver(packet)
@rpc("any_peer","call_remote","reliable")
func ack(stage: int) -> void:
	if multiplayer.is_server(): tree.ack(stage,multiplayer.get_remote_sender_id())
