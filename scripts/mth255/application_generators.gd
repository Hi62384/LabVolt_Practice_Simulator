extends RefCounted
## Additional course applications use the common provider and scalar engine.
static func make(topic: String,d: int,r: RandomNumberGenerator) -> Dictionary:
	var a=r.randi_range(1,6+d);var b=r.randi_range(1,6+d);var p={"parameters":{},"answer":{},"steps":[],"diagram":{},"input":{"kind":"structured","fields":[]},"expected_form":"structured","rubric":{"tolerance":0.000001}}
	match topic:
		"decibel_inverse":
			var voltage=bool(r.randi()%2);var input=float(r.randi_range(1,99))/10;var gain=float(r.randi_range(-25,25));var factor=20 if voltage else 10
			p.parameters={"voltage":voltage,"input":input,"gain":gain};p.prompt="An amplifier has signed gain %s dB and input %s %s. Find output %s to FOUR significant figures. %s"%[gain,input,"V RMS" if voltage else "W","RMS voltage in V" if voltage else "power in W","For voltage, equal positive resistive impedances are assumed." if voltage else "Use the power-gain definition."];p.answer={"output":input*pow(10,gain/factor)};p.rubric.field_forms={"output":{"form":"significant","digits":4}};p.steps=[{"text":"Invert the logarithmic gain with ratio=10^(G/20) for equal-impedance RMS voltage or 10^(G/10) for power. Multiply by the input and round only the final output to four significant figures."}]
		"quadratic_system":
			var h=r.randi_range(-5,5);var k=r.randi_range(-6,6);var m=r.randi_range(-3,3);var n=k+a*a-m*h
			# y=(x-h)^2+k, y=m*(x-h)+k+a^2. Chosen constant yields distinct real intersections.
			var disc=m*m+4*a*a;var u1=(m+sqrt(disc))/2;var u2=(m-sqrt(disc))/2
			p.prompt="Find BOTH intersection points of y=(x-(%d))²+(%d) and y=%d*(x-(%d))+(%d). Enter both coordinate pairs to 5 decimal places, in either order."%[h,k,m,h,k+a*a];p.parameters={"h":h,"k":k,"m":m,"a":a};p.answer={"points":[{"x":h+u1,"y":m*u1+k+a*a},{"x":h+u2,"y":m*u2+k+a*a}]};p.expected_form="system_points";p.input={"kind":"structured","fields":[{"id":"x1","label":"First point x"},{"id":"y1","label":"First point y"},{"id":"x2","label":"Second point x"},{"id":"y2","label":"Second point y"}]};p.rubric.point_tolerance={"x":0.00002,"y":0.00002};p.steps=[{"text":"Equate the two expressions for y. Put u=x-h, solve u²-mu-a²=0, recover x, and substitute to find each corresponding y. Check both original relations."}]
		"polynomial_remaining":
			var root=r.randi_range(-5,5);var s=root+a;var t=root-a-b;var B=-(root+s+t);var cc=root*s+root*t+s*t;var dd=-root*s*t
			p.prompt="Given %d is a root of x³+(%d)*x²+(%d)*x+(%d)=0, divide by x-(%d). Enter quotient coefficients B,C for x²+B*x+C, remainder, and ALL original roots."%[root,B,cc,dd,root];p.parameters={"known":root,"B":B,"C":cc,"D":dd};p.answer={"b":-(s+t),"c":s*t,"remainder":0,"values":[root,s,t]};p.steps=[{"text":"Use polynomial division or synthetic division. The zero remainder verifies the known root. Factor the quadratic quotient and include the given root in the complete set."}]
		"resistor_pair":
			var r1=a*100;var r2=(a+b)*100;var series=r1+r2;var parallel=float(r1*r2)/series
			p.prompt="Two positive resistors have series equivalent %s ohm and parallel equivalent %s ohm. Find BOTH resistor values in ohms, order irrelevant."%[series,parallel];p.parameters={"series":series,"parallel":parallel};p.answer={"values":[r1,r2]};p.expected_form="solutions";p.steps=[{"text":"Let x and S-x be the resistances. The parallel relationship gives x*(S-x)=P*S. Solve the quadratic and retain positive values."}]
		"engineering_power":
			var resistance=float(a*20);var voltage=float(2*(a+b));var current=voltage/(resistance*(3+d));var power=voltage*current-resistance*current*current;var second=voltage/resistance-current
			p.prompt="Ideal load-power model P=E*I-R*I² with E=%s V, R=%s ohm, P=%s W. Find ALL nonnegative currents I in amperes."%[voltage,resistance,power];p.parameters={"R":resistance,"E":voltage,"P":power};p.answer={"values":[current,second]};p.expected_form="solutions";p.steps=[{"text":"Rearrange as R*I²-E*I+P=0. Both roots can be physically valid in this model; check nonnegative current and the original power equation."}]
		"half_angle":
			var theta=[60,90,120,180,240,270,300][r.randi_range(0,6)];var cosine=d%2==1;var angle=theta/2.0
			p.parameters={"theta":theta,"cosine":cosine};p.prompt="Given theta=%d degrees, evaluate %s(theta/2) exactly using a half-angle identity. Enter sign=1 or -1 and squared magnitude as an exact expression; sign follows the half-angle quadrant."%[theta,"cos" if cosine else "sin"]
			var cos_keys={60:"1/2",90:"0",120:"-1/2",180:"-1",240:"-1/2",270:"0",300:"1/2"};var expression="(1+(%s))/2"%cos_keys[theta] if cosine else "(1-(%s))/2"%cos_keys[theta]
			p.answer={"sign":-1 if (cos(deg_to_rad(angle)) if cosine else sin(deg_to_rad(angle)))<0 else 1,"squared_magnitude":expression};p.expected_form="exact_fields";p.steps=[{"text":"For cosine use (1+cos(theta))/2; for sine use (1-cos(theta))/2 under the square root. Select the sign from the quadrant of theta/2."}]
		"log_variable_base":
			var root=a+2;var coefficient=root+b;var constant=root*root-coefficient*root
			p.parameters={"coefficient":coefficient,"constant":constant};p.prompt="Solve log_x(%d*x+(%d))=2 over the reals. Return ALL valid roots and the excluded base values 0 and 1. Check base>0, base≠1 and argument>0."%[coefficient,constant];var candidates=[root,b];var values=[]
			for x in candidates:
				if x>0 and x!=1 and not values.has(x):values.append(x)
			p.answer={"values":values,"excluded":[0,1],"boundary":maxf(0.0,-float(constant)/coefficient)};p.expected_form="restricted_roots";p.steps=[{"text":"Convert to x²=coefficient*x+constant, solve the quadratic, and reject invalid bases or arguments. Bases below one are allowed when positive and not equal to one."}]
		"exp_substitution":
			var positive=a+1;var negative=-b;var multiplier=d+1
			p.parameters={"positive":positive,"negative":negative,"multiplier":multiplier};p.prompt="Solve exp(%d*x)^2-(%d)*exp(%d*x)+(%d)=0 over the reals. Give x to 5 decimal places."%[multiplier,positive+negative,multiplier,positive*negative];p.answer={"x":log(positive)/multiplier};p.steps=[{"text":"Put u=exp(m*x)>0. Solve the quadratic in u, reject its negative root, then use x=ln(u)/m."}]
		"card_union":
			var suit=r.randi_range(0,3);var rank=r.randi_range(1,13);var intersection=d>=2;var favorable=1 if intersection else 16
			p.parameters={"suit":suit,"rank":rank,"intersection":intersection};p.prompt="Draw one card from a standard 52-card deck, no jokers. Find P(card is suit %s %s rank %s). Here OR is inclusive."%[["hearts","diamonds","clubs","spades"][suit],"AND" if intersection else "OR",["ace","2","3","4","5","6","7","8","9","10","jack","queen","king"][rank-1]];p.answer={"probability":"%d/52"%favorable};p.expected_form="exact_probability";p.steps=[{"text":"Intersection is one specified card. Inclusive union has 13+4-1=16 cards because the intersection would otherwise be counted twice."}]
		"dice_event":
			var variant=r.randi_range(0,mini(3,d+1));var divisor=r.randi_range(2,5);var favorable=0
			for x in range(1,7):
				for y in range(1,7):
					if x==y if variant==0 else x!=y if variant==1 else x%2==0 and y%2==0 if variant==2 else (x+y)%divisor==0:favorable+=1
			p.parameters={"variant":variant,"divisor":divisor};p.prompt="Roll two fair independent six-sided dice. Find the exact probability of %s."%["a double" if variant==0 else "not a double" if variant==1 else "both faces even" if variant==2 else "a sum divisible by %d"%divisor];p.answer={"probability":"%d/36"%favorable};p.expected_form="exact_probability";p.steps=[{"text":"List ordered pairs in a 6 by 6 table. Mark the event and divide the marked count by 36; the complement offers an independent check for not-a-double."}]
		_:return {"error":"Unknown application topic."}
	return p
