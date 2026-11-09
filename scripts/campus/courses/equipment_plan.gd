extends RefCounted
## Concrete catalog plan for the host to issue inventory/equipment. This is a
## construction aid, not an alternate solver or permission to auto-complete work.
const Catalog = preload("res://scripts/electronics_catalog.gd")
static func for_assignment(assignment: Dictionary) -> Dictionary:
	if assignment.get("course_id","")!="ETY155":return {"ok":false,"error":"Use AC lab-bank equipment adapter"}
	var catalog := Catalog.all();var items := {};var devices: Array=[];var missing: Array=[]
	var parts: Array=assignment.get("reference_parts",[])
	for p in parts:
		if int(assignment.week)==3 and p.id in ["R1","R2"]:continue
		if p.kind=="V":devices.append({"reference_id":p.id,"equipment":"isolated_adjustable_dc_channel","setpoint_volts":absf(float(p.value)),"reverse_leads":float(p.value)<0,"positive_node":p.a,"negative_node":p.b});continue
		if p.kind=="I":
			var source_index := devices.filter(func(device):return device.get("equipment","")=="adjustable_current_source").size()
			if source_index>=4:missing.append("More than four current-source instances")
			var suffix := "" if source_index==0 else str(source_index+1)
			devices.append({"reference_id":p.id,"equipment":"adjustable_current_source","source_index":source_index,"hardware_index":source_index,"positive_terminal":"IS"+suffix+"+","negative_terminal":"IS"+suffix+"-","instructions":"Connect minus to node a and plus to node b for the requested a-to-b current arrow.","setpoint_amperes":float(p.value),"current_direction":"a_to_b","a":p.a,"b":p.b,"positive_node":p.b,"negative_node":p.a,"compliance_volts":30.0});continue
		var found := ""
		if int(assignment.week)==2 and p.id=="R1":
			var parameters: Dictionary=assignment.get("scenario",{})
			var physical := "r%d_t%d_w%d"%[int(p.value),int(float(parameters.get("tolerance",0.05))*100),int(float(parameters.get("rating_watts",0.25))*100)]
			if catalog.has(physical):found=physical
		for key in catalog:
			if found!="":break
			if catalog[key].get("kind","")=="R" and absf(float(catalog[key].value)-float(p.value))<1e-8:found=key;break
		if found!="":items[found]=int(items.get(found,0))+1;devices.append({"reference_id":p.id,"catalog_id":found,"a":p.a,"b":p.b});continue
		if p.kind=="R" and float(p.value)>0.01 and float(p.value)<10000.0:
			items.pot10k=int(items.get("pot10k",0))+1
			devices.append({"reference_id":p.id,"catalog_id":"pot10k","expanded_id_suffix":"/upper","setting":float(p.value)/10000.0,"end_a":p.a,"wiper":p.b,"end_b":"isolated unused end; do not join it to another node"})
		else:missing.append("Unsupported component "+str(p.id))
	if int(assignment.week)==3:
		items.pot10k=int(items.get("pot10k",0))+1
		devices.append({"catalog_id":"pot10k","reference_ids":{"R1":"/upper","R2":"/lower"},"setting":float(parts[1].value)/10000.0,"end_a":"p","wiper":"w","end_b":"g"})
	return {"ok":missing.is_empty(),"catalog_counts":items,"devices":devices,"missing_capabilities":missing,"workflow":"Host issues or reserves these real parts. Student constructs; host captures netlist and meter/procedure events. Never copy reference_result into measurements."}
