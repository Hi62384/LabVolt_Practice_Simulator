extends RefCounted
const C=preload("res://scripts/mth255/complex_domain.gd")
static func make(topic: String,d: int,r: RandomNumberGenerator) -> Dictionary:
	var a=r.randi_range(1,6+d);var b=r.randi_range(1,6+d);var sign_b=-1 if r.randi()%2 else 1
	var z=Vector2(a*(-1 if r.randi()%2 else 1),b*sign_b);var w=Vector2(b,a)
	var p={"parameters":{},"answer":{},"steps":[],"diagram":{},"input":{"kind":"structured","fields":[]},"expected_form":"structured","rubric":{"tolerance":0.000001}}
	match topic:
		"complex_components":
			var target=Vector2(r.randi_range(-8,8),r.randi_range(-8,8));var u=target-w if d>=1 else target;var second=w if d>=1 else Vector2.ZERO;var quadrant=0
			if target.x!=0 and target.y!=0:quadrant=1 if target.x>0 and target.y>0 else 2 if target.x<0 and target.y>0 else 3 if target.x<0 else 4
			p.parameters={"z":C.encode(target),"u":C.encode(u),"w":C.encode(second)};p.prompt="For z=(%s+j*(%s))+(%s+j*(%s)), find Re(z), Im(z), quadrant code (1–4; 0 if on an axis), and argument_defined (1=yes, 0=undefined)."%[u.x,u.y,second.x,second.y];p.answer={"real":target.x,"imag":target.y,"quadrant":quadrant,"argument_defined":0 if target.length_squared()==0 else 1};p.steps=[{"text":"Add real and imaginary components separately. Axis points are outside the four open quadrants; the zero vector has no unique argument."}]
		"complex_plot":
			var count=1 if d<2 else 2+d;var points=[];var given=[]
			for i in range(count):
				var x=r.randi_range(-8,8);var y=r.randi_range(-8,8);var point={"x":x,"y":y}
				while points.has(point):x=r.randi_range(-8,8);y=r.randi_range(-8,8);point={"x":x,"y":y}
				points.append(point);given.append("z%d=%d+j*(%d)"%[i+1,x,y])
			p.prompt="Plot all complex numbers on the real/imaginary plane: "+", ".join(given)+". Use real as x and imaginary coefficient as y.";p.parameters={"points":points};p.answer={"points":points};p.expected_form="graph_points";p.input={"kind":"complex_plane"};p.diagram={"kind":"complex_plane","domain":[-10,10],"range":[-10,10],"points":[],"polar":d>=3,"x_label":"Real","y_label":"Imaginary j"};p.steps=[{"text":"For each a+jb move a units on the real axis and b units vertically. Every distinct requested number needs one point."}]
		"j_power":
			var n=r.randi_range(-24,24)*(d+1);var values=[Vector2(1,0),Vector2(0,1),Vector2(-1,0),Vector2(0,-1)]
			var m=r.randi_range(-16,16);var k=r.randi_range(-16,16);var h=k+r.randi_range(-1,1);var zn=values[posmod(n,4)];var zm=values[posmod(m,4)];var zk=values[posmod(k,4)];var zh=values[posmod(h,4)];var result=zn
			var expression="j^(%d)"%n
			if d==1:result=C.multiply(zn,zm);expression="j^(%d)*j^(%d)"%[n,m]
			elif d==2:result=C.divide(zn,zm);expression="j^(%d)/j^(%d)"%[n,m]
			elif d==3:result=C.multiply(zn+zm,zk);expression="(j^(%d)+j^(%d))*j^(%d)"%[n,m,k]
			elif d==4:result=C.divide(zn+zm,zk+zh);expression="(j^(%d)+j^(%d))/(j^(%d)+j^(%d))"%[n,m,k,h]
			p.prompt="Evaluate %s. Give real and imaginary components."%expression;p.parameters={"n":n,"m":m,"k":k,"h":h,"mode":d};p.answer=C.encode(result);p.steps=[{"text":"The four powers repeat: 1, j, -1, -j. Reduce the exponent modulo four."}]
		"complex_convert":
			var phase=rad_to_deg(atan2(z.y,z.x));var mode=d%3
			p.parameters={"z":C.encode(z),"requested":["polar","exponential","rectangular"][mode]};p.expected_form=p.parameters.requested
			if mode==2:
				p.prompt="Convert %s exp(j*(%s degrees)) to rectangular form. Round to 5 decimal places."%[String.num(z.length(),15),String.num(phase,15)];p.answer=C.encode(z)
			else:
				p.prompt="Convert %s+j*(%s) to %s form. Give nonnegative magnitude and angle in degrees (5 decimal places)."%[z.x,z.y,p.parameters.requested];p.answer={"magnitude":z.length(),"angle":phase}
			p.diagram={"kind":"complex_plane","points":[{"x":z.x,"y":z.y,"label":"z"}],"domain":[-12,12],"range":[-12,12]};p.steps=[{"text":"Magnitude is sqrt(a²+b²). Use atan2(b,a) to preserve the quadrant; equivalent phases differ by 360 degrees."}]
			if d==3:p.prompt="Convert %s*exp(j*(%s radians)) to polar form. Give nonnegative magnitude and angle in degrees (5 decimal places)."%[String.num(z.length(),15),String.num(z.angle(),15)]
			elif d==4:
				var u=z-w;p.prompt="Convert (%s+j*(%s)) + (%s angle %s degrees) to exponential form. Give magnitude and phase in degrees to five decimal places."%[u.x,u.y,String.num(w.length(),15),String.num(rad_to_deg(w.angle()),15)]

		"complex_operation":
			var op=["add","subtract","multiply","divide","conjugate","reciprocal"][r.randi_range(0,mini(5,d+2))];var result=Vector2.ZERO
			match op:
				"add":result=z+w
				"subtract":result=z-w
				"multiply":result=C.multiply(z,w)
				"divide":result=C.divide(z,w)
				"conjugate":result=Vector2(z.x,-z.y)
				"reciprocal":result=C.divide(Vector2(1,0),z)
			p.prompt="Given z=%s+j*(%s), w=%s+j*(%s), calculate %s in rectangular form."%[z.x,z.y,w.x,w.y,op];p.parameters={"z":C.encode(z),"w":C.encode(w),"operation":op};p.answer=C.encode(result);p.expected_form="rectangular";p.steps=[{"text":"Use j²=-1. For division or reciprocals multiply numerator and denominator by the denominator's conjugate."}]
			if d>=2:
				var representation="%s angle %s degrees"%[String.num(w.length(),15),String.num(rad_to_deg(w.angle()),15)] if d==2 else "%s*exp(j*(%s radians))"%[String.num(w.length(),15),String.num(w.angle(),15)]
				p.prompt="Given z=%s+j*(%s), w=%s, calculate %s in rectangular form. Convert representations as needed; retain precision until the final five decimal places."%[z.x,z.y,representation,op]

		"complex_power":
			var n=r.randi_range(2,3+d);p.prompt="Calculate (%s+j*(%s))^%s in rectangular form using De Moivre's theorem."%[z.x,z.y,n];p.parameters={"z":C.encode(z),"n":n};p.answer=C.encode(C.power(z,n));p.expected_form="rectangular";p.steps=[{"text":"Convert to polar: raise magnitude to n and multiply phase by n. Convert the result back to rectangular coordinates."}]
		"complex_roots":
			var n=r.randi_range(2,mini(7,3+d));var roots=C.roots(z,n);var values=[]
			for value in roots:values.append(C.encode(value))
			p.prompt="Find ALL %dth roots of %s+j*(%s). Enter each root in rectangular form (5 decimal places)."%[n,z.x,z.y];p.parameters={"z":C.encode(z),"n":n};p.answer={"values":values};p.expected_form="complex_roots";p.input={"kind":"complex_roots","count":n,"angle_unit":"degrees"};p.prompt+=" Any scalar trig functions in component expressions use degrees.";p.diagram={"kind":"complex_plane","domain":[-4,4],"range":[-4,4],"points":[]};p.steps=[{"text":"For k=0,...,n-1 use magnitude r^(1/n) and phase (theta+360k)/n. There must be n distinct roots for nonzero z."}]
		"impedance":
			z.x=absf(z.x);w.x=absf(w.x);var parallel=d>=2;var zeq=C.divide(C.multiply(z,w),z+w) if parallel else z+w;var v=Vector2(12*a,0);var current=C.divide(v,zeq)
			p.prompt="Ideal sinusoidal steady state: impedances Z1=%s+j*(%s) ohm and Z2=%s+j*(%s) ohm are %s. Applied RMS phasor voltage is %s V at zero degrees. Find equivalent impedance and source-current rectangular components."%[z.x,z.y,w.x,w.y,"parallel" if parallel else "series",v.x];p.parameters={"z":C.encode(z),"w":C.encode(w),"v":v.x,"parallel":parallel};p.answer={"z_real":zeq.x,"z_imag":zeq.y,"i_real":current.x,"i_imag":current.y};p.diagram={"kind":"circuit","topology":"parallel" if parallel else "series","components":[{"id":"Z1","real":z.x,"imag":z.y},{"id":"Z2","real":w.x,"imag":w.y}],"source":{"rms_volts":v.x,"phase_degrees":0}};p.steps=[{"text":"Series: add impedances. Parallel: Z=Z1 Z2/(Z1+Z2). Use I=V/Z; positive resistance makes this ideal network nonsingular."}]
		"quadratic":
			var root1=r.randi_range(-9,9);var variant=r.randi_range(0,2);var root2=(-root1 if variant==0 else 0 if variant==1 else root1) if d==0 else r.randi_range(-9,9);var aa=a;var bb=-aa*(root1+root2);var cc=aa*root1*root2
			p.parameters={"a":aa,"b":bb,"c":cc};p.prompt="Solve %s*x²+(%s)*x+(%s)=0. Give every distinct root and the discriminant."%[aa,bb,cc];p.answer={"values":[root1] if root1==root2 else [root1,root2],"discriminant":bb*bb-4*aa*cc};p.expected_form="quadratic_roots";p.input={"kind":"structured","fields":[{"id":"values","kind":"solutions"},{"id":"discriminant"}]};p.steps=[{"text":"Set each factor to zero or apply (-b±sqrt(b²-4ac))/(2a). Substitute each proposed root into the original equation."}]
			var style=r.randi_range(0,2);var extra=r.randi_range(-9,9);var x={"op":"symbol","name":"x"};var ax2=_bin("mul",_n(aa),_bin("pow",x,_n(2)));var bx=_bin("mul",_n(bb),x);var left=_bin("add",_bin("add",ax2,bx),_n(cc));var right=_n(0)
			p.parameters.display_style=style;p.parameters.display_extra=extra
			if d==0:
				if style==0:left=_bin("add",ax2,bx);right=_n(-cc);p.prompt="Solve %d*x²+(%d)*x=%d. Enter all distinct roots and the discriminant after moving all terms to one side."%[aa,bb,-cc]
				elif style==1:left=_bin("add",_bin("add",ax2,bx),_n(cc+extra));right=_n(extra);p.prompt="Solve %d*x²+(%d)*x+(%d)=%d. Enter all distinct roots and the standard-form discriminant."%[aa,bb,cc+extra,extra]
				else:left=_bin("mul",x,_bin("add",_bin("mul",_n(aa),x),_n(bb)));right=_n(-cc);p.prompt="Solve x*(%d*x+(%d))=%d. Enter all distinct roots and the expanded standard-form discriminant."%[aa,bb,-cc]
			if d>=2:
				var shift=r.randi_range(1,5)
				p.prompt="Expand and rearrange %d*x*(x+(%d))+(%d)*x=%d, then solve. Give every distinct root and the discriminant of the resulting standard-form quadratic."%[aa,shift,bb-aa*shift,-cc]
				left=_bin("add",_bin("mul",_bin("mul",_n(aa),x),_bin("add",x,_n(shift))),_bin("mul",_n(bb-aa*shift),x));right=_n(-cc);p.parameters.display_shift=shift
			p.ast={"op":"equation","args":[left,right]}
			if d in [1,3]:
				p.prompt+=" Also enter the complete factorization of the normalized polynomial a*x²+b*x+c.";p.answer.factored="%d*(x-(%d))*(x-(%d))"%[aa,root1,root2];p.rubric.expression_fields=["factored"];p.rubric.expression_forms={"factored":"factored"};p.input.fields.append({"id":"factored","label":"Complete factorization"})


		"quadratic_formula":
			var h=0 if d==0 else r.randi_range(-6,6);var rad=[2,3,5,6,7,10][r.randi_range(0,5)];var nonreal=d>=3
			p.parameters={"h":h,"rad":rad,"nonreal":nonreal};p.prompt="Solve (x-(%d))²=%d. Give exact roots using sqrt and j components if needed."%[h,-rad if nonreal else rad];p.expected_form="exact_complex_roots" if nonreal else "exact_roots"
			if nonreal:p.answer={"values":[{"real":str(h),"imag":"sqrt(%d)"%rad},{"real":str(h),"imag":"-sqrt(%d)"%rad}]}
			else:p.answer={"values":["%d+sqrt(%d)"%[h,rad],"%d-sqrt(%d)"%[h,rad]]}
			p.input={"kind":"complex_roots" if nonreal else "solutions"};p.steps=[{"text":"Taking a square root requires both signs. A negative radicand contributes j. Keep the radical exact."}]
			if d==2:
				p.prompt="Complete the square to solve x²+(%d)*x+(%d)=0. Enter the square center h in (x-h)²=k, k, and every exact root."%[-2*h,h*h-rad];p.answer.center=h;p.answer.k=rad;p.input={"kind":"structured","fields":[{"id":"center","label":"Square center h"},{"id":"k","label":"Squared-side value k"},{"id":"values","label":"All exact roots","kind":"solutions"}]}
			elif d==4:
				p.prompt="Solve %d*(x-(%d))²+(%d)=%d. Enter every exact nonreal root using real and imaginary components."%[a,h,b,b-a*rad]

		"rational_quadratic":
			var excluded=r.randi_range(1,5);var other=excluded+a
			p.prompt="Solve (x²-(%d)*x+%d)/(x-%d)=0. State the excluded value and every valid root."%[excluded+other,excluded*other,excluded];p.parameters={"excluded":excluded,"other":other};p.answer={"values":[other],"excluded":[excluded]};p.expected_form="restricted_roots";p.steps=[{"text":"The original denominator excludes its zero even after cancellation. A rational expression is zero only if its numerator is zero and denominator nonzero."}]
		"radical_quadratic":
			var root=a+1;var offset=root*root-root
			p.prompt="Solve sqrt(x+%d)=x over the reals. Check the unsquared equation and reject extraneous roots."%offset;p.parameters={"offset":offset};p.answer={"values":[root]};p.expected_form="solutions";p.steps=[{"text":"The square root is nonnegative, so x≥0. Square both sides, solve the quadratic, then substitute in the unsquared equation."}]
		"biquadratic":
			var u=a;var v=a+b;var roots=[-v,-u,u,v]
			p.prompt="Solve x^4-(%d)*x²+%d=0 over the reals using u=x²."%[u*u+v*v,u*u*v*v];p.parameters={"u":u,"v":v};p.answer={"values":roots};p.expected_form="solutions";p.steps=[{"text":"Solve the quadratic in u, retain u≥0, and take both square roots for each positive u."}]
		"quadratic_application":
			var width=a+2;var length=width+b;var area=width*length
			p.prompt="A rectangular panel has area %d cm². Its length exceeds its width by %d cm. Find width and length in cm; reject negative dimensions."%[area,b];p.parameters={"area":area,"difference":b};p.answer={"width":width,"length":length};p.steps=[{"text":"Write w(w+d)=area, solve the quadratic, and retain the root giving positive dimensions."}]
			if d>=1 and bool(r.randi()%2):p.parameters.perimeter=2*(width+length);p.prompt="A rectangular panel has area %d cm² and perimeter %d cm. Find the shorter width and longer length in cm, rejecting negative dimensions."%[area,2*(width+length)]
		"quadratic_vertex":
			var h=r.randi_range(-8,8);var k=r.randi_range(2,20);var aa=-a if d%2 else a
			p.prompt="For y=%d*x²+(%d)*x+(%d), find the vertex coordinates and classify it: enter type=1 for minimum or -1 for maximum."%[aa,-2*aa*h,aa*h*h+k];p.parameters={"a":aa,"b":-2*aa*h,"c":aa*h*h+k};p.answer={"x":h,"y":k,"type":1 if aa>0 else -1};p.diagram={"kind":"graph","function":{"kind":"quadratic","a":aa,"b":-2*aa*h,"c":aa*h*h+k},"domain":[h-5,h+5],"range":[k-30,k+30]};p.steps=[{"text":"Complete the square or use x=-b/(2a), then substitute for y. The sign of a determines minimum or maximum."}]
		_ :return {"error":"Unknown complex/quadratic generator: "+topic}
	if topic in ["complex_convert","complex_operation","complex_power"]:
		p.input={"kind":"complex","form":p.expected_form,"angle_unit":"radians" if topic=="complex_operation" and d>=3 else "degrees"}

	return p

static func _n(value: int) -> Dictionary:
	return {"op":"neg","args":[{"op":"num","value":str(-value)}]} if value<0 else {"op":"num","value":str(value)}
static func _bin(operation: String,a: Dictionary,b: Dictionary) -> Dictionary:
	return {"op":operation,"args":[a,b]}
