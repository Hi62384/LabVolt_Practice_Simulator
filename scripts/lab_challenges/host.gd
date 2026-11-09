extends RefCounted
signal changed
signal notice(peer: int,bench: int,message: String)
const Catalog = preload("res://scripts/lab_challenges/scenario_catalog.gd")
const Objectives = preload("res://scripts/lab_challenges/objectives.gd")
const Decor = preload("res://scripts/lab_challenges/decorations.gd")
var store := preload("res://scripts/lab_challenges/ledger_adapter.gd").new()
var public_ids := preload("res://scripts/campus/social/public_identity.gd").new()
var needs_resume := {}
var labs: Array=[]
var allowed := Callable() # authenticated peer, bench, command -> host reach/class permission
var names := Callable()
var clock := Callable()
func now() -> int:return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())
func recover_journal() -> void:
	needs_resume.clear()
	for key in store.root().get("active",{}):needs_resume[int(key)]=true
func available(peer: int, bench: int, command: String) -> bool:
	return store.available() and peer in store.ledger.bindings and bench>=0 and bench<mini(3,labs.size()) and allowed.is_valid() and bool(allowed.call(peer,bench,command))
func guard(_peer: int,bench: int,action: Dictionary) -> String:
	var root := store.root()
	if not root.is_empty() and root.active.has(str(bench)) and str(action.get("op","")) in ["configure","reset","submit"]:return "Use the dedicated team challenge controls for this attempt."
	return ""
func act(peer: int,bench: int,request: Dictionary) -> Dictionary:
	var command := str(request.get("command",""))
	if not available(peer,bench,command):return _fail("Challenge access unavailable.")
	if request.keys().any(func(key):return key not in ["command","attempt_id","kind","seed","anchor","decoration","diagnosis"]):return _fail("Unknown team request field.")
	if var_to_bytes(request).size()>2048:return _fail("Challenge request too large.")
	var root := store.root()
	if root.is_empty():return _fail("Challenge journal is corrupt or unavailable.")
	if command=="start":return _start(peer,bench,request,root)
	if command=="decorate":return _decorate(peer,bench,request,root)
	var attempt: Dictionary=root.active.get(str(bench),{})
	var identity: String=store.ledger.bindings[peer]
	if attempt.is_empty() or str(request.get("attempt_id",""))!=attempt.id or identity not in attempt.participants:return _fail("Stale or unauthorized team attempt.")
	if command=="abandon":
		if peer!=1:return _fail("Only the host can end this team attempt.")
		attempt.outcome="abandoned";attempt.completed_at=now();root.history.append(attempt.duplicate(true));root.active.erase(str(bench))
		while root.history.size()>200:root.history.pop_front()
		var saved := _saved(root,"Team attempt ended without a reward.")
		if saved.ok and not needs_resume.get(bench,false):labs[bench].powered=false;labs[bench].mode="Free Laboratory";labs[bench].revision+=1;labs[bench].recalculate()
		if saved.ok:needs_resume.erase(bench)
		return saved
	var plan := Catalog.generate(attempt.kind,int(attempt.seed))
	if command=="resume":
		if peer!=1:return _fail("Only the host can restore the challenge circuit.")
		for token in attempt.participants:
			if token not in store.ledger.bindings.values() or not available(int(store.ledger.bindings.find_key(token)),bench,"resume"):return _fail("Wait for all original participants to reconnect, or abandon this attempt.")
		var error := Catalog.setup_error(labs[bench],plan)
		if error!="":return _fail(error)
		attempt.evidence={};attempt.diagnosis="";attempt.diagnosed_by=""
		if not store.commit(root):return _fail("Host save failed.")
		Catalog.install(labs[bench],plan);needs_resume[bench]=false;changed.emit();return {"ok":true,"message":"Same attempt restored; gather fresh physical evidence."}
	if needs_resume.get(bench,false):return _fail("The host must restore this journaled attempt before continuing.")
	if command=="diagnose":
		if not attempt.evidence.values().any(func(value):return value.get("measure_fault",false)):return _fail("Record actual instrument readings of the fault before diagnosing.")
		if str(request.get("diagnosis",""))!=plan.diagnosis:return _fail("The recorded electrical evidence does not support that diagnosis.")
		if attempt.diagnosis==plan.diagnosis:return {"ok":true,"message":"Diagnosis already recorded."}
		attempt.diagnosis=plan.diagnosis;attempt.diagnosed_by=identity;return _saved(root,"Diagnosis supported by the host's fault evidence.")
	if command!="submit":return _fail("Unknown team command.")
	if attempt.diagnosis!=plan.diagnosis:return _fail("Diagnose the original measured fault first.")
	for token in attempt.participants:
		var role: String=attempt.roles[token];var evidence: Dictionary=attempt.evidence.get(token,{})
		if not evidence.get(role,false):return _fail("Each assigned role must contribute real electrical work: "+role)
	var result := Objectives.evaluate(labs[bench],plan)
	if not result.ok:return {"ok":false,"error":" ".join(result.failures)}
	if store.ledger.creative:return _fail("Scored team rewards are unavailable in Creative Mode.")
	var committed := store.complete(bench,attempt.id,result.measurements,now())
	if committed.ok:labs[bench].mode="Free Laboratory";labs[bench].revision+=1;changed.emit()
	return {"ok":committed.ok,"message":"Team completion saved." if committed.ok else "","error":committed.get("error","")}
func _start(peer: int,bench: int,request: Dictionary,root: Dictionary) -> Dictionary:
	if peer!=1 or store.ledger.creative:return _fail("Only the host can start a scored team challenge outside Creative Mode.")
	if root.active.has(str(bench)):return _fail("End or resume the current team attempt first.")
	if not request.get("seed") is int or request.seed<0 or request.seed>2147483647:return _fail("Invalid challenge seed.")
	var plan := Catalog.generate(str(request.get("kind","")),int(request.seed))
	var error := Catalog.setup_error(labs[bench],plan)
	if error!="":return _fail(error)
	var members: Array=[];var role_map := {};var display_names := {}
	var peers: Array=store.ledger.bindings.keys();peers.sort()
	for connected in peers:
		if not available(int(connected),bench,"start"):continue
		var identity: String=store.ledger.bindings[connected]
		if root.active.values().any(func(attempt):return identity in attempt.participants):continue
		if not store.ledger.state.accounts[identity].profile.get("pending_trade",{}).is_empty():continue
		members.append(identity)
		role_map[identity]="repair" if members.size()==1 else "verify" if members.size()==3 else "measure_final"
		display_names[identity]=preload("res://scripts/campus/social/public_profiles.gd").clean_name(str(names.call(connected)) if names.is_valid() else "Student")
	if members.size()<2 or members.size()>8 or store.ledger.bindings[1] not in members:return _fail("Bring 2–8 authenticated participants to this bench.")
	var sequence: int=root.next_sequence
	root.next_sequence+=1
	var attempt := {"id":"labteam:"+str(root.epoch)+":"+str(sequence),"sequence":sequence,"bench":bench,"kind":plan.kind,"seed":plan.seed,"difficulty":plan.difficulty,"participants":members,"roles":role_map,"names":display_names,"evidence":{},"diagnosis":"","diagnosed_by":"","began_at":now()}
	root.active[str(bench)]=attempt
	if not store.commit(root):return _fail("Host save failed; circuit was not changed.")
	Catalog.install(labs[bench],plan);needs_resume[bench]=false;changed.emit();return {"ok":true,"attempt_id":attempt.id}
func observe(peer: int,bench: int,action: Dictionary,before: Dictionary) -> void:
	if needs_resume.get(bench,false) or not available(peer,bench,"observe"):return
	var root := store.root();var attempt: Dictionary=root.get("active",{}).get(str(bench),{})
	var identity: String=store.ledger.bindings[peer]
	if attempt.is_empty() or identity not in attempt.participants:return
	var plan := Catalog.generate(attempt.kind,int(attempt.seed));var state: Object=labs[bench]
	var baseline := Catalog.baseline_error(state)
	if not baseline.is_empty():
		needs_resume[bench]=true;notice.emit(peer,bench,baseline);return
	var after: Dictionary=state.snapshot()
	var evidence: Dictionary=attempt.evidence.get(identity,{}).duplicate(true);var previous := evidence.duplicate(true)
	var op := str(action.get("op",""))
	if op in ["plug","unplug","switch","undo","return"] and not before.powered and not state.powered and Objectives.fault_present(before,plan) and not Objectives.fault_present(after,plan):evidence.repair=true
	if op=="check" and not bool(before.checked) and state.checked and not Objectives.fault_present(after,plan):evidence.verify=true
	if op=="record" and Objectives.meaningful_measurement(state):
		if Objectives.fault_present(after,plan):evidence.measure_fault=true
		elif Objectives.evaluate(state,plan).ok:evidence.measure_final=true
	if evidence!=previous:
		attempt.evidence[identity]=evidence
		if store.commit(root):changed.emit()
		else:notice.emit(peer,bench,"The electrical action occurred, but the host could not save team proof. Restore/repeat that role after the save problem is resolved.")
func _decorate(peer: int,bench: int,request: Dictionary,root: Dictionary) -> Dictionary:
	var anchor := str(request.get("anchor",""));var id := str(request.get("decoration",""));var identity: String=store.ledger.bindings[peer]
	if not Decor.ANCHORS.has(anchor) or (not id.is_empty() and id not in Decor.unlocks(root.progress.get(identity,{}))):return _fail("Decoration or fixed anchor is unavailable.")
	var choices: Dictionary=root.decorations.get(str(bench),{}).duplicate(true)
	if choices.has(anchor) and choices[anchor].owner!=identity and peer!=1:return _fail("This anchor belongs to another participant; the host can clear it.")
	if id.is_empty() and not choices.has(anchor):return {"ok":true,"message":"Mount already clear."}
	if choices.get(anchor,{})=={"id":id,"owner":identity}:return {"ok":true,"message":"Decoration already selected."}
	if id.is_empty():choices.erase(anchor)
	else:choices[anchor]={"id":id,"owner":identity}
	root.decorations[str(bench)]=choices;return _saved(root,"Cosmetic decoration selection saved.")
func view(peer: int,bench: int,history_offset := 0) -> Dictionary:
	if not available(peer,bench,"view"):return {}
	var root := store.root();var identity: String=store.ledger.bindings[peer]
	var result := {"catalog":Catalog.catalog(),"active":{},"history":[],"history_total":0,"history_offset":clampi(history_offset,0,199),"unlocks":Decor.unlocks(root.get("progress",{}).get(identity,{})),"decorations":{}}
	if root.is_empty():return result
	var active: Dictionary=root.active.get(str(bench),{})
	if not active.is_empty():result.active=_public(active);result.active.needs_resume=bool(needs_resume.get(bench,false))
	var matching: Array=root.history.filter(func(record):return identity in record.participants)
	result.history_total=matching.size()
	var end := maxi(0,matching.size()-int(result.history_offset))
	for record in matching.slice(maxi(0,end-20),end):result.history.append(_public(record))
	for anchor in root.decorations.get(str(bench),{}):result.decorations[anchor]={"id":root.decorations[str(bench)][anchor].id}
	return result
func _public(attempt: Dictionary) -> Dictionary:
	var result := {"id":attempt.id,"kind":attempt.kind,"seed":attempt.seed,"bench":attempt.bench,"outcome":attempt.get("outcome","active"),"participants":[],"diagnosed":not str(attempt.get("diagnosis","")).is_empty(),"measurements":attempt.get("measurements",{}).duplicate(true),"completed_at":attempt.get("completed_at",0),"objective":Catalog.brief(Catalog.generate(attempt.kind,int(attempt.seed)))}
	for identity in attempt.participants:result.participants.append({"id":public_ids.public_id(identity),"name":attempt.names.get(identity,"Student"),"role":attempt.roles[identity],"evidence":attempt.evidence.get(identity,{}).duplicate(true)})
	return result
func _saved(root: Dictionary,message: String) -> Dictionary:
	if not store.commit(root):return _fail("Host save failed.")
	changed.emit();return {"ok":true,"message":message}
func _fail(message: String) -> Dictionary:return {"ok":false,"error":message}
