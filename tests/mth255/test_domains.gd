extends SceneTree
const P=preload("res://scripts/mth255/provider.gd")
const D=preload("res://scripts/mth255/data_domains.gd")
const C=preload("res://scripts/mth255/complex_domain.gd")
var failures=0
func check(ok: bool,message: String) -> void:
	if not ok:print("FAIL "+message);failures+=1
func _initialize() -> void:
	var p=P.new()
	var z=Vector2(-3,-4);check(C.near(C.polar(z.length(),atan2(z.y,z.x)),z),"third-quadrant atan2")
	check(not C.valid(C.divide(Vector2(1,0),Vector2.ZERO)),"complex divide by zero")
	for n in range(2,13):check(C.verify_roots(z,C.roots(z,n),n),"complete roots n%d"%n)
	check(C.roots(Vector2.ZERO,4)==[Vector2.ZERO],"zero roots collapse")
	var s=D.describe([1,2,3,4,5]);check(s.q1==2 and s.q3==4 and s.modes.is_empty(),"odd quartile convention")
	s=D.describe([1,1,2,2,3,4]);check(s.modes==[1.0,2.0] and s.median==2,"multiple modes")
	check(D.dice_counts(2,7,"exactly").favorable==6,"dice sum weighting")
	check(D.coin_count(4,2,true)==11 and D.coin_count(4,2,false)==6,"exactly versus at least")
	check(D.card_counts("ace",2,false).favorable==12 and D.card_counts("ace",2,true).favorable==16,"replacement")
	if p._core()!=null:
		for bad in ["OS.execute('bad')","__import__(x)","x[0]","a=4","sqrt(-1)","log(0,10)","log(2,1)","atan2(0,0)"]:
			check(not p._scalar(bad).get("ok",false),"restricted scalar input "+bad)
		var degree_equation=p.generate_problem("trig_equation",0,17);var alpha=degree_equation.parameters.alpha
		check(p.check(degree_equation,{"values":["asin(sin(%s))"%alpha,"180-asin(sin(%s))"%alpha]}).correct,"degree inverse-function answer context")
		check(not p._scalar("exp(-1000)").get("ok",false),"shared core-v3 underflow rejection")
		var exact=p.generate_problem("quadratic_formula",4,134);var values=exact.answer.values.duplicate(true);values.reverse()
		check(p.check(exact,{"values":values}).correct,"exact nonreal radicals, unordered")
		values[0].imag="0.123456";check(not p.check(exact,{"values":values}).correct,"wrong exact radical")
		var prob=p.generate_problem("coins",4,34);var pair=prob.answer.probability.split("/");var equivalent="%d/%d"%[2*int(pair[0]),2*int(pair[1])]
		check(p.check(prob,{"probability":equivalent}).correct,"equivalent probability fraction")
		var polar=p.generate_problem("complex_convert",0,19)
		check(p.check(polar,{"magnitude":str(polar.answer.magnitude),"angle":polar.answer.angle+720,"form":"polar","angle_unit":"degrees"}).correct,"equivalent phase turns")
		check(p.check(polar,{"magnitude":polar.answer.magnitude,"angle":deg_to_rad(polar.answer.angle),"form":"polar","angle_unit":"radians"}).correct,"tagged radian answer")
		check(not p.check(polar,{"magnitude":polar.answer.magnitude,"angle":polar.answer.angle,"form":"exponential"}).correct,"required representation")
		var logq=p.generate_problem("log_equation",4,91);check(not p.check(logq,{"values":[-logq.answer.values[0]],"boundary":logq.parameters.h}).correct,"extraneous log root")
		var rad=p.generate_problem("radical_quadratic",4,91);check(not p.check(rad,{"values":[1-rad.answer.values[0]]}).correct,"extraneous squared root")
		var decimal=p.generate_problem("decibel_inverse",4,91);var value=decimal.answer.output;var places=3-int(floor(log(value)/log(10)));var scale=pow(10,places);var rounded=round(value*scale)/scale;var text=String.num(rounded,maxi(0,places))
		if text.contains("."):
			while text.get_slice(".",1).length()<places:text+="0"
		check(p.check(decimal,{"output":text}).correct,"four significant figure rounding "+text)
		check(not p.check(decimal,{"output":str(value)+"00000"}).correct,"excess significant figures")
	if p._core()!=null:
		var factor=p.generate_problem("quadratic",1,17);var unfactored=factor.answer.duplicate(true);var coef=factor.parameters;unfactored.factored="%s*x^2+(%s)*x+(%s)"%[coef.a,coef.b,coef.c]
		check(not p.check(factor,unfactored).correct,"complete factorization required form")
		var proof=p.generate_problem("trig_proof",4,78)
		check(p.check(proof,proof.answer).correct,"structured exact proof")
		check(not p.check(proof,{"step1":"1","step2":"1","restriction":1}).correct,"proof intermediate required form")
		var identity=p.generate_problem("trig_identity",1,2)
		check(not identity.has("error"),"core-v2 formerly withheld identity")
		if not identity.has("error"):
			var wrong_form=identity.answer.duplicate(true);wrong_form.expression="%d*sin(2*x)"%identity.parameters.scale
			check(not p.check(identity,wrong_form).correct,"identity required transformed form")
		var intersections=p.generate_problem("quadratic_system",4,12);var pts=intersections.answer.points
		check(p.check(intersections,{"x1":pts[1].x,"y1":pts[1].y,"x2":pts[0].x,"y2":pts[0].y}).correct,"coordinate intersections in either order")
	var points=p.generate_problem("wave_graph",4,11);var reversed=points.answer.points.duplicate(true);reversed.reverse();check(p.check(points,{"points":reversed}).correct,"graph critical point order")
	reversed[0].x+=points.parameters.period;check(not p.check(points,{"points":reversed}).correct,"wrong graph period")
	check(p.units().size()==5 and p.week_for_topic("log_changebase")==8,"unit and topic routing")
	var unit_assignment=p.generate_unit(3,4,77,8);check(not unit_assignment.has("error") and unit_assignment.unit==3 and unit_assignment.week_range==[5,6],"unit practice generation")
	check(p.generate_unit(3,4,77,8,"cards").has("error"),"cross-unit focus rejected")
	var assignment=p.generate(1,2,19);var marked=p.grade(assignment,{})
	check(marked.percentage==0 and marked.course=="MTH255","blank timeout score and separate course")
	var restored=p.restore(JSON.parse_string(JSON.stringify(assignment)));check(not restored.has("error"),"private saved assessment restore")
	var damaged=assignment.duplicate(true);damaged.questions[0].answer={};check(p.restore(damaged).has("error"),"damaged saved key rejected")
	var curve=p.generate_problem("waveform",2,55);var damaged_curve=curve.duplicate(true);damaged_curve.diagram.function.amplitude+=1
	check(not p.check(damaged_curve,curve.answer).correct,"diagram/function mismatch rejected")
	print("MTH255_EDGE failures=%d"%failures);quit(0 if failures==0 else 1)
