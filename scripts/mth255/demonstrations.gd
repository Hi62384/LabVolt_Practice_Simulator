extends RefCounted
## Course-specific demo state feeds the shared math UI; no per-frame symbolic work.
const C=preload("res://scripts/mth255/complex_domain.gd")
static func complex_vector(real: float,imag: float,polar_grid: bool=false) -> Dictionary:
	if not is_finite(real) or not is_finite(imag) or maxf(absf(real),absf(imag))>10000:return {"error":"Coordinates out of range."}
	var extent=maxf(2,Vector2(real,imag).length()*1.2)
	return {"kind":"complex_plane","polar":polar_grid,"domain":[-extent,extent],"range":[-extent,extent],"points":[{"x":real,"y":imag,"label":"z"}],"magnitude":Vector2(real,imag).length(),"phase_degrees":rad_to_deg(atan2(imag,real)) if real!=0 or imag!=0 else null,"x_label":"Real","y_label":"Imaginary j"}
static func root_vectors(real: float,imag: float,n: int) -> Dictionary:
	if n<2 or n>12:return {"error":"Root count must be 2 through 12."}
	var out=complex_vector(real,imag);var roots=C.roots(Vector2(real,imag),n)
	if out.has("error") or not C.verify_roots(Vector2(real,imag),roots,n):return {"error":"Invalid roots."}
	out.points=[]
	for i in range(roots.size()):out.points.append({"x":roots[i].x,"y":roots[i].y,"label":"root %d"%(i+1)})
	return out
static func wave(amplitude: float,frequency: float,phase_radians: float,comparison_phase: Variant=null) -> Dictionary:
	if not is_finite(amplitude) or not is_finite(frequency) or not is_finite(phase_radians) or amplitude<0 or amplitude>10000 or frequency<=0 or frequency>100000:return {"error":"Invalid wave parameters."}
	var primary={"kind":"sin","amplitude":amplitude,"period":1/frequency,"phase":-phase_radians/(TAU*frequency),"offset":0}
	var out={"kind":"sinusoid","function":primary,"domain":[0,2/frequency],"range":[-maxf(1,amplitude)*1.2,maxf(1,amplitude)*1.2],"x_label":"time (s)","y_label":"value","angle_unit":"radians","curves":[]}
	if comparison_phase is float or comparison_phase is int:
		if not is_finite(float(comparison_phase)):return {"error":"Invalid comparison phase."}
		var comparison=primary.duplicate(true);comparison.phase=-float(comparison_phase)/(TAU*frequency);out.curves=[primary,comparison];out.lead_seconds=(phase_radians-float(comparison_phase))/(TAU*frequency)
	return out
static func rc(voltage: float,resistance: float,capacitance: float,charging: bool) -> Dictionary:
	if not is_finite(voltage) or not is_finite(resistance) or not is_finite(capacitance) or voltage<=0 or resistance<=0 or capacitance<=0:return {"error":"Positive finite SI values required."}
	var tau=resistance*capacitance
	if not is_finite(tau) or tau<1e-9 or tau>1e9:return {"error":"Time constant outside demonstration range."}
	return {"kind":"graph","function":{"kind":"exponential","amplitude":-voltage if charging else voltage,"rate":-1/tau,"offset":voltage if charging else 0},"domain":[0,5*tau],"range":[0,voltage*1.1],"x_label":"time (s)","y_label":"capacitor voltage (V)","tau":tau}
