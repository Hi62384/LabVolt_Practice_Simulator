extends SceneTree
func _initialize() -> void:
	root.add_child(preload("res://tests/workers/io/network_peer.gd").new())
