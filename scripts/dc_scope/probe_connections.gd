extends RefCounted
# Physical lead diagnostics, not a circuit solver. Shared-reference inputs remain
# the existing S1/GND and S2/GND 1 MΩ circuit elements.
static func describe(leads: Array, externally_linked := false) -> Dictionary:
	var used := {"S1":false,"S2":false,"GND":false}
	for wire in leads:
		if not wire is Array or wire.size()!=2 or wire[0]==wire[1]: continue
		for port in wire:
			if used.has(str(port)): used[str(port)]=true
	var warning := ""
	if not used.GND: warning="Verify common return through inter-bench leads" if externally_linked else "GND reference has no lead; connect it to the circuit return"
	return {"shared_reference":"GND","differential":false,"reference_connected":used.GND,"external_reference_possible":externally_linked,"signal_connected":[used.S1,used.S2],"warning":warning}
