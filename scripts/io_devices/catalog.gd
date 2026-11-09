extends RefCounted
const PIN_COUNTS={"io_encoder":3,"io_keypad":7,"io_slider":3,"io_joystick":6,"io_selector":4,"io_rgb":4,"io_bar":5,"io_matrix":8,"io_pixels":5,"io_graphic":5,"io_motor":2,"io_vibration":2,"io_servo":3,"io_relay":5,"io_bridge":6}
## Catalog fragment: simulated educational modules, never commercial-part claims.
static func all() -> Dictionary:
	var out := {}
	var rows := [
		["io_encoder","Quadrature rotary encoder","Input",["A","B","COM"],"Dry contacts; four Gray transitions per detent. One transition per simulation step."],
		["io_keypad","3 × 4 matrix keypad","Input",["R1","R2","R3","R4","C1","C2","C3"],"Twelve independent dry contacts, no isolation diodes; electrical ghosting is possible."],
		["io_slider","10 kΩ linear slider","Input",["A","W","B"],"Ideal linear track, 10 mΩ minimum end resistance."],
		["io_joystick","Two-axis thumbstick","Input",["VREF","X","Y","GND","SW","COM"],"Two 10 kΩ tracks and separate momentary switch; spring return to center."],
		["io_selector","Three-position selector","Input",["COM","1","2","3"],"Single-pole three-throw dry contact; break-before-make at operation boundary."],
		["io_rgb","RGB LED · common cathode","Output",["R","G","B","K"],"Three piecewise-linear junctions, 1.8/2.1/3 V; external series resistors required."],
		["io_bar","Four-segment LED bar","Output",["1","2","3","4","K"],"Four 1.8 V junctions, common cathode; external series resistors required."],
		["io_matrix","4 × 4 LED matrix","Output",["R1","R2","R3","R4","K1","K2","K3","K4"],"Sixteen 1.8 V junctions, anode rows/cathode columns; external current limiting required."],
		["io_pixels","LV clocked RGB strip · 8 pixels","Output",["VCC","GND","DATA","CLK","/CS"],"Educational 3–5.5 V protocol, not WS2812. CS low; MSB-first address 0–7, then R/G/B bytes, auto-increment. CS high aborts partial pixel."],
		["io_graphic","LV graphical display · 16 × 16","Output",["VCC","GND","DATA","CLK","/CS"],"Educational 3–5.5 V SPI, not SSD1306. CS low; MSB-first address 0–31 then framebuffer bytes. Row-major, MSB left, two bytes per row."],
		["io_motor","Small DC motor · educational","Output",["+","−"],"20 Ω winding, ke=kt=0.02 SI, J=1e-5 kg m², viscous friction 2e-5 Nm s. Back EMF and torque; no saturation, inductance or thermal model."],
		["io_vibration","Eccentric vibration motor · educational","Output",["+","−"],"DC motor model with 0.5 g eccentric mass at 2 mm. Vibration force follows angular speed squared."],
		["io_servo","Pulse-position servo · educational","Output",["VCC","GND","SIGNAL"],"4.5–6 V; 1–2 ms pulses at 10–30 ms intervals command 0–180°. Resolution limited to simulation step. 360°/s rate; approximate resistive power load."],
		["io_relay","Relay output · educational","Output",["COIL+","COIL−","COM","NC","NO"],"125 Ω coil, 3.5 V pull-in/1.5 V release; 50 mΩ contacts. No flyback suppression, contact bounce or inductance."],
		["io_bridge","Dual-input motor output module","Output",["VCC","GND","IN1","IN2","OUT1","OUT2"],"2–6 V educational H bridge; 2 Ω drivers, 1 MΩ input loads. Each high input connects its output to VCC; low connects to GND. No switching dead-time model."]
	]
	for row in rows:
		out[row[0]]={"name":row[1],"category":row[2],"kind":row[0],"pins":row[3],"rating":row[4],"price":12,"space":4,"rarity":"Uncommon","unit":"","io_version":1}
	return out

static func supports(kind: String) -> bool:
	return PIN_COUNTS.has(kind) or preload("res://scripts/commercial_devices/catalog.gd").supports(kind)

## New views opt into commercial surfaces; all() retains the15legacy fragment API.
static func surfaces() -> Dictionary:
	var out:=all()
	for key in preload("res://scripts/commercial_devices/catalog.gd").all():
		var entry: Dictionary=preload("res://scripts/commercial_devices/catalog.gd").all()[key]
		if entry.category in ["Input","Output"]:out[key]=entry
	return out
