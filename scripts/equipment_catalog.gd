extends RefCounted
## Common 120 V/60 Hz variants. See docs/EQUIPMENT.md for source evidence
## and the distinction between documented values and modeling assumptions.
const LOADS := {
	"R":{"model":"8311","values":[1200.0,600.0,300.0],"labels":["1200Ω","600Ω","300Ω"]},
	"L":{"model":"8321","values":[3.2,1.6,0.8],"labels":["3.2H","1.6H","0.8H"]},
	"C":{"model":"8331","values":[2.2e-6,4.4e-6,8.8e-6],"labels":["2.2µF","4.4µF","8.8µF"]}
}
const CURRENT_COIL_OHMS := 0.02 # assumption, not a verified instrument spec
const VOLT_COIL_OHMS := 150000.0 # assumption
const FIXED_LIMIT_AMPS := 15.0
const VARIABLE_LIMIT_AMPS := 5.0
const LOAD_TRIP_VOLTS := 135.0 # conservative game threshold, not a real breaker
