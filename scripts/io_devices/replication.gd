extends RefCounted
## Transport-independent host-only publication. Caller uses existing authority RPC.
## Bounded fields; no framebuffer is emitted when unchanged. A full() is for late join.
static func public_state(kind: String,state: Dictionary) -> Dictionary:
	if preload("res://scripts/commercial_devices/catalog.gd").supports(kind):return preload("res://scripts/commercial_devices/publication.gd").public_state(kind,state)
	var out := {"control":state.get("control",{}).duplicate(true)}
	match kind:
		"io_pixels","io_graphic":
			out.powered=bool(state.get("powered",false))
			var field := "pixels" if kind=="io_pixels" else "cells"
			out[field]=state.get(field,[]).duplicate()
		"io_rgb","io_bar","io_matrix":out.levels=state.get("levels",[]).duplicate()
		"io_motor","io_vibration":
			out.angle=float(state.get("angle",0));out.omega=float(state.get("omega",0));out.force=float(state.get("force",0))
		"io_servo":out.angle=float(state.get("angle",90));out.powered=bool(state.get("powered",false));out.signal_valid=bool(state.get("signal_valid",false))
		"io_relay":out.closed=bool(state.get("closed",false))
		"io_bridge":out.powered=bool(state.get("powered",false))
	return out

static func delta(previous: Dictionary,current: Dictionary) -> Dictionary:
	var changed := {};var removed: Array=[]
	for id in current:
		if not previous.has(id) or previous[id]!=current[id]:changed[id]=current[id].duplicate(true)
	for id in previous:
		if not current.has(id):removed.append(id)
	return {"changed":changed,"removed":removed}

static func apply_delta(previous: Dictionary,packet: Dictionary) -> Dictionary:
	var out := previous.duplicate(true)
	for id in packet.get("removed",[]):out.erase(id)
	for id in packet.get("changed",{}):out[id]=packet.changed[id].duplicate(true)
	return out
