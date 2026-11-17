extends Node
var staged:=false
@rpc("any_peer","call_remote","reliable",6)
func report_staged() -> void:
	if multiplayer.is_server():staged=true
