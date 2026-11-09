extends RefCounted
## Rule-based finite-deck predicates. Numeric rank convention is explicit in prompts.
static func eligible(rule: Dictionary) -> int:
	var count=0
	for suit in range(4):
		for rank in range(1,14):
			var suit_ok=rule.suit_mode=="all" or suit==int(rule.suit) if rule.suit_mode!="colour" else int(suit/2)==int(rule.colour)
			var match_card=suit_ok and rank>=rule.low and rank<=rule.high
			if rule.complement:match_card=not match_card
			if match_card:count+=1
	return count
static func counts(rule: Dictionary,draws: int,replacement: bool) -> Dictionary:
	if draws<1 or draws>4:return {}
	var m=eligible(rule);var favorable=1;var total=1
	for i in range(draws):favorable*=m-(0 if replacement else i);total*=52-(0 if replacement else i)
	return {"favorable":favorable,"total":total}
static func description(rule: Dictionary) -> String:
	var suit_text="any suit" if rule.suit_mode=="all" else ["hearts","diamonds","clubs","spades"][int(rule.suit)] if rule.suit_mode=="suit" else ["red","black"][int(rule.colour)]
	var condition="%s AND rank from %d through %d inclusive"%[suit_text,rule.low,rule.high]
	return "NOT ("+condition+")" if rule.complement else "("+condition+")"
