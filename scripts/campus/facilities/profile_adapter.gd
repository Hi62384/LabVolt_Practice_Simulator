extends RefCounted
## Bind ONLY authoritative ElectronicsProfile objects, never a client mirror.
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var profiles := {}
var is_authority := Callable()

func load_facilities(identity: String) -> Dictionary:
	if not is_authority.is_valid() or not is_authority.call() or not profiles.has(identity):return {}
	var p: RefCounted=profiles[identity]
	return p.data.get("facilities",Rules.empty_profile()).duplicate(true)

func commit(identity: String, dollar_delta: int, facilities: Dictionary) -> bool:
	if not is_authority.is_valid() or not is_authority.call() or not profiles.has(identity):return false
	if dollar_delta>0 or dollar_delta < -10000 or not Rules.valid_profile(facilities):return false
	var p: RefCounted=profiles[identity]
	if p.authority_submit.is_valid() or not p.data.get("pending_trade",{}).is_empty():return false
	var old: Dictionary=p.data.get("facilities",Rules.empty_profile())
	if not Rules.valid_profile(old):return false
	if int(facilities.revision)!=int(old.revision)+1 or int(facilities.last_sequence)!=int(old.last_sequence)+1:return false
	var debit := preload("res://scripts/economy/temporary_playtest/policy.gd").purchase_debit(p.data.get("dollars",0),-dollar_delta,true)
	if not debit.ok:return false
	var before: Dictionary=p.data.duplicate(true)
	p.data.dollars=debit.next_balance
	p.data.facilities=facilities.duplicate(true)
	if p.save()!=OK:
		p.data=before
		return false
	return true
