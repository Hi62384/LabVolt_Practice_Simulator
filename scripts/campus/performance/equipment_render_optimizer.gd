extends RefCounted
## Explicit opt-in for authored equipment roots after building them, before use.
## Never pass arbitrary live avatars, boards, cables or streamed gameplay roots.
const Cache = preload("res://scripts/campus/performance/equipment_mesh_cache.gd")
const Batch = preload("res://scripts/campus/performance/static_panel_batch.gd")
const SocketBatch = preload("res://scripts/campus/performance/socket_visual_batch.gd")
var cache := Cache.new()
var batching := Batch.new()
var sockets := SocketBatch.new()
var _originals: Array[Dictionary] = []
var _roots := {}

func optimize_equipment(root: Node3D, protected_nodes: Array = [], batch_static := true) -> Dictionary:
	if _roots.has(root.get_instance_id()):
		return {"already_optimized":true}
	var started := Time.get_ticks_usec()
	_replace(root,root)
	if batch_static:
		batching.apply(root,protected_nodes)
		for socket in root.find_children("*","StaticBody3D",true,false):
			if str(socket.get_meta("role","")) == "socket":
				sockets.apply(socket)
	_roots[root.get_instance_id()] = weakref(root)
	return {"cache":cache.stats(),"batching":batching.stats.duplicate(),"sockets_batched":sockets.sockets_batched,"socket_saved_instances":sockets.saved_instances,"setup_usec":Time.get_ticks_usec()-started}

func _replace(node: Node, root: Node) -> void:
	# The explicitly supplied root can have EquipmentBuilder's script. Other scripted
	# subtrees are excluded because their geometry ownership is not known here.
	if node != root and node.get_script() != null:
		return
	if node is MeshInstance3D and node.mesh is PrimitiveMesh and not node.has_meta("campus_static_batch_source"):
		var original: Mesh = node.mesh
		var replacement: Mesh = cache.replacement(original)
		if replacement != original:
			_originals.append({"node":weakref(node),"mesh":original})
			node.mesh = replacement
	for child in node.get_children():
		_replace(child,root)

func restore() -> void:
	batching.clear()
	sockets.clear()
	for record in _originals:
		var node: MeshInstance3D = record.node.get_ref()
		if is_instance_valid(node):
			node.mesh = record.mesh
	_originals.clear()
	_roots.clear()

func release_original_meshes() -> void:
	# Optional commit after acceptance: releases old high-resolution resources.
	# Afterwards restore() still unbatches, but cannot restore old tessellation.
	_originals.clear()

func optimize_legacy_game(game: Node3D) -> Array:
	# Explicit snapshot02 composition adapter. Future root lists must be supplied
	# through optimize_equipment instead of scanning arbitrary live campus content.
	var results: Array = []
	var training: Node3D = game.get_node_or_null("TrainingStation")
	if training != null:
		results.append(optimize_equipment(training,_protected_for(game)))
	for station in game.stations:
		results.append(optimize_equipment(station.equipment,_protected_for(station.equipment)))
	return results

func _protected_for(builder: Node) -> Array:
	var nodes: Array = builder.needle_bodies.values()
	for entry in builder.switch_meshes.values():
		nodes.append(entry.handle)
		nodes.append(entry.indicator)
	return nodes
