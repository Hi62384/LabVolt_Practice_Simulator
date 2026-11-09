extends RefCounted
## Authoritative, server-wide policy for the current project playtest.
##
## This is deliberately source configuration, not a profile field or client
## option. Turning it off restores stored-balance behavior immediately; no save
## migration or cleanup is required because enabled mode never changes dollars.

const Core = preload("res://scripts/economy/temporary_playtest/policy_core.gd")
const UNLIMITED_PURCHASES := true
const SUPPRESS_EARNINGS := true

static func authority_policy() -> RefCounted:
	return Core.new(UNLIMITED_PURCHASES, SUPPRESS_EARNINGS)

static func purchase_debit(stored_balance: Variant, authoritative_price: Variant, authority_confirmed: bool) -> Dictionary:
	return authority_policy().purchase_debit(stored_balance, authoritative_price, authority_confirmed)

static func earning_credit(stored_balance: Variant, authoritative_amount: Variant, authority_confirmed: bool) -> Dictionary:
	return authority_policy().earning_credit(stored_balance, authoritative_amount, authority_confirmed)

static func display_snapshot(authority_confirmed: bool) -> Dictionary:
	return authority_policy().display_snapshot(authority_confirmed)
