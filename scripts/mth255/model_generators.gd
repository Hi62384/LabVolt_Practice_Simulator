extends RefCounted
const Cards=preload("res://scripts/mth255/card_rules.gd")
const D=preload("res://scripts/mth255/data_domains.gd")
static func make(topic: String,d: int,r: RandomNumberGenerator) -> Dictionary:
	var a=r.randi_range(2,8);var b=r.randi_range(1,6);var p={"parameters":{},"answer":{},"steps":[],"diagram":{},"input":{"kind":"structured","fields":[]},"expected_form":"structured","rubric":{"tolerance":0.000001}}
	match topic:
		"exponential":
			var initial=r.randi_range(3,30);var rate=(d+1)*r.randf_range(0.1,0.5)*(-1 if r.randi()%2 else 1);rate=snappedf(rate,0.01);var t=snappedf(r.randf_range(0.2,3),0.01)
			p.parameters={"initial":initial,"rate":rate,"t":t};p.prompt="For y(t)=%d*exp((%s)*t), find y(%s), y(0), and the horizontal asymptote. The mathematical domain is all real t; range is positive."%[initial,rate,t];p.answer={"value":initial*exp(rate*t),"initial":initial,"asymptote":0};p.diagram={"kind":"graph","function":{"kind":"exponential","amplitude":initial,"rate":rate,"offset":0},"domain":[0,4],"range":[0,initial*exp(maxf(0,rate)*4)*1.1]};p.steps=[{"text":"Substitute the time into the exponent, then multiply by the initial value. Positive rate gives growth; negative rate gives decay toward zero."}]

			if d>=3:
				var ratio=[0.5,0.75,1.25,1.5][r.randi_range(0,3)];var t1=1 if d==3 else 2;var t2=2 if d==3 else 4;var t3=3 if d==3 else 6;rate=log(ratio);var y1=initial*pow(ratio,t1);var y2=initial*pow(ratio,t2)
				p.parameters={"initial":initial,"rate":rate,"fit":true,"t1":t1,"t2":t2,"t3":t3,"y1":y1,"y2":y2};p.prompt="A positive exponential y=A*exp(k*t) satisfies y(%d)=%s and y(%d)=%s. Find initial value A, signed rate k, and y(%d). Round final scalar answers to five decimal places."%[t1,String.num(y1,15),t2,String.num(y2,15),t3];p.answer={"initial":initial,"rate":rate,"value_at_t3":initial*pow(ratio,t3)};p.diagram.function.rate=rate;p.diagram.domain=[t1,t2];p.diagram.range=[0,maxf(y1,y2)*1.1];p.steps=[{"text":"Divide the two observations to eliminate A: y2/y1=exp(k*(t2-t1)). Take ln to find k, substitute to recover A, and evaluate the later time without early rounding."}]

		"exp_equation":
			var base=r.randi_range(2,7);var coefficient=a;var shift=r.randi_range(-5,5);var target=r.randi_range(3,40)
			p.parameters={"base":base,"coefficient":coefficient,"shift":shift,"target":target};p.prompt="Solve %d^(%d*x+(%d))=%d. Give x to 5 decimal places."%[base,coefficient,shift,target];p.answer={"x":(log(target)/log(base)-shift)/coefficient};p.steps=[{"text":"Take logarithms: (coefficient*x+shift)*ln(base)=ln(target). Isolate x. Positive base unequal to one makes the exponential one-to-one."}]
		"rc_model":
			var resistance=r.randi_range(1,20)*100.0;var capacitance=r.randi_range(1,20)*0.00001;var voltage=r.randi_range(3,30);var tau=resistance*capacitance;var fraction=snappedf(r.randf_range(0.1,0.9),0.01);var charging=d%2==0;var time=-tau*log(1-fraction if charging else fraction)
			p.parameters={"resistance":resistance,"capacitance":capacitance,"voltage":voltage,"fraction":fraction,"charging":charging};p.prompt="Ideal RC %s capacitor voltage: E=%d V, R=%s ohm, C=%s F, initially %s. Find tau in seconds and time in seconds to reach %s V. Use v=E*(1-exp(-t/RC)) for charge or E*exp(-t/RC) for discharge."%["charging" if charging else "discharging",voltage,resistance,capacitance,"uncharged" if charging else "charged to E",fraction*voltage];p.answer={"tau":tau,"time":time};p.diagram={"kind":"graph","function":{"kind":"exponential","amplitude":-voltage if charging else voltage,"rate":-1/tau,"offset":voltage if charging else 0},"domain":[0,5*tau],"range":[0,voltage*1.1]};p.steps=[{"text":"Convert R and C to SI before tau=RC. Isolate the exponential and take ln. Charging capacitor VOLTAGE rises while its series current decays."}]

			if d==4:
				p.parameters.unknown_capacitance=true;p.parameters.given_time=time;p.prompt="An ideal RC %s capacitor has source E=%d V and R=%s ohm. At t=%s s the capacitor voltage is %s V. Initially it was %s. Find C in MICROFARADS, using the charging or discharging voltage model as appropriate."%["charging" if charging else "discharging",voltage,String.num(resistance,15),String.num(time,15),String.num(fraction*voltage,15),"uncharged" if charging else "charged to E"];p.answer={"capacitance_microfarads":capacitance*1000000};p.steps=[{"text":"First isolate exp(-t/(RC)) from the appropriate voltage formula. Then C=-t/(R*ln(remaining exponential fraction)); convert farads to microfarads only at the end."}]

		"log_evaluate":
			var base=r.randi_range(2,8);var exponent=r.randi_range(-3,3+d);var argument=pow(base,exponent)
			p.prompt="Evaluate log base %d of (%s). State the logarithm base and argument."%[base,argument];p.parameters={"base":base,"exponent":exponent,"argument":argument};p.answer={"value":exponent,"base":base,"argument":argument};p.diagram={"kind":"graph","function":{"kind":"log","base":base,"rate":1,"phase":0,"amplitude":1,"offset":0},"domain":[0.1,minf(50,maxf(3,argument*1.5))],"range":[-5,maxf(5,exponent+1)],"x_label":"positive x","y_label":"log base %s of x"%base};p.steps=[{"text":"log_b(A)=y means b^y=A. Check b>0, b≠1, A>0 before applying the inverse relationship."}]
		"log_equation":
			var h=r.randi_range(1,7);var root=h+a;var product=(root-h)*(root+h);var base=r.randi_range(2,7)
			p.prompt="Solve log_%d(x-%d)+log_%d(x+%d)=log_%d(%d) over the reals. State the lower domain boundary (strict x>boundary) and all roots."%[base,h,base,h,base,product];p.parameters={"base":base,"h":h,"product":product};p.answer={"values":[root],"boundary":h};p.expected_form="log_solutions";p.steps=[{"text":"Both log arguments must be positive, so x>h. Combine the logs, solve x²-h²=product, and reject the negative candidate in the original equation."}]
		"log_rules":
			var power=r.randi_range(2,3+d);var divisor=r.randi_range(1,4);p.prompt="For x>0 and y>0, expand ln(x^%d/y^%d) as A*ln(x)+B*ln(y). Enter coefficients A and B."%[power,divisor];p.parameters={"power":power,"divisor":divisor};p.answer={"a":power,"b":-divisor};p.steps=[{"text":"The logarithm of a quotient is a difference. Bring exponents in front only on the stated positive domain."}]
		"decibels":
			var voltage=d%2==1;var ratio=pow(10.0,r.randi_range(-3,3)/2.0);var input=r.randi_range(1,20)/10.0;var output=input*ratio;var factor=20 if voltage else 10
			p.parameters={"voltage":voltage,"input":input,"output":output};p.prompt="Input %s=%.12f %s and output=%.12f %s. Find signed gain in dB and output/input ratio. %s"%["RMS voltage" if voltage else "power",input,"V" if voltage else "W",output,"V" if voltage else "W","Equal positive resistive impedances are assumed for the voltage gain formula." if voltage else "Power values are positive."];p.answer={"gain_db":factor*log(ratio)/log(10),"ratio":ratio};p.steps=[{"text":"Use 10*log10(Pout/Pin) for power. Use 20*log10(Vout/Vin) for RMS voltage with equal impedances. A ratio below one has negative gain."}]
		"statistics":
			var data=[];var n=r.randi_range(6+2*d,10+4*d);var precision=10.0 if d>=2 else 1.0
			for _i in range(n):data.append(r.randi_range(90,110)/precision)
			var stats=D.describe(data);var total_ticks=0
			for value in data:total_ticks+=int(round(value*precision))
			stats.mean=float(total_ticks)/(data.size()*precision);p.parameters={"data":data,"precision":precision};p.prompt="Generated equipment readings: %s. Find mean, median, Q1, Q3, IQR and ALL modes (empty set means no mode). Quartiles use medians of halves, including the central observation in both halves when n is odd."%str(data);p.answer={"mean":stats.mean,"median":stats.median,"q1":stats.q1,"q3":stats.q3,"iqr":stats.iqr,"modes":stats.modes};p.expected_form="statistics";p.diagram={"kind":"statistics","columns":[{"id":"value","label":"Reading"}],"rows":[]};p.input={"kind":"structured","fields":[{"id":"mean"},{"id":"median"},{"id":"q1"},{"id":"q3"},{"id":"iqr"},{"id":"modes","kind":"solutions"}]}
			for value in data:p.diagram.rows.append([value])
			p.steps=[{"text":"Sort observations. Mean=sum/n; median uses central positions. Split halves with the stated convention. All values tied at the greatest frequency are modes, unless every value occurs once."}]

			if d==0:
				p.answer={"mean":stats.mean,"median":stats.median};p.prompt="Generated readings %s. Find the arithmetic mean and median."%str(data)
			elif d==1:
				p.answer={"mean":stats.mean,"median":stats.median,"modes":stats.modes};p.prompt="Generated readings %s. Find mean, median and ALL modes; enter an empty set if every value occurs once."%str(data)
			elif d>=3:
				var maximum=0
				for count in stats.counts.values():maximum=maxi(maximum,int(count))
				p.answer.modal_frequency=maximum;p.prompt+=" Also give the modal frequency (largest occurrence count)."
				if d==4:
					var above=0
					for value in data:
						if int(round(value*precision))*data.size()>total_ticks:above+=1
					p.answer.above_mean=above;p.prompt+=" Count observations strictly above the mean."
			p.input={"kind":"structured","fields":[]}

		"frequency":
			var rows=[];var weighted=0;var count=0;var n=r.randi_range(3,4+d)
			for i in range(n):
				var value=a+i*b;var frequency=r.randi_range(1,4+d);rows.append([value,frequency]);weighted+=value*frequency;count+=frequency
			p.parameters={"rows":rows};p.prompt="For frequency rows [value,count]=%s, find total count and weighted mean. Each row value represents exactly count observations."%str(rows);p.answer={"count":count,"mean":float(weighted)/count};p.diagram={"kind":"statistics","columns":[{"id":"value","label":"Value"},{"id":"frequency","label":"Frequency"}],"rows":rows};p.steps=[{"text":"The denominator is sum of frequencies, not the number of distinct values. Weighted mean=sum(value*frequency)/sum(frequency)."}]


			if d==2:
				var observations=[];var blanks=[]
				for row in rows:
					for _i in range(row[1]):observations.append(row[0])
					blanks.append([row[0],""])
				for i in range(observations.size()-1,0,-1):
					var j=r.randi_range(0,i);var temp=observations[i];observations[i]=observations[j];observations[j]=temp
				p.parameters.construct_table=true;p.parameters.observations=observations;p.prompt="Construct the frequency distribution for generated observations %s. The value column lists the distinct readings; enter each occurrence count. Rows may be reordered, but all values and counts are required."%str(observations);p.answer={"rows":rows};p.expected_form="frequency_table";p.input={"kind":"statistics_table","columns":[{"id":"value","label":"Reading"},{"id":"frequency","label":"Frequency"}],"rows":blanks};p.diagram={"kind":"statistics","columns":[{"id":"observation","label":"Observation"}],"rows":[]}
				for value in observations:p.diagram.rows.append([value])
				p.steps=[{"text":"Count each distinct reading across the entire observation list. Frequencies are nonnegative integers and their sum must equal the number of observations. Sorting can make this counting easier."}]

			if d>=3:
				var shown=rows.duplicate(true);var missing=shown[0][1];shown[0][1]="?";p.parameters.missing_index=0;p.prompt="Frequency rows [value,count]=%s have EXACT weighted mean %d/%d. Find the missing frequency and total observation count."%[str(shown),weighted,count];p.answer={"missing_frequency":missing,"total_count":count};p.diagram.rows=shown

		"coins":
			var n=r.randi_range(2,3+d);var k=r.randi_range(0,n);var at_least=d>0 and bool(r.randi()%2);var counts=D.coin_count(n,k,at_least);var total=int(pow(2,n))
			p.parameters={"n":n,"k":k,"at_least":at_least};p.prompt="Toss %d independent fair coins. Find the exact probability of %s %d heads."%[n,"at least" if at_least else "exactly",k];p.answer={"probability":"%d/%d"%[counts,total]};p.expected_form="exact_probability";p.diagram={"kind":"probability","mode":"coins","outcomes":[]}
			for heads in range(n+1):p.diagram.outcomes.append({"label":"%d heads"%heads,"favorable":heads>=k if at_least else heads==k,"weight":D.choose(n,heads)})
			p.steps=[{"text":"There are 2^n equally likely ordered outcomes. Exactly k heads gives choose(n,k) favorable outcomes; at least k requires summing all k through n."}]

			if d>=3:
				var n2=r.randi_range(2,3+d);var k2=r.randi_range(0,n2);var second_count=D.coin_count(n2,k2,false);var total2=int(pow(2,n2));p.parameters.second={"n":n2,"k":k2};p.prompt="Two independent groups of fair coins are tossed: group A has %d coins and group B has %d coins. Find the exact probability A has %s %d heads AND B has exactly %d heads."%[n,n2,"at least" if at_least else "exactly",k,k2];p.answer.probability="%d/%d"%[counts*second_count,total*total2];p.diagram.mode="tree";p.diagram.outcomes=[{"label":"A and B","weight":counts*second_count,"favorable":true},{"label":"A and not B","weight":counts*(total2-second_count),"favorable":false},{"label":"not A and B","weight":(total-counts)*second_count,"favorable":false},{"label":"neither","weight":(total-counts)*(total2-second_count),"favorable":false}];p.steps.append({"text":"The two groups are independent. Count each group's event separately, then multiply their exact probabilities."})

		"dice":
			var n=r.randi_range(1,mini(4,2+d));var threshold=r.randi_range(n,6*n);var condition="exactly" if d==0 or r.randi()%2 else "at least";var counts=D.dice_counts(n,threshold,condition)
			p.parameters={"n":n,"threshold":threshold,"condition":condition};p.prompt="Roll %d independent fair six-sided dice. Find the exact probability the sum is %s %d."%[n,condition,threshold];p.answer={"probability":"%d/%d"%[counts.favorable,counts.total]};p.expected_form="exact_probability";p.diagram={"kind":"probability","mode":"dice","outcomes":[]}
			for total in counts.distribution:p.diagram.outcomes.append({"label":str(total),"weight":counts.distribution[total],"favorable":total==threshold if condition=="exactly" else total>=threshold})
			p.steps=[{"text":"Count ordered face outcomes; different sums are not equally likely. Divide the matching count by 6^n."}]
		"cards":
			var low=r.randi_range(1,13);var high=r.randi_range(low,13);var rule={"suit_mode":["all","suit","colour"][r.randi_range(0,2)],"suit":r.randi_range(0,3),"colour":r.randi_range(0,1),"low":low,"high":high,"complement":d>=1 and bool(r.randi()%2)}
			if r.randi_range(0,7)==0:rule.low=2;rule.high=10
			var draws=r.randi_range(1,mini(4,d+1));var replacement=bool(r.randi()%2);var counts=Cards.counts(rule,draws,replacement);var condition=Cards.description(rule)
			p.parameters={"rule":rule,"draws":draws,"replacement":replacement};p.prompt="From a standard 52-card deck without jokers draw %d cards %s replacement. Find the exact probability EVERY draw satisfies %s. Numeric ranks: ace=1, jack=11, queen=12, king=13; number cards are ranks 2 through 10."%[draws,"with" if replacement else "without",condition];p.answer={"probability":"%d/%d"%[counts.favorable,counts.total]};p.expected_form="exact_probability";p.diagram={"kind":"probability","mode":"cards","outcomes":[{"label":condition,"weight":counts.favorable,"favorable":true},{"label":"Other ordered draw sequences","weight":counts.total-counts.favorable,"favorable":false}]};p.steps=[{"text":"Enumerate the eligible cards using the stated suit/colour and rank interval, then apply the complement if requested. Multiply draw probabilities; without replacement both favorable count and deck count decrease after each success. Zero eligible cards or too few eligible cards can correctly give probability zero."}]
		_ :return {"error":"Unknown model/data generator: "+topic}
	return p
