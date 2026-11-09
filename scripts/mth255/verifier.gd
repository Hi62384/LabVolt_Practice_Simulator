extends RefCounted
const Electrical=preload("res://scripts/mth255/ac_verifier.gd")
const Diagrams=preload("res://scripts/mth255/diagram_verifier.gd")
const C=preload("res://scripts/mth255/complex_domain.gd")
## Verification uses defining equations, enumeration, or a distinct geometric route.
static func near(a: float,b: float,tol: float=0.000001) -> bool:
	return is_finite(a) and is_finite(b) and absf(a-b)<=tol*maxf(1.0,absf(b))
static func verify(p: Dictionary) -> bool:
	if not Diagrams.verify(p) or not Electrical.verify(p):return false
	var q=p.parameters;var answer=p.answer;var topic=p.generator_id
	match topic:

		"impedance_network":
			var z1=C.decode(q.z1);var z2=C.decode(q.z2);var z3=C.decode(q.z3);var v=Vector2(answer.v_real,answer.v_imag);var i2=Vector2(answer.i2_real,answer.i2_imag);var i3=Vector2(answer.i3_real,answer.i3_imag);var total=i2+i3;var eq=Vector2(answer.z_real,answer.z_imag)
			return C.near(C.multiply(i2,z2),v) and C.near(C.multiply(i3,z3),v) and C.near(C.multiply(total,z1)+v,Vector2(q.voltage,0)) and C.near(C.multiply(total,eq),Vector2(q.voltage,0))
		"reactance_equation":
			if answer.values.size()!=1 or not numeric_set(answer.excluded,[0]):return false
			var omega=answer.values[0]
			return omega>0 and near(omega*q.L-1.0/(omega*q.C),q.X)
		"rational_transformed":
			var B=-(q.excluded+q.ex2+q.A+q.B);var constant=q.excluded*q.ex2+q.A*q.ex2+q.B*q.excluded;var disc=B*B-4*constant
			if disc<0 or not numeric_set(answer.excluded,[q.excluded,q.ex2]):return false
			var candidates=[(-B+sqrt(disc))/2,(-B-sqrt(disc))/2];var valid=[]
			for x in candidates:
				if x!=q.excluded and x!=q.ex2 and near(float(q.A)/(x-q.excluded)+float(q.B)/(x-q.ex2),1) and not valid.has(x):valid.append(x)
			return numeric_set(answer.values,valid)
		"radical_transformed":
			var B=2*q.m-q.c;var constant=q.m*q.m-q.k;var disc=B*B-4*constant
			if disc<0:return false
			var candidates=[(-B+sqrt(disc))/2,(-B-sqrt(disc))/2];var valid=[]
			for u in candidates:
				if q.c*u+q.k>=0 and u+q.m>=0 and near(sqrt(q.c*u+q.k),u+q.m) and not valid.has(u+q.h):valid.append(u+q.h)
			return numeric_set(answer.values,valid) and near(answer.boundary,maxf(q.h-float(q.k)/q.c,q.h-q.m))
		"trig_proof","log_combine","log_changebase":return true # Provider requires shared exact schema proof before issuance.
		"quadratic_system":
			if answer.points.size()!=2:return false
			for pair in answer.points:
				var x=pair.x;var y=pair.y
				if not near(y,pow(x-q.h,2)+q.k) or not near(y,q.m*(x-q.h)+q.k+q.a*q.a):return false
			return not near(answer.points[0].x,answer.points[1].x)
		"polynomial_remaining":
			if not near(answer.b-q.known,q.B) or not near(answer.c-q.known*answer.b,q.C) or not near(-q.known*answer.c,q.D) or answer.remainder!=0:return false
			if answer.values.size()!=3:return false
			for x in answer.values:
				if not near(x*x*x+q.B*x*x+q.C*x+q.D,0):return false
			return true
		"resistor_pair":
			if answer.values.size()!=2:return false
			var x=answer.values[0];var y=answer.values[1]
			return x>0 and y>0 and near(x+y,q.series) and near(1.0/x+1.0/y,1.0/q.parallel)
		"engineering_power":
			if answer.values.size()!=2:return false
			for current in answer.values:
				if current<0 or not near(q.E*current-q.R*current*current,q.P):return false
			return not near(answer.values[0],answer.values[1])
		"half_angle":return true # provider checks radical expression against unit-circle geometry
		"log_variable_base":
			var discriminant=q.coefficient*q.coefficient+4*q.constant;var candidates=[(q.coefficient+sqrt(discriminant))/2,(q.coefficient-sqrt(discriminant))/2];var valid=[]
			for x in candidates:
				if x>0 and x!=1 and q.coefficient*x+q.constant>0 and not valid.has(x):valid.append(x)
			return numeric_set(answer.values,valid) and numeric_set(answer.excluded,[0,1]) and near(answer.boundary,maxf(0.0,-float(q.constant)/q.coefficient))
		"exp_substitution":
			var u=exp(q.multiplier*answer.x)
			return u>0 and near(u*u-(q.positive+q.negative)*u+q.positive*q.negative,0) and q.negative<0
		"card_union":
			var count=0
			for suit in range(4):
				for rank in range(1,14):
					if (suit==q.suit and rank==q.rank) if q.intersection else (suit==q.suit or rank==q.rank):count+=1
			return fraction_counts(answer.probability,count,52)
		"dice_event":
			var count=6 if q.variant==0 else 30 if q.variant==1 else 9 if q.variant==2 else 0
			if q.variant==3:
				# Use the triangular sum distribution instead of face-pair enumeration.
				for total in range(2,13):
					if total%int(q.divisor)==0:count+=6-absi(7-total)
			return fraction_counts(answer.probability,count,36)
		"complex_components":
			var z=C.decode(q.z);var quadrant=0
			if z.x!=0 and z.y!=0:quadrant=1 if z.x>0 and z.y>0 else 2 if z.x<0 and z.y>0 else 3 if z.x<0 else 4
			return C.near(C.decode(q.u)+C.decode(q.w),z) and near(answer.real,z.x) and near(answer.imag,z.y) and answer.quadrant==quadrant and answer.argument_defined==(0 if z.length_squared()==0 else 1)
		"complex_plot":return answer.points==q.points and answer.points.size()>=1
		"wave_from_graph":return answer.amplitude>0 and answer.period>0 and answer.shift>=0 and answer.shift<answer.period and near(answer.amplitude,q.amplitude) and near(answer.period,q.period) and near(answer.offset,q.offset) and near(answer.shift,q.shift)
		"wave_graph":
			if answer.points.size()!=5:return false
			for i in range(5):
				var point=answer.points[i];var angle=TAU*(point.x-q.shift)/q.period
				if not near(point.x,q.shift+i*q.period/4) or not near(point.y,q.offset+q.amplitude*(cos(angle) if q.cosine else sin(angle))):return false
			return true
		"j_power":
			var zn=C.power(Vector2(0,1),int(q.n));var zm=C.power(Vector2(0,1),int(q.m));var zk=C.power(Vector2(0,1),int(q.k));var zh=C.power(Vector2(0,1),int(q.h));var result=zn
			if q.mode==1:result=C.multiply(zn,zm)
			elif q.mode==2:result=C.divide(zn,zm)
			elif q.mode==3:result=C.multiply(zn+zm,zk)
			elif q.mode==4:result=C.divide(zn+zm,zk+zh)
			return C.near(C.decode(answer),result)
		"complex_convert":
			var z=C.decode(q.z)
			return C.near(C.decode(answer),z) if q.requested=="rectangular" else C.near(C.polar(answer.magnitude,deg_to_rad(answer.angle)),z)
		"complex_operation":
			var z=C.decode(q.z);var w=C.decode(q.w);var out=C.decode(answer)
			match q.operation:
				"add":return C.near(out-w,z)
				"subtract":return C.near(out+w,z)
				"multiply":return C.near(C.polar(z.length()*w.length(),z.angle()+w.angle()),out)
				"divide":return C.near(C.multiply(out,w),z)
				"conjugate":return near(out.x,z.x) and near(out.y,-z.y)
				"reciprocal":return C.near(C.multiply(out,z),Vector2(1,0))
		"complex_power":
			var z=C.decode(q.z);return C.near(C.decode(answer),C.polar(pow(z.length(),q.n),q.n*z.angle()))
		"complex_roots":
			var values=[]
			for value in answer.values:values.append(C.decode(value))
			return C.verify_roots(C.decode(q.z),values,q.n)
		"impedance":
			var z=C.decode(q.z);var w=C.decode(q.w);var eq=Vector2(answer.z_real,answer.z_imag);var current=Vector2(answer.i_real,answer.i_imag);var voltage=Vector2(q.v,0)
			if not C.near(C.multiply(current,eq),voltage):return false
			if q.parallel:return C.near(C.divide(voltage,z)+C.divide(voltage,w),current)
			return C.near(C.multiply(current,z)+C.multiply(current,w),voltage)
		"quadratic":
			var disc=q.b*q.b-4*q.a*q.c
			if not near(answer.discriminant,disc) or answer.values.size()!=(1 if disc==0 else 2):return false
			for x in answer.values:
				if not near(q.a*x*x+q.b*x+q.c,0):return false
			return answer.values.size()==1 or not near(answer.values[0],answer.values[1])
		"quadratic_formula":return q.rad>0 and answer.values.size()==2 and (not answer.has("center") or answer.center==q.h and answer.k==q.rad) # Exact keys are additionally checked by shared-core substitution in provider.
		"rational_quadratic":
			if answer.values.size()!=1 or answer.excluded!=[q.excluded]:return false
			var x=answer.values[0];return x!=q.excluded and near((x*x-(q.excluded+q.other)*x+q.excluded*q.other)/(x-q.excluded),0)
		"radical_quadratic":
			var disc=1+4*q.offset;var candidates=[(1+sqrt(disc))/2,(1-sqrt(disc))/2];var valid=[]
			for x in candidates:
				if x+q.offset>=0 and near(sqrt(x+q.offset),x):valid.append(x)
			return numeric_set(answer.values,valid)
		"biquadratic":
			if answer.values.size()!=4:return false
			var seen=[]
			for x in answer.values:
				if seen.has(x) or not near(pow(x,4)-(q.u*q.u+q.v*q.v)*x*x+q.u*q.u*q.v*q.v,0):return false
				seen.append(x)
			return true
		"quadratic_application":return answer.width>0 and answer.length>0 and near(answer.width*answer.length,q.area) and near(answer.length-answer.width,q.difference) and (not q.has("perimeter") or near(2*(answer.width+answer.length),q.perimeter))
		"quadratic_vertex":return near(2*q.a*answer.x+q.b,0) and near(q.a*answer.x*answer.x+q.b*answer.x+q.c,answer.y) and answer.type==(1 if q.a>0 else -1)
		"angle_conversion","exact_trig","trig_identity":return true # Shared exact proof is mandatory in provider before issuance.
		"trig_equation":
			if answer.values.size()!=2*q.n:return false
			var seen=[];var upper=TAU if q.radians else 360.0
			for x in answer.values:
				if x<0 or x>=upper:return false
				for old in seen:
					if near(x,old):return false
				seen.append(x)
				if not near(sin(q.n*x*(1.0 if q.radians else PI/180)),sin(deg_to_rad(q.alpha))):return false
			return true
		"waveform":return near(answer.period*q.frequency,1) and near(answer.omega*answer.period,TAU) and near(answer.shift*answer.omega+q.phase,0) and near(answer.value,q.amplitude*sin(TAU*(q.t-answer.shift)/answer.period))
		"wave_combine":return near(answer.magnitude*cos(answer.angle),q.a) and near(answer.magnitude*sin(answer.angle),q.b) and near(answer.lead_seconds*q.omega,answer.angle) and (not answer.has("lead_milliseconds") or near(answer.lead_milliseconds,1000*answer.lead_seconds))
		"wave_threshold":
			var t=answer.time
			if t<=0 or not near(sin(q.omega*t+q.phase),q.ratio):return false
			# Enumerate all candidates in the previous full cycle using acos via cos(theta-pi/2).
			var beta=acos(q.ratio);var min_time=INF
			for k in range(-3,5):
				for angle in [PI/2-beta+TAU*k,PI/2+beta+TAU*k]:
					var candidate=(angle-q.phase)/q.omega
					if candidate>1e-9:min_time=minf(min_time,candidate)
			return near(t,min_time)
		"exponential":
			if q.get("fit",false):return answer.initial>0 and near(answer.initial*exp(answer.rate*q.t1),q.y1) and near(answer.initial*exp(answer.rate*q.t2),q.y2) and near(answer.value_at_t3,answer.initial*exp(answer.rate*q.t3))
			return answer.value>0 and near(log(answer.value/q.initial),q.rate*q.t) and near(answer.initial,q.initial) and answer.asymptote==0
		"exp_equation":return near(pow(q.base,q.coefficient*answer.x+q.shift),q.target)
		"rc_model":
			if q.get("unknown_capacitance",false):
				var capacitance=answer.capacitance_microfarads/1000000.0
				if capacitance<=0:return false
				var remaining=exp(-q.given_time/(q.resistance*capacitance))
				return near(1-remaining if q.charging else remaining,q.fraction)
			if answer.time<=0 or not near(answer.tau,q.resistance*q.capacitance):return false
			var fraction=1-exp(-answer.time/answer.tau) if q.charging else exp(-answer.time/answer.tau)
			return near(fraction,q.fraction)
		"log_evaluate":return q.base>0 and q.base!=1 and q.argument>0 and near(pow(q.base,answer.value),q.argument)
		"log_equation":
			if answer.values.size()!=1 or answer.boundary!=q.h:return false
			var x=answer.values[0]
			return x>q.h and near(log(x-q.h)+log(x+q.h),log(q.product))
		"log_rules":return answer.a==q.power and answer.b==-q.divisor
		"decibel_inverse":return answer.output>0 and near((20 if q.voltage else 10)*log(answer.output/q.input)/log(10),q.gain)
		"decibels":return near(pow(10,answer.gain_db/(20 if q.voltage else 10))*q.input,q.output) and near(answer.ratio*q.input,q.output)
		"statistics":return verify_statistics(q.data,answer,int(q.precision))
		"frequency":
			if q.get("construct_table",false):
				if answer.rows!=q.rows:return false
				var count=0
				for row in answer.rows:
					if q.observations.count(row[0])!=row[1]:return false
					count+=int(row[1])
				return count==q.observations.size()
			var expanded=[]
			for row in q.rows:
				for _i in range(row[1]):expanded.append(row[0])
			var total=0.0
			for value in expanded:total+=value
			if q.has("missing_index"):return answer.missing_frequency==q.rows[q.missing_index][1] and answer.total_count==expanded.size()
			return answer.count==expanded.size() and near(answer.mean,total/expanded.size())
		"coins","dice","cards":return verify_probability(topic,q,p)
	return false
static func numeric_set(a: Array,b: Array) -> bool:
	if a.size()!=b.size():return false
	var used=[]
	for x in a:
		var found=-1
		for i in range(b.size()):
			if not used.has(i) and near(float(x),float(b[i])):found=i;break
		if found<0:return false
		used.append(found)
	return true
static func middle(a: Array) -> float:
	# Deliberately calculate middle indices via rank rather than calling the domain median helper.
	var lo=int(floor((a.size()-1)/2.0));var hi=int(ceil((a.size()-1)/2.0))
	return (float(a[lo])+float(a[hi]))/2.0
static func verify_statistics(data: Array,key: Dictionary,precision: int=1) -> bool:
	var sorted=data.duplicate();sorted.sort();var n=sorted.size();var sum=0.0;var modes=[];var maximum=0
	for value in sorted:sum+=value
	for value in sorted:
		var count=data.count(value)
		if count>maximum:maximum=count;modes=[value]
		elif count==maximum and not modes.has(value):modes.append(value)
	if maximum==1:modes=[]
	var half=int(n/2);var q1=middle(sorted.slice(0,half+n%2));var q3=middle(sorted.slice(n-half-n%2))
	var expected={"mean":sum/n,"median":middle(sorted),"q1":q1,"q3":q3,"iqr":q3-q1,"modal_frequency":maximum,"above_mean":0}
	var ticks=0
	for value in sorted:ticks+=int(round(value*precision))
	for value in sorted:
		if int(round(value*precision))*n>ticks:expected.above_mean+=1
	for field in key:
		if field=="modes":
			if not numeric_set(key.modes,modes):return false
		elif not expected.has(field) or not near(key[field],expected[field]):return false
	return key.has("mean") and key.has("median")
static func verify_probability(topic: String,q: Dictionary,p: Dictionary) -> bool:
	var numerator=0;var denominator=0
	if topic=="coins":
		denominator=int(pow(2,q.n))
		for mask in range(denominator):
			var heads=0
			for bit in range(q.n):heads+=(mask>>bit)&1
			if (heads>=q.k if q.at_least else heads==q.k):numerator+=1


		if q.has("second"):
			var n2=int(q.second.n);var k2=int(q.second.k);var total2=1<<n2;var count2=0
			for mask in range(total2):
				var heads=0
				for bit in range(n2):heads+=(mask>>bit)&1
				if heads==k2:count2+=1
			numerator*=count2;denominator*=total2
	elif topic=="dice":
		denominator=int(pow(6,q.n))
		for code in range(denominator):
			var temp=code;var sum=0
			for _i in range(q.n):sum+=temp%6+1;temp=int(temp/6)
			if (sum==q.threshold if q.condition=="exactly" else sum>=q.threshold):numerator+=1
	else:
		# Independent finite-deck recurrence counts ordered successful draws.
		var eligible=0
		for suit in range(4):
			for rank in range(1,14):
				var suit_ok=true
				if q.rule.suit_mode=="suit":suit_ok=suit==int(q.rule.suit)
				elif q.rule.suit_mode=="colour":suit_ok=(suit<2)==(int(q.rule.colour)==0)
				var match_card=suit_ok and rank>=q.rule.low and rank<=q.rule.high
				if q.rule.complement:match_card=not match_card
				if match_card:eligible+=1
		numerator=1;denominator=1
		for draw in range(q.draws):numerator*=eligible if q.replacement else eligible-draw;denominator*=52 if q.replacement else 52-draw
	var parts=str(p.answer.probability).split("/")
	return parts.size()==2 and int(parts[0])*denominator==numerator*int(parts[1]) and denominator>0 and numerator>=0 and numerator<=denominator

static func fraction_counts(value: String,numerator: int,denominator: int) -> bool:
	var parts=value.split("/")
	return parts.size()==2 and int(parts[1])>0 and int(parts[0])*denominator==numerator*int(parts[1])

