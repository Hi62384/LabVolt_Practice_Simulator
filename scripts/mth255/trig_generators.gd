extends RefCounted
static func make(topic: String,d: int,r: RandomNumberGenerator) -> Dictionary:
	var a=r.randi_range(1,5+d);var b=r.randi_range(1,6);var p={"parameters":{},"answer":{},"steps":[],"diagram":{},"input":{"kind":"structured","fields":[]},"expected_form":"structured","rubric":{"tolerance":0.000001}}
	match topic:
		"wave_from_graph":
			var amplitude=float(a);var frequency=r.randi_range(1,5+d);var period=1.0/frequency;var shift=0.0 if d==0 else r.randi_range(0,7)*period/8;var offset=0.0 if d<2 else float(r.randi_range(-5,5))
			p.parameters={"amplitude":amplitude,"period":period,"shift":shift,"offset":offset};p.prompt="Read the plotted sinusoid and write y=offset+A*sin(2*pi*(t-shift)/T). Enter A>0, period T in seconds, offset, and the unique shift with 0≤shift<T. The plotted curve, axes and sample values are the givens; no hidden function parameters are sent.";p.answer={"amplitude":amplitude,"period":period,"offset":offset,"shift":shift};p.rubric.field_tolerances={"amplitude":amplitude*0.01,"period":period*0.01,"offset":amplitude*0.01,"shift":period*0.01};p.prompt+=" Graph readings allow 1% of amplitude for vertical values and 1% of period for time values.";p.diagram={"kind":"sinusoid","function":{"kind":"sin","amplitude":amplitude,"period":period,"phase":shift,"offset":offset},"domain":[-period,period],"range":[offset-amplitude*1.2,offset+amplitude*1.2],"points":[],"x_label":"time (s)","y_label":"y"};p.steps=[{"text":"Read max and min: A=(max-min)/2 and offset=(max+min)/2. Measure one repeat for T. Find the rising offset crossing and reduce its time modulo T for the required shift."}]
		"wave_graph":
			var amplitude=float(a);var frequency=r.randi_range(1,8);var period=1.0/frequency;var shift=0.0 if d<2 else r.randi_range(-3,3)*period/8;var offset=0.0 if d<3 else float(b);var cosine=d%2==1;var points=[]
			for i in range(5):
				var x=shift+i*period/4;var y=offset+amplitude*(cos(TAU*i/4) if cosine else sin(TAU*i/4));points.append({"x":x,"y":y})
			p.parameters={"amplitude":amplitude,"period":period,"shift":shift,"offset":offset,"cosine":cosine};p.prompt="Plot the five quarter-period critical points for one complete cycle of y=%s+%s*%s(2*pi*(t-(%s))/%s), from t=shift to shift+period. Time t is seconds, angles radians. Include both cycle endpoints."%[offset,amplitude,"cos" if cosine else "sin",shift,period];p.answer={"points":points};p.expected_form="graph_points";p.input={"kind":"graph"};p.diagram={"kind":"graph","domain":[shift-period/4,shift+period*1.25],"range":[offset-amplitude*1.4,offset+amplitude*1.4],"points":[],"x_label":"time (s)","y_label":"y"};p.rubric.point_tolerance={"x":period*0.01,"y":amplitude*0.01};p.steps=[{"text":"Start at the horizontal shift. Advance by T/4 each point; sine values are 0,1,0,-1,0 and cosine values 1,0,-1,0,1, then scale and offset."}]
		"angle_conversion":
			var degrees=r.randi_range(-12,12)*15;var to_radians=d%2==0
			p.parameters={"degrees":degrees,"to_radians":to_radians};p.prompt="Convert %s to %s. Give an exact expression using pi where needed."%[str(degrees)+" degrees" if to_radians else "%d*pi/180 radians"%degrees,"radians" if to_radians else "degrees"];p.answer={"value":"%d*pi/180"%degrees if to_radians else str(degrees)};p.expected_form="exact_fields";p.steps=[{"text":"A full turn is 360 degrees or 2*pi radians. Multiply degrees by pi/180 or radians by 180/pi."}]
		"exact_trig":
			var angles=[0,30,45,60,90,120,135,150,180,210,225,240,270,300,315,330];var deg=angles[r.randi_range(0,angles.size()-1)];var cosine=d%2==1
			var sin_keys=["0","1/2","sqrt(2)/2","sqrt(3)/2","1","sqrt(3)/2","sqrt(2)/2","1/2","0","-1/2","-sqrt(2)/2","-sqrt(3)/2","-1","-sqrt(3)/2","-sqrt(2)/2","-1/2"]
			# Cos(theta)=sin(90-theta); indices derived from the same geometric special angles.
			var turns=r.randi_range(-4,4) if d>=1 else 0;deg+=360*turns
			var lookup=posmod(90-deg,360) if cosine else posmod(deg,360);var index=angles.find(lookup)
			p.parameters={"degrees":deg,"cosine":cosine};p.prompt="Evaluate %s(%d degrees) exactly."%["cos" if cosine else "sin",deg];p.answer={"value":sin_keys[index]};p.expected_form="exact_fields";p.diagram={"kind":"unit_circle","angle_unit":"degrees","domain":[-1.5,1.5],"range":[-1.5,1.5],"points":[{"x":cos(deg_to_rad(deg)),"y":sin(deg_to_rad(deg)),"label":"theta"}]};p.steps=[{"text":"Use the unit circle and reference-angle triangles. x is cosine and y is sine; apply quadrant signs and retain radicals."}]

			p.parameters.mode=d
			if d==2:
				if sin_keys[index]=="0":deg=30+360*turns;index=angles.find(30)
				p.parameters.degrees=deg;p.prompt="Evaluate 1/sin(%d degrees) exactly, stating that the denominator is nonzero."%deg;p.answer.value="1/(%s)"%sin_keys[index]
			elif d==3:
				var si=angles.find(posmod(deg,360));var ci=angles.find(posmod(90-deg,360));p.parameters.a=a;p.parameters.b=b;p.prompt="Evaluate %d*sin(%d degrees)+%d*cos(%d degrees) exactly."%[a,deg,b,deg];p.answer.value="%d*(%s)+%d*(%s)"%[a,sin_keys[si],b,sin_keys[ci]]
			elif d==4:
				var other=angles[r.randi_range(0,angles.size()-1)];var si=angles.find(posmod(deg,360));var ci=angles.find(posmod(90-deg,360));var sj=angles.find(other);var cj=angles.find(posmod(90-other,360));p.parameters.other=other;p.prompt="Evaluate sin(%d degrees)*cos(%d degrees)+cos(%d degrees)*sin(%d degrees) exactly, using an angle identity where useful."%[deg,other,deg,other];p.answer.value="(%s)*(%s)+(%s)*(%s)"%[sin_keys[si],sin_keys[cj],sin_keys[ci],sin_keys[sj]]
			# Rebuild the private teaching vector from the actual (possibly related) angle.
			p.diagram.points=[{"x":cos(deg_to_rad(deg)),"y":sin(deg_to_rad(deg)),"label":"theta"}]

		"trig_identity":
			var scale=r.randi_range(1,7);var variant=r.randi_range(0,mini(4,d+1));var identities=["sin(x)^2+cos(x)^2","1+tan(x)^2","sin(2*x)","cos(2*x)","sin(x+y)"];var targets=["1","sec(x)^2","2*sin(x)*cos(x)","cos(x)^2-sin(x)^2","sin(x)*cos(y)+cos(x)*sin(y)"]
			p.parameters={"variant":variant,"scale":scale};p.prompt="Complete an identity transformation for %d*(%s). Enter an equivalent expression using the requested identity and identify its domain restriction: 0=all real; 1=cos(x) nonzero."%[scale,identities[variant]];p.answer={"expression":"%d*(%s)"%[scale,targets[variant]],"restriction":1 if variant==1 else 0};p.expected_form="identity";p.prompt+=" "+["Use a constant result.","Use sec(x) only.","Use sin(x) and cos(x), with no multiple-angle functions.","Use sin(x) and cos(x), with no multiple-angle functions.","Use separate sin/cos functions of x and y, with no sum inside a function."][variant];p.rubric.required_identity=["pythagorean","reciprocal","double_angle_sine","double_angle_cosine","angle_sum"][variant];p.steps=[{"text":"Apply the named identity to one side only. Preserve the original domain; tan and sec require cos(x)≠0."}]
		"trig_equation":
			var n=r.randi_range(1,d+1);var alpha=[30,45,60][r.randi_range(0,2)];var radians=d%2==1;var values=[]
			for k in range(n):
				values.append((alpha+360.0*k)/n* (PI/180 if radians else 1.0));values.append((180-alpha+360.0*k)/n*(PI/180 if radians else 1.0))
			values.sort();var rhs=sin(deg_to_rad(alpha));p.parameters={"n":n,"alpha":alpha,"radians":radians};p.prompt="Solve sin(%d*x)=sin(%d degrees) for ALL x in %s. Give decimal values to 5 places in the stated interval units."%[n,alpha,"[0,2*pi) radians" if radians else "[0,360) degrees"];p.answer={"values":values};p.expected_form="solutions";p.input={"kind":"solutions","angle_unit":"radians" if radians else "degrees"};p.steps=[{"text":"Both theta=alpha+360k and theta=180-alpha+360k solve the sine equation. Divide by the angle multiplier and retain every value in the half-open interval."}]
		"waveform":
			var frequency=r.randi_range(2,40)*(d+1);var phase_index=r.randi_range(-5,5);var phase=phase_index*PI/6;var amplitude=float(a);var t=float(b)/(frequency*12.0)
			p.parameters={"amplitude":amplitude,"frequency":frequency,"phase":phase,"t":t};p.prompt="v(t)=%s*sin(2*pi*%s*t+(%d*pi/6)) V, t in seconds and angle in radians. Find amplitude V, period s, angular frequency rad/s, phase shift s, and v(%d/%d) V."%[amplitude,frequency,phase_index,b,frequency*12];p.answer={"amplitude":amplitude,"period":1.0/frequency,"omega":TAU*frequency,"shift":-phase/(TAU*frequency),"value":amplitude*sin(TAU*frequency*t+phase)};p.diagram={"kind":"sinusoid","function":{"kind":"sin","amplitude":amplitude,"period":1.0/frequency,"phase":-phase/(TAU*frequency),"offset":0},"domain":[0,2.0/frequency],"range":[-amplitude*1.2,amplitude*1.2],"x_label":"t (s)","y_label":"v (V)"};p.steps=[{"text":"Compare A*sin(omega*t+phi): period=2*pi/omega, frequency=1/period, and horizontal shift=-phi/omega. Convert angles before evaluating."}]
		"wave_combine":
			var aa=a*(-1 if r.randi()%2 else 1);var bb=b*(-1 if r.randi()%2 else 1);var omega=r.randi_range(5,50)
			p.parameters={"a":aa,"b":bb,"omega":omega};p.prompt="Combine %s*sin(%s*t)+(%s)*cos(%s*t) as R*sin(%s*t+phi). Find R≥0, phi in radians, and the lead time relative to sin(%s*t) in seconds (negative means lag)."%[aa,omega,bb,omega,omega,omega];p.answer={"magnitude":sqrt(aa*aa+bb*bb),"angle":atan2(bb,aa),"lead_seconds":atan2(bb,aa)/omega};p.steps=[{"text":"Expand R*sin(omega*t+phi). Match R*cos(phi)=A and R*sin(phi)=B, then use R=sqrt(A²+B²) and phi=atan2(B,A)."}]
			p.prompt+=" For the lead time, use the shortest signed representative (between -T/2 and T/2)."
			if d>=3:p.answer.lead_milliseconds=1000*atan2(bb,aa)/omega;p.prompt+=" Also enter that lead time in milliseconds."
		"wave_threshold":
			var omega=r.randi_range(10,80);var phase=r.randi_range(-3,3)*PI/4;var ratio=[0.0,0.5,-0.5][r.randi_range(0,2)];var alpha=asin(ratio);var candidates=[]
			for k in range(-2,5):
				for angle in [alpha+TAU*k,PI-alpha+TAU*k]:
					var t=(angle-phase)/omega
					if t>0.000000001:candidates.append(t)
			candidates.sort();p.parameters={"amplitude":a,"omega":omega,"phase":phase,"ratio":ratio};p.prompt="Find the earliest strictly positive time in seconds when %d*sin(%d*t+(%s))=%s. All angles are radians."%[a,omega,phase,a*ratio];p.answer={"time":candidates[0]};p.steps=[{"text":"Solve both sine-angle families. Subtract phase, divide by positive omega, and choose the smallest strictly positive candidate; do not return t=0."}]
		_ :return {"error":"Unknown trigonometry generator: "+topic}
	return p
