extends SceneTree
const Core = preload("res://scripts/economy/temporary_playtest/policy_core.gd")
const Policy = preload("res://scripts/economy/temporary_playtest/policy.gd")
var checks := 0

func expect(value: bool, message: String) -> void:
	checks += 1
	if not value:
		push_error(message)
		quit(1)

func _init() -> void:
	var enabled := Core.new(true, true)
	var disabled := Core.new(false, false)
	var funded := enabled.purchase_debit(7, 50, true)
	expect(funded.ok and funded.debit == 0 and funded.next_balance == 7, "enabled purchase preserves stored balance")
	var normal := disabled.purchase_debit(70, 50, true)
	expect(normal.ok and normal.debit == 50 and normal.next_balance == 20, "disabled purchase restores normal debit")
	expect(not disabled.purchase_debit(7, 50, true).ok, "disabled policy enforces insufficient funds")
	expect(not enabled.purchase_debit(7, 50, false).ok, "purchase requires authority")
	expect(not enabled.purchase_debit(7, -1, true).ok, "invalid authoritative price is rejected")
	var muted := enabled.earning_credit(7, 25, true)
	expect(muted.ok and muted.credit == 0 and muted.next_balance == 7, "enabled policy suppresses earning without changing balance")
	var credited := disabled.earning_credit(7, 25, true)
	expect(credited.ok and credited.credit == 25 and credited.next_balance == 32, "disabled policy restores earning")
	expect(not enabled.earning_credit(7, 25, false).ok, "earning requires authority")
	var display := Policy.display_snapshot(true)
	expect(display.ok and display.funds_text == "Unlimited", "authoritative UI snapshot uses unlimited semantics")
	transaction_pipeline_checks(enabled)
	print("PASS temporary playtest economy policy: ", checks, " checks")
	quit()

func transaction_pipeline_checks(policy: RefCounted) -> void:
	var state := {"dollars": 3, "owned": [], "receipts": {}}
	expect(not fake_purchase(state, policy, false, "tx-a", "valid", 5).ok, "untrusted caller cannot purchase")
	expect(not fake_purchase(state, policy, true, "tx-a", "missing", 5).ok, "unknown catalog item remains rejected")
	expect(not fake_purchase(state, policy, true, "tx-a", "valid", -5).ok, "invalid catalog price remains rejected")
	var bought := fake_purchase(state, policy, true, "tx-a", "valid", 5)
	expect(bought.ok and state.dollars == 3 and "valid" in state.owned, "authorized purchase grants ownership without debit")
	expect(not fake_purchase(state, policy, true, "tx-a", "valid", 5).ok, "replayed transaction remains rejected")
	expect(not fake_purchase(state, policy, true, "tx-b", "valid", 5).ok, "duplicate permanent purchase remains rejected")

func fake_purchase(state: Dictionary, policy: RefCounted, authority: bool, transaction_id: String, item_id: String, price: int) -> Dictionary:
	# This fixture demonstrates the required ordering: the policy is consulted only
	# after authority, receipt, catalog, price and ownership validation.
	if not authority:return {"ok": false}
	if state.receipts.has(transaction_id):return {"ok": false}
	if item_id != "valid" or price < 0:return {"ok": false}
	if item_id in state.owned:return {"ok": false}
	var decision: Dictionary = policy.purchase_debit(state.dollars, price, authority)
	if not decision.ok:return decision
	var before := state.duplicate(true)
	state.dollars = decision.next_balance
	state.owned.append(item_id)
	state.receipts[transaction_id] = true
	if state.owned.size() != before.owned.size() + 1:
		state = before
		return {"ok": false}
	return {"ok": true}
