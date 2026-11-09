extends SceneTree
# Run only in an independently authorized isolated candidate, never under the current hold.
const Crowd = preload("res://scripts/campus/npcs/local_crowd.gd")
var failures := 0
var assertions := 0
func _initialize() -> void:
	call_deferred("run")
func check(ok: bool, label: String) -> void:
	assertions += 1
	if not ok:
		failures += 1
		printerr("FAIL: " + label)
func finite_state(c, label: String) -> void:
	check(c.get_child_count() == c._pool.size(), label + " child/pool count")
	for item in c._pool:
		check(is_instance_valid(item.node) and item.node is MeshInstance3D, label + " valid visual")
		check(item.node.position.is_finite() and item.node.rotation.is_finite(), label + " finite transform")
		check(is_finite(float(item.clock)) and float(item.clock) >= 0.0, label + " finite nonnegative clock")
		check(is_finite(float(item.phase)), label + " finite phase")
		for point in item.route:
			check(point.is_finite(), label + " finite route point")
func state_snapshot(c) -> Array:
	var state: Array = [c.density, c._zone, c._viewer, c._spawn_clock, c._updates, c._update_calls, c._adaptive_cap, c._slow_seconds, c._fast_seconds]
	for item in c._pool:
		state.append([item.node.get_instance_id(), item.node.position, item.node.rotation, item.node.visible, item.clock, item.phase, item.target, item.lod, item.route.duplicate()])
	return state
func source_dependencies(c) -> void:
	# Limited lexical checks on this script only: no transport/runtime isolation claim.
	var script: Script = c.get_script()
	var source: String = script.source_code
	for token in ["@rpc", ".rpc(", ".rpc_id(", "multiplayer.", "HTTPRequest", "WebSocketPeer", "ENetMultiplayerPeer", "CollisionShape3D", "CharacterBody3D", "NavigationAgent3D"]:
		check(not source.contains(token), "local script omits dependency " + token)
	check(source.count("preload(") == 0, "local crowd has no preloaded script dependencies")
	check(Crowd.MESH_PATHS == ["res://assets/campus/npcs/student_full.tres", "res://assets/campus/npcs/student_reduced.tres"], "declared resource inputs remain the two meshes")
func run() -> void:
	var c := Crowd.new()
	c.allow_headless = true
	root.add_child(c)
	c.set_process(false)
	# Synthetic shared templates avoid disk loading and imported assets in this test.
	c._meshes.append(ArrayMesh.new())
	c._meshes.append(ArrayMesh.new())
	# Direct creation checks initialization, ownership and actual node allocation.
	check(c._pool.is_empty() and c.get_child_count() == 0, "starts with no visual allocation")
	c._create_visual()
	check(c._pool.size() == 1 and c.get_child_count() == 1, "create allocates one child and one pool record")
	check(c._pool[0].node.get_parent() == c and c._pool[0].node.mesh == c._meshes[0], "created child owned here and shares template")
	check(c._pool[0].clock == 0.0 and c._pool[0].phase == 0.0, "creation initializes clock and phase")
	finite_state(c, "created")
	var route := PackedVector3Array([Vector3.ZERO, Vector3(4,0,0)])
	c.set_routes("a", [route])
	c.set_routes("b", [route])
	c.set_context("a", Vector3.ZERO)
	c.set_density("High")
	for i in 100:
		var previous_count: int = c._pool.size()
		c.advance(0.1)
		check(c._pool.size() >= previous_count and c._pool.size() <= previous_count + 1, "advance allocates at most one visual")
		check(c._pool.size() <= 18, "advance respects high density ceiling")
		finite_state(c, "growth")
	check(c._pool.size() == 18 and c._pool.size() <= Crowd.HARD_CAP, "high pool cap")
	var handles: Array[int] = []
	for item in c._pool:
		handles.append(item.node.get_instance_id())
	for cycle in 250:
		c.set_density("Off")
		var updates: int = c.get_stats().updates
		for frame in 4:
			c.advance(0.1)
		check(c.get_stats().active == 0 and c.get_stats().updates == updates, "Off sleeps visuals")
		c.set_context("missing", Vector3.ZERO)
		c.set_density("High")
		c.advance(0.1)
		check(c.get_stats().active == 0, "missing zone hides")
		c.set_context("a" if cycle % 2 == 0 else "b", Vector3.ZERO)
		c.advance(0.1)
		check(c._pool.size() == handles.size(), "zone cycling reuses pool")
		finite_state(c, "zone cycle")
		for index in handles.size():
			check(c._pool[index].node.get_instance_id() == handles[index], "stable pooled node")
	c.set_context("a", Vector3.ZERO)
	c.advance(0.1)
	c.set_routes("a", [])
	check(c.get_stats().active == 0, "replacement invalidation hides synchronously")
	c.set_routes("a", [route])
	var item: Dictionary = c._pool[0]
	item.clock = 0.12
	item.node.rotation = Vector3(0,1,0.025)
	var prior_phase: float = item.phase
	c._assign_route(item, 0)
	check(item.phase == prior_phase and is_finite(float(item.phase)), "reassignment retains finite animation phase")
	finite_state(c, "reassigned")
	check(item.clock == 0.0 and item.node.rotation == Vector3.ZERO, "assignment clears prior time and pose")
	# Invalid calls must be no-ops for transforms, timers, counters and context.
	var snapshot: Array = state_snapshot(c)
	for delta in [0.0, -1.0, NAN, INF, -INF]:
		c.advance(delta)
		c.observe_frame_time(delta)
		check(state_snapshot(c) == snapshot, "invalid frame input is a no-op")
	for position_value in [Vector3(NAN,0,0), Vector3(0,INF,0), Vector3(0,0,-INF)]:
		c.set_context("invalid-zone", position_value)
		check(state_snapshot(c) == snapshot, "invalid viewer input is a no-op")
	c.set_density("Invalid")
	check(state_snapshot(c) == snapshot, "invalid density is a no-op")
	finite_state(c, "invalid inputs")
	# Existing sanitation accepts only finite Vector3 points and two-point routes.
	c.set_routes("b", [null, 5, [], [Vector3.ZERO], [Vector3(NAN,0,0), Vector3.ZERO, "bad", Vector3(1,0,0), Vector3(INF,0,0)]])
	check(c._routes.b.size() == 1 and c._routes.b[0].size() == 2, "malformed route inputs sanitized")
	finite_state(c, "sanitized routes")
	# All route points remain visible but use far LOD: movement must freeze.
	c.set_context("a", Vector3(0,0,-32))
	c.advance(0.1)
	var before: Vector3 = item.node.position
	var updates: int = c.get_stats().updates
	for frame in 20:
		c.advance(0.1)
	check(item.node.position == before and item.lod == 2, "far LOD freezes movement")
	check(c.get_stats().updates - updates <= 2 * c._pool.size(), "far updates capped at 1 Hz")
	c.set_context("a", Vector3(0,0,-100))
	updates = c.get_stats().updates
	c.advance(0.1)
	check(c.get_stats().active == 0 and c.get_stats().updates == updates, "outside radius sleeps")
	c.set_context("a", Vector3.ZERO)
	c.advance(0.1)
	check(c.get_stats().active == 18, "viewer reentry resumes")
	for zone in 100:
		c.set_routes("zone%d" % zone, [route])
	check(c._routes.size() == 32, "route zone cache hard cap")
	var long_route := PackedVector3Array()
	for point in 100:
		long_route.append(Vector3(point,0,0))
	var many: Array = []
	for index in 100:
		many.append(long_route)
	c.set_routes("a", many)
	check(c._routes.a.size() == Crowd.HARD_CAP and c._routes.a[0].size() == 64, "route and point caps")
	c.set_density("Low")
	for frame in 51:
		c.observe_frame_time(0.1)
	check(c._adaptive_cap == 2, "sustained slow reduces cap")
	for frame in 1800:
		c.observe_frame_time(1.0/60.0)
	check(c._adaptive_cap == 2, "recovery waits thirty seconds")
	c.observe_frame_time(1.0/60.0)
	check(c._adaptive_cap == 3, "recovery adds one")
	check(c.find_children("*", "CollisionObject3D", true, false).is_empty(), "visuals have no collision authority")
	source_dependencies(c)
	finite_state(c, "final")
	c.free()
	print("NPC_BUDGET assertions=%d failures=%d" % [assertions, failures])
	quit(1 if failures else 0)
