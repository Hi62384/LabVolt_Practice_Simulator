extends RefCounted
## Groups share one real circuit and assignment. Each student retains their answers.
static func allocate(identities: Array, bench_count: int = 3) -> Dictionary:
	var tokens := identities.duplicate()
	tokens.sort()
	var result := {}
	for i in range(mini(8,tokens.size())):
		result[tokens[i]]={"bench":i%maxi(1,bench_count),"group":i%maxi(1,bench_count),"individual":true}
	return result

static func permits(allocation: Dictionary, token: String, bench: int) -> bool:
	return allocation.has(token) and int(allocation[token].bench)==bench
