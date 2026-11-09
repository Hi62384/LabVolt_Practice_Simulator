extends RefCounted
## Exact count/data extensions, not an expression parser.
static func median(sorted: Array) -> float:
	var n=sorted.size()
	if n==0:return NAN
	return float(sorted[n/2]) if n%2 else (float(sorted[n/2-1])+float(sorted[n/2]))/2.0
static func describe(data: Array) -> Dictionary:
	if data.size()<4 or data.size()>128:return {}
	var sorted=data.duplicate();sorted.sort()
	var total=0.0;var counts={}
	for v in sorted:
		total+=float(v);var key=str(v);counts[key]=int(counts.get(key,0))+1
	var half=int(sorted.size()/2);var lo=sorted.slice(0,half+sorted.size()%2);var hi=sorted.slice(half)
	var q1=median(lo);var q3=median(hi);var maximum=0;var modes=[]
	for key in counts:maximum=maxi(maximum,counts[key])
	if maximum>1:
		for key in counts:
			if counts[key]==maximum:modes.append(float(key))
	modes.sort()
	return {"mean":total/data.size(),"median":median(sorted),"q1":q1,"q3":q3,"iqr":q3-q1,"modes":modes,"counts":counts,"sorted":sorted,"convention":"Median of halves; include the central value in both halves when n is odd. No mode if every value occurs once."}
static func choose(n: int,k: int) -> int:
	if k<0 or k>n:return 0
	var out=1
	for i in range(1,mini(k,n-k)+1):out=int(out*(n-i+1)/i)
	return out
static func coin_count(n: int,k: int,at_least: bool) -> int:
	var out=0
	for heads in range(n+1):
		if (heads>=k if at_least else heads==k):out+=choose(n,heads)
	return out
static func dice_counts(n: int,threshold: int,condition: String) -> Dictionary:
	var sums={0:1}
	for _i in range(n):
		var next={}
		for total in sums:
			for face in range(1,7):next[total+face]=int(next.get(total+face,0))+sums[total]
		sums=next
	var count=0
	for total in sums:
		if (total==threshold if condition=="exactly" else total>=threshold):count+=sums[total]
	return {"favorable":count,"total":int(pow(6,n)),"distribution":sums}
static func card_counts(category: String,draws: int,replacement: bool) -> Dictionary:
	var eligible={"hearts":13,"red":26,"ace":4,"number card (2 through 10)":36}.get(category,0)
	if draws<1 or draws>4 or eligible==0:return {}
	var favorable=1;var total=1
	for i in range(draws):
		favorable*=eligible-(0 if replacement else i);total*=52-(0 if replacement else i)
	return {"favorable":favorable,"total":total}
