extends SceneTree
const Budget = preload("res://scripts/campus/performance/equipment_budget.gd")
const Interest = preload("res://scripts/campus/performance/zone_interest.gd")
const Probe = preload("res://scripts/campus/performance/frame_probe.gd")
const Crowd = preload("res://scripts/campus/npcs/local_crowd.gd")
const Readout = preload("res://scripts/campus/performance/readout_adapter.gd")
const Routes = preload("res://scripts/campus/npcs/hallway_routes.gd")
const Router = preload("res://scripts/campus/performance/snapshot_router.gd")
class RegistryStub extends RefCounted:
	var data := {"corridor":{"x_min":10,"x_max":16,"z_min":-4,"z_max":68},"stairs":{"z_min":50}}
	func locate(_point: Vector3) -> String:
		return "test_hall"
	func search(_query: String) -> Array:
		return [{"anchor":[0,0,0]}]
var failures := 0
var assertions := 0

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	assertions += 1
	if not condition:
		failures += 1
		printerr("FAIL: " + message)

func run() -> void:
	var budget := Budget.new()
	var calls := [0]
	budget.register_display("meter", func(): calls[0] += 1, 10.0)
	check(budget.tick(0.0) == 1 and calls[0] == 1, "initial dirty display refreshes")
	check(budget.tick(1.0) == 0, "unchanged display performs no work")
	budget.mark_dirty("meter")
	budget.set_relevant("meter", false)
	check(budget.tick(1.0) == 0, "hidden display sleeps")
	budget.set_relevant("meter", true)
	check(budget.tick(0.0) == 1, "reentry refreshes latest dirty value")
	budget.mark_dirty("meter")
	check(budget.tick(0.01) == 0, "display refresh is rate limited")
	check(budget.tick(0.1) == 1, "dirty value eventually refreshes")
	budget.register_display("remove", func(): budget.unregister_display("remove"))
	check(budget.tick(1.0) == 1, "callback may unregister safely")
	budget.register_display("again", func(): budget.mark_dirty("again"))
	budget.tick(1.0)
	check(budget.tick(1.0) == 1, "callback may redirty without lost update")
	budget.unregister_display("again")
	var readout := Readout.new()
	var label := Label3D.new()
	readout.observe("supply", {"result":{"drop":{"s0":12.0},"i":{"s0":-0.2},"mode":{"s0":"CV"}}}, label)
	check(readout.tick(1.0) == 1 and "12.00 V" in label.text and "0.200 A" in label.text, "readout preserves authoritative meter values and current sign")
	var refreshed: int = readout.budget.refreshed
	readout.observe("supply", {"result":{"drop":{"s0":12.0},"i":{"s0":-0.2},"mode":{"s0":"CV"}}}, label)
	readout.tick(1.0)
	check(readout.budget.refreshed == refreshed, "unchanged instrument values avoid formatting work")
	label.free()
	readout.clear()
	var stub := RegistryStub.new()
	var hallways: Dictionary = Routes.from_registry(stub)
	check(hallways.has("test_hall"), "routes consume registry-returned zone ID")
	check(hallways.test_hall[0][1].z < 50, "hallway crowd route avoids staircase landing")
	var interest := Interest.new()
	var peer := {"id": 2, "zone_id": "test_a", "position": Vector3.ZERO, "session_id": "class"}
	var object := {"zone_id": "test_b", "position": Vector3.ZERO}
	check(not interest.is_relevant(peer, object), "out-of-zone transient excluded")
	object.owner = 2
	check(interest.is_relevant(peer, object), "owner dependency retained")
	object.erase("owner")
	object.session_id = "class"
	check(interest.is_relevant(peer, object), "shared class timer retained across zones")
	object.erase("session_id")
	object.global = true
	check(interest.is_relevant(peer, object), "global event retained")
	object.erase("global")
	object.zone_id = "test_a"
	object.position = Vector3(100, 0, 0)
	check(not interest.is_relevant(peer, object), "distance excludes remote motion")
	object.dependencies = [2]
	check(interest.is_relevant(peer, object), "gameplay dependency overrides distance")
	check(interest.is_relevant({}, {}), "missing metadata preserves legacy visibility")
	check(not interest.is_relevant({"building":"one"}, {"building":"two"}), "known unrelated building excluded")
	check(interest.recipients({2: peer, 3: {"zone_id": "test_b"}}, {"zone_id": "test_b"}) == [3], "recipient IDs preserved")
	var router := Router.new()
	var objects := {"bench":{"meta":{"zone_id":"test_a"},"state":{"voltage":12.0,"powered":true}},"gym":{"meta":{"zone_id":"test_b"},"state":{"animation":"curl"}}}
	var initial: Dictionary = router.build_patch(2, peer, objects)
	check(initial.updates.has("bench") and not initial.updates.has("gym"), "router sends only interested object state")
	check(router.build_patch(2, peer, objects).updates.is_empty(), "unchanged object produces no state delta")
	objects.bench.state.voltage = 13.0
	var changed: Dictionary = router.build_patch(2, peer, objects)
	check(changed.updates.bench == {"voltage":13.0}, "only changed field transmitted")
	var away: Dictionary = router.build_patch(2, {"zone_id":"test_b"}, objects)
	check("bench" in away.left_interest and away.updates.has("gym"), "zone transition retires old object baseline")
	var reentry: Dictionary = router.build_patch(2, peer, objects)
	check(reentry.updates.bench == objects.bench.state, "reentry sends full latest state without stale delta")
	objects.bench.state.erase("powered")
	check(router.build_patch(2, peer, objects).removed_fields.bench == ["powered"], "field deletion explicitly signaled")
	for id in range(1, 9):
		check(router.build_patch(id, {"zone_id":"test_a"}, objects, true).updates.has("bench"), "eight independent peer baselines %d" % id)
	router.forget_peer(2)
	check(not router._previous.has(2), "disconnect retires peer cache")
	var probe := Probe.new()
	probe.enabled = false
	probe.max_samples = 100
	for i in 99:
		probe.record_frame(0.01)
	probe.record_frame(0.1)
	var report := probe.report()
	check(is_equal_approx(report.one_percent_low_fps, 10.0), "1% low uses worst tail mean")
	check(is_equal_approx(report.average_fps, 1000.0 / 10.9), "mean FPS derived from frame intervals")
	probe.record_frame(NAN)
	check(probe.frames.size() == 100, "invalid frame ignored and sample cap maintained")
	probe.add_network_bytes(100, 200)
	check(probe.report().network_payload_sent == 100, "explicit payload accounting")
	probe.free()
	var crowd := Crowd.new()
	crowd.allow_headless = true
	root.add_child(crowd)
	crowd.set_process(false)
	crowd.set_density("High")
	crowd.set_context("test_a", Vector3.ZERO)
	check(crowd._desired() == 0, "no invented routes or unregistered-zone spawning")
	crowd.set_routes("test_a", [PackedVector3Array([Vector3.ZERO, Vector3(5, 0, 0)])])
	check(crowd._desired() == 18, "high preset target")
	crowd.observe_frame_time(0.2)
	check(crowd.get_stats().adaptive_cap == 18, "single spike never changes density")
	for i in 151:
		crowd.observe_frame_time(0.034)
	check(crowd.get_stats().adaptive_cap == 16, "sustained pressure reduces density")
	crowd.set_density("High")
	check(crowd.get_stats().adaptive_cap == 16, "reapplying unchanged graphics option preserves adaptive reduction")
	for i in 1900:
		crowd.observe_frame_time(0.016)
	check(crowd.get_stats().adaptive_cap == 17, "recovery is slow and gradual")
	# Manual advancement checks geometry and reuse without a rendered stress run.
	crowd.auto_density = false
	crowd.set_density("Low")
	check(crowd.prewarm(), "source-baked shared meshes load")
	for i in 30:
		crowd.advance(0.1)
	check(crowd.get_stats().active == 4, "low density creates four active visuals")
	check(crowd.get_stats().templates == 2, "shared full and reduced mesh templates")
	check(crowd._meshes[0].get_surface_count() == 1, "full character merged into one draw surface")
	check(crowd._meshes[1].surface_get_array_len(0) < crowd._meshes[0].surface_get_array_len(0), "medium LOD reduces geometry")
	check(crowd.find_children("*", "CollisionObject3D", true, false).is_empty(), "decorative students never block players")
	var instance: int = crowd._pool[0].node.get_instance_id()
	var before: Vector3 = crowd._pool[0].node.position
	for i in 10:
		crowd.advance(0.1)
	check(crowd._pool[0].node.position.distance_to(before) > 0.1, "cached route advances visual")
	crowd.set_density("High")
	for i in 60:
		crowd.advance(0.1)
	check(crowd.get_stats().pooled == 18 and crowd.get_stats().pooled <= Crowd.HARD_CAP, "high density stays within hard cap")
	crowd.set_density("Off")
	check(crowd.get_stats().active == 0, "Off immediately hides pooled students")
	crowd.set_density("Low")
	crowd.set_context("test_a", Vector3(0, 0, -32))
	var distant_before: Vector3 = crowd._pool[0].node.position
	for i in 20:
		crowd.advance(0.1)
	check(crowd._pool[0].node.position == distant_before, "distant visual freezes movement")
	crowd.set_context("test_a", Vector3.ZERO)
	crowd.set_context("test_b", Vector3.ZERO)
	check(crowd.get_stats().active == 0, "out-of-zone students sleep")
	crowd.set_context("test_a", Vector3.ZERO)
	crowd.advance(0.1)
	check(crowd._pool[0].node.get_instance_id() == instance, "zone return reuses pool")
	crowd.disable("test fallback")
	check(crowd.get_stats().active == 0, "graceful disable hides all students immediately")
	check(crowd.get_stats().network_messages == 0, "crowds generate no network messages")
	print("CROWD TEST SAMPLE " + JSON.stringify(crowd.get_stats()))
	crowd.free()
	print("PERFORMANCE UNIT: %d assertions, %d failures" % [assertions, failures])
	quit(1 if failures else 0)
