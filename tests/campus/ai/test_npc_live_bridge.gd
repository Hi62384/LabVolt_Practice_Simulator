extends SceneTree
## The old resource is deliberately inert. No player microphone may acquire a
## persistent Live session or a separate delegation/reasoning path.
const Bridge=preload("res://scripts/campus/voice/npc_live_conversation.gd")
const Router=preload("res://scripts/campus/voice/npc_voice_router.gd")
func _initialize() -> void:
 var retired:=Bridge.new()
 assert(not retired.enabled())
 assert(not retired.has_method("begin_turn"))
 assert(not retired.has_method("feed_packet"))
 var router:=Router.new()
 assert(not router.get_property_list().any(func(property: Dictionary):return property.name=="live_bridge"))
 assert(router.has_method("_deliver"))
 retired.free();router.free()
 print("NPC_LIVE_BRIDGE PASS (native player conversation path retired; turn-based routing retained)")
 quit(0)
