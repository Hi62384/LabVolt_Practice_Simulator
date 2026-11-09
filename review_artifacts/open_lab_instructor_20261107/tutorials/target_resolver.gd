extends RefCounted
## Resolve an existing target for HUD projection; never attach a node to equipment.
static func world_point(lab_id: String,cue: String,ac_positions: Dictionary,dc_fixture: Node) -> Variant:
	if lab_id=="ac_lab":return ac_positions.get(cue,null)
	if lab_id!="dc_lab" or not is_instance_valid(dc_fixture):return null
	if dc_fixture.physical.control_mounts.has(cue):return dc_fixture.physical.control_mounts[cue].global_position
	if dc_fixture.physical.display_mounts.has(cue):return dc_fixture.physical.display_mounts[cue].global_position
	if dc_fixture.binding.sockets.openings.has(cue):return dc_fixture.binding.sockets.anchor(cue).origin
	var devices := {"psu":"psu","meter":"meter","generator":"generator","scope_trace":"scope","scope":"scope"}
	if devices.has(cue):return dc_fixture.physical.get_node(devices[cue]).global_position
	return null
