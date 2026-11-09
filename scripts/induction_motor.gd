extends RefCounted
## Illustrative 4-pole per-phase induction machine equivalent circuit.
## Parameters are deliberately NOT claimed to identify the photographed machine.
## Rs=12Ω, Rr'=9Ω, Xs=Xr'=15Ω, Xm=180Ω at 60Hz; no core loss branch.
const RS := 12.0
const RR := 9.0
const XS := 15.0
const XR := 15.0
const XM := 180.0
const POLES := 4

static func mul(a: Vector2,b: Vector2) -> Vector2:
	return Vector2(a.x*b.x-a.y*b.y,a.x*b.y+a.y*b.x)

static func divc(a: Vector2,b: Vector2) -> Vector2:
	return Vector2(a.dot(b),a.y*b.x-a.x*b.y)/b.length_squared()

static func impedance(frequency: float,slip: float) -> Vector2:
	var scale := frequency/60.0
	var magnetizing := Vector2(0,XM*scale)
	var rotor := Vector2(RR/clampf(slip,.0001,1),XR*scale)
	return Vector2(RS,XS*scale)+divc(mul(magnetizing,rotor),magnetizing+rotor)

static func torque(voltage: float,frequency: float,slip: float) -> float:
	var scale := frequency/60.0
	var rotor := Vector2(RR/clampf(slip,.0001,1),XR*scale)
	var input := divc(Vector2(voltage,0),impedance(frequency,slip))
	var air_gap := Vector2(voltage,0)-mul(input,Vector2(RS,XS*scale))
	var rotor_current := divc(air_gap,rotor).length()
	var omega_sync := TAU*(120*frequency/POLES)/60
	return 3*rotor_current*rotor_current*RR/clampf(slip,.0001,1)/omega_sync

static func operating_point(voltage: float,frequency: float,load: float) -> Dictionary:
	var demand := .02+clampf(load,0,1)*1.2 # friction plus dynamometer constant torque, Nm
	var peak_slip := .001
	var peak_torque := 0.0
	for i in range(1,101):
		var s := i/100.0
		var t := torque(voltage,frequency,s)
		if t>peak_torque:
			peak_slip=s
			peak_torque=t
	var slip := 1.0
	var stalled := voltage<20 or demand>peak_torque
	if not stalled:
		var low := .0001
		var high := peak_slip
		for i in range(32):
			var middle := (low+high)*.5
			if torque(voltage,frequency,middle)<demand:
				low=middle
			else:
				high=middle
		slip=(low+high)*.5
	var sync := 120*frequency/POLES
	var rpm := 0.0 if stalled else sync*(1-slip)
	return {"slip":slip,"rpm":rpm,"synchronous_rpm":sync,"torque":torque(voltage,frequency,slip),"shaft_power":load*1.2*rpm*TAU/60,"starting_current":voltage/impedance(frequency,1).length(),"stalled":stalled}
