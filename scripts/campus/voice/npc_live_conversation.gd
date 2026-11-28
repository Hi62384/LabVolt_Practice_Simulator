extends Node
## Retired compatibility shim. Player audio is recorded locally and transcribed
## once per turn by npc_voice_router. Live is used only by the speech renderer.
## Keeping this resource path lets older scenes load without reopening a session.
func enabled() -> bool:
 return false
func build(_game: Node,_faculty: Node,_router: Node) -> void:
 pass
func clear_session() -> void:
 pass
