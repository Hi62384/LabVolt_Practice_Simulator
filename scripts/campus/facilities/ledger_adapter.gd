extends RefCounted
signal committed(identity: String)
## Preferred multiplayer adapter: one existing host-ledger commit for dollars and gym/food.
const Rules=preload("res://scripts/campus/facilities/facility_host.gd")
var ledger: RefCounted
var is_authority := Callable()

func load_facilities(identity: String) -> Dictionary:
	if not available(identity):return {}
	var account: Dictionary=ledger.state.accounts[identity]
	# This marker lives outside imported profile data and cannot arrive through metadata.
	if not bool(account.get("facilities_authority",false)):return Rules.empty_profile()
	return account.profile.get("facilities",Rules.empty_profile()).duplicate(true)

func available(identity: String) -> bool:
	return is_authority.is_valid() and bool(is_authority.call()) and ledger!=null and ledger.state.accounts.has(identity) and identity in ledger.bindings.values()

func commit(identity: String, dollar_delta: int, facilities: Dictionary) -> bool:
	if not available(identity) or dollar_delta>0 or dollar_delta < -10000 or not Rules.valid_profile(facilities):return false
	var account: Dictionary=ledger.state.accounts[identity]
	var old: Dictionary=load_facilities(identity)
	if not Rules.valid_profile(old) or int(facilities.revision)!=int(old.revision)+1 or int(facilities.last_sequence)!=int(old.last_sequence)+1:return false
	if not account.profile.get("pending_trade",{}).is_empty():return false
	var debit := preload("res://scripts/economy/temporary_playtest/policy.gd").purchase_debit(account.profile.dollars,-dollar_delta,true)
	if not debit.ok:return false
	var next: Dictionary=ledger.state.duplicate(true)
	next.accounts[identity].profile.dollars=debit.next_balance
	next.accounts[identity].profile.facilities=facilities.duplicate(true)
	next.accounts[identity].facilities_authority=true
	next.accounts[identity].revision+=1
	if not bool(ledger.persist(next)):return false
	committed.emit(identity)
	return true
