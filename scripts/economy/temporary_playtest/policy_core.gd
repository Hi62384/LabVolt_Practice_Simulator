extends RefCounted
## Pure decision core for the temporary playtest economy.
##
## The enabled flag is authority-owned configuration. Never construct this from
## request data, profile data, RPC arguments, metadata, or a client setting.

var unlimited_purchases: bool
var suppress_earnings: bool

func _init(unlimited: bool, suppress: bool) -> void:
	unlimited_purchases = unlimited
	suppress_earnings = suppress

func purchase_debit(stored_balance: Variant, authoritative_price: Variant, authority_confirmed: bool) -> Dictionary:
	if not authority_confirmed:
		return _failure("Authority required")
	if not _whole_nonnegative(stored_balance) or not _whole_nonnegative(authoritative_price):
		return _failure("Invalid price or balance")
	var balance := int(stored_balance)
	var price := int(authoritative_price)
	if not unlimited_purchases and balance < price:
		return _failure("Not enough dollars")
	return {
		"ok": true,
		"debit": 0 if unlimited_purchases else price,
		"next_balance": balance if unlimited_purchases else balance - price,
		"unlimited": unlimited_purchases,
	}

func earning_credit(stored_balance: Variant, authoritative_amount: Variant, authority_confirmed: bool) -> Dictionary:
	if not authority_confirmed:
		return _failure("Authority required")
	if not _whole_nonnegative(stored_balance) or not _whole_nonnegative(authoritative_amount):
		return _failure("Invalid reward or balance")
	var balance := int(stored_balance)
	var amount := int(authoritative_amount)
	if not suppress_earnings and balance > 1000000000 - amount:
		return _failure("Reward exceeds balance limit")
	return {
		"ok": true,
		"credit": 0 if suppress_earnings else amount,
		"next_balance": balance if suppress_earnings else balance + amount,
		"suppressed": suppress_earnings,
	}

func display_snapshot(authority_confirmed: bool) -> Dictionary:
	if not authority_confirmed:
		return _failure("Authority required")
	return {
		"ok": true,
		"funds_text": "Unlimited" if unlimited_purchases else "",
		"unlimited_purchases": unlimited_purchases,
		"earnings_suppressed": suppress_earnings,
	}

static func _whole_nonnegative(value: Variant) -> bool:
	# JSON profiles reload integer balances as floats.
	return (value is int or value is float) and value >= 0 and value <= 1000000000 and value == floor(float(value))

static func _failure(message: String) -> Dictionary:
	return {"ok": false, "error": message}
