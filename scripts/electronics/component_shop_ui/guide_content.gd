extends RefCounted

const LESSONS := {
	"R": ["A resistor limits current and creates a voltage drop proportional to the current through it. Both pins are interchangeable.","Put it in series with a load to limit current, or join two resistors end to end and measure the midpoint against the low rail."],
	"C": ["A capacitor stores charge. Its voltage changes as current flows into or out of it, so it can smooth a changing signal or delay a transition.","For an RC delay, connect a resistor from the source to one capacitor pin and the other pin to ground. Watch the voltage at the junction as the source switches."],
	"polar_cap": ["This capacitor stores charge with a preferred polarity. Reverse voltage can cause leakage in the model.","Connect + to the higher-voltage node and − to the lower-voltage node. To see smoothing, place it across the load and compare the voltage ripple with and without it."],
	"variable_cap": ["This adjustable capacitor changes the frequency response of a filter or resonant circuit.","Pair it with an inductor, apply an AC signal, and adjust the capacitor using Interact and the mouse wheel. Compare the response before and after tuning."],
	"L": ["An inductor stores energy in a magnetic field and resists changes in current. Its terminals are interchangeable.","Put it in series with a load and observe how current changes when the source switches. Pair it with a capacitor to explore resonance."],
	"variable_inductor": ["Changing the inductance changes how strongly this coil opposes a varying current.","Pair it with a capacitor and adjust the coil using Interact and the mouse wheel. Sweep the source frequency to find where the response is strongest."],
	"signal_transformer": ["Two isolated windings couple through a magnetic field. A changing signal in the primary induces a voltage in the secondary.","Apply AC across P+ and P−. Connect a load across S+ and S−, then compare the primary and secondary waveforms. Keep the two winding circuits separate."],
	"photodiode": ["The photodiode converts simulated light into a small current.","Connect a resistor across Anode and Cathode and measure the voltage across the resistor. Change the light using Interact and the mouse wheel to compare the readings."],
	"solar_panel": ["The panel turns simulated light into electrical power for a small load.","Connect the load across + and −. Measure the voltage across the load while changing the light with Interact and the mouse wheel."],
	"D": ["A diode conducts mainly from its anode to its cathode.","Wire A toward the positive side through a series resistor and K toward the return. Reverse it and compare the current under the same source voltage."],
	"LED": ["The LED lights when forward current flows from anode to cathode.","Run a series resistor from the positive supply to A and connect K to ground. Use the current reading to check your resistor choice."],
	"V": ["The battery module supplies DC voltage with internal resistance in the model.","Connect + to the positive rail and − to the return rail. Measure the rail voltage under load and avoid shorting the rails."],
	"pot": ["A movable wiper divides a resistive track into two sections.","Connect the two ends across a reference voltage and ground. Measure the wiper against ground as you turn or slide the control."],
	"io_slider": ["A movable wiper divides a resistive track into two sections.","Connect the two ends across a reference voltage and ground. Measure the wiper against ground as you turn or slide the control."],
	"button": ["These switches open or close a path between two pins. A momentary button releases automatically, while a toggle retains its position.","Wire the two pins in series with a load or use a pull resistor when driving a logic input. Operate the switch and watch the circuit change."],
	"toggle": ["These switches open or close a path between two pins. A momentary button releases automatically, while a toggle retains its position.","Wire the two pins in series with a load or use a pull resistor when driving a logic input. Operate the switch and watch the circuit change."],
	"io_joystick": ["The thumbstick contains two independent 10 kΩ potentiometers and a separate push switch. X and Y report position as voltages and return to center when released.","Connect VREF to a reference supply and GND to its return. Read X and Y with separate analog inputs or meters referenced to GND. Connect COM to ground and SW to a digital input with a pull-up. Pressing the stick then pulls that input low."],
	"io_encoder": ["A and B switch in a phase sequence as the encoder turns. Their order indicates direction.","Connect COM to ground and give A and B separate pull-ups. Turn the encoder and record both states to observe which channel changes first."],
	"io_keypad": ["A key bridges one row and one column. Each key is an independent switch.","Wire R1–R4 and C1–C3 to your controller. Scan one row at a time and read the pulled-up columns to identify the pressed key. Start with single key presses."],
	"io_selector": ["The selector connects COM to one of three throws.","Wire COM to your signal and 1, 2 and 3 to the three destinations. Check which branch conducts as you change position."],
	"seven_segment": ["The module contains independently driven LEDs with a shared cathode.","Connect COM or K to ground. Drive each labeled segment or color through its own series resistor. Test the channels separately before combining them."],
	"io_rgb": ["The module contains independently driven LEDs with a shared cathode.","Connect COM or K to ground. Drive each labeled segment or color through its own series resistor. Test the channels separately before combining them."],
	"io_bar": ["The module contains independently driven LEDs with a shared cathode.","Connect COM or K to ground. Drive each labeled segment or color through its own series resistor. Test the channels separately before combining them."],
	"io_matrix": ["Each LED is addressed by an anode row and a cathode column.","Apply a current-limited drive between one R pin and one K pin to light their intersection. To display a pattern, scan rows while changing the active columns."],
	"io_motor": ["A DC voltage spins the modeled motor. The vibration version converts rotation into vibration using an eccentric weight.","Connect a suitable DC supply across + and −. Change voltage and observe the speed or vibration. Reverse the leads to test the direction of rotation."],
	"io_vibration": ["A DC voltage spins the modeled motor. The vibration version converts rotation into vibration using an eccentric weight.","Connect a suitable DC supply across + and −. Change voltage and observe the speed or vibration. Reverse the leads to test the direction of rotation."],
	"io_servo": ["The servo moves toward an angle set by the width of a repeating pulse.","Power VCC and GND, then feed SIGNAL from a controller sharing the same ground. Try pulses between 1 and 2 ms and observe the position."],
	"io_relay": ["Energizing the coil moves the common contact from normally closed to normally open.","Put the control supply on the coil pins and route the switched circuit through COM and NO or NC. Test both coil states before connecting the intended load."],
	"relay": ["Energizing the coil moves the common contact from normally closed to normally open.","Put the control supply on the coil pins and route the switched circuit through COM and NO or NC. Test both coil states before connecting the intended load."],
	"logic": ["The chip reads digital inputs and drives outputs according to its gate or buffer function.","Connect its supply and ground, then drive the labeled inputs to defined high or low levels. Probe the matching output and step through the input combinations."],
	"nor": ["The chip reads digital inputs and drives outputs according to its gate or buffer function.","Connect its supply and ground, then drive the labeled inputs to defined high or low levels. Probe the matching output and step through the input combinations."],
	"schmitt": ["The chip reads digital inputs and drives outputs according to its gate or buffer function.","Connect its supply and ground, then drive the labeled inputs to defined high or low levels. Probe the matching output and step through the input combinations."],
	"timer555": ["The timer switches its output as the trigger and threshold cross internal references. DISCH provides a discharge path for a timing capacitor.","Wire VCC and GND and hold RESET high. For an oscillator, tie TRIG and THRES to the timing capacitor and use a resistor network through DISCH. Probe OUT."],
	"flip74": ["Each flip-flop stores the D input at a rising clock edge. Preset and clear can override that stored state.","Power the chip, hold the active-low preset and clear inputs high for normal operation, and feed D and CLK. Change D between clock edges and compare Q and its complement."],
	"shift595": ["Shift registers move bits one at a time on clock edges to convert between serial and parallel data.","Power the chip and use the labeled clock and load or latch controls. Shift a known bit pattern slowly and probe the outputs to check the bit order."],
	"shift165": ["Shift registers move bits one at a time on clock edges to convert between serial and parallel data.","Power the chip and use the labeled clock and load or latch controls. Shift a known bit pattern slowly and probe the outputs to check the bit order."],
	"spi_display": ["This device exchanges data with a controller over a clocked serial connection. Its pin names distinguish the clock, data and selection signals.","Connect power and a common ground, then wire clock and data to the controller. Assert chip select and use the protocol listed under Model details. Start with one transaction and observe the output or response."],
	"io_graphic": ["This device exchanges data with a controller over a clocked serial connection. Its pin names distinguish the clock, data and selection signals.","Connect power and a common ground, then wire clock and data to the controller. Assert chip select and use the protocol listed under Model details. Start with one transaction and observe the output or response."],
	"io_pixels": ["This device exchanges data with a controller over a clocked serial connection. Its pin names distinguish the clock, data and selection signals.","Connect power and a common ground, then wire clock and data to the controller. Assert chip select and use the protocol listed under Model details. Start with one transaction and observe the output or response."],
	"ili9341": ["This device exchanges data with a controller over a clocked serial connection. Its pin names distinguish the clock, data and selection signals.","Connect power and a common ground, then wire clock and data to the controller. Assert chip select and use the protocol listed under Model details. Start with one transaction and observe the output or response."],
	"xpt2046": ["This device exchanges data with a controller over a clocked serial connection. Its pin names distinguish the clock, data and selection signals.","Connect power and a common ground, then wire clock and data to the controller. Assert chip select and use the protocol listed under Model details. Start with one transaction and observe the output or response."],
	"eeprom25": ["This device exchanges data with a controller over a clocked serial connection. Its pin names distinguish the clock, data and selection signals.","Connect power and a common ground, then wire clock and data to the controller. Assert chip select and use the protocol listed under Model details. Start with one transaction and observe the output or response."],
	"adc3008": ["This device exchanges data with a controller over a clocked serial connection. Its pin names distinguish the clock, data and selection signals.","Connect power and a common ground, then wire clock and data to the controller. Assert chip select and use the protocol listed under Model details. Start with one transaction and observe the output or response."],
	"dac4921": ["This device exchanges data with a controller over a clocked serial connection. Its pin names distinguish the clock, data and selection signals.","Connect power and a common ground, then wire clock and data to the controller. Assert chip select and use the protocol listed under Model details. Start with one transaction and observe the output or response."],
	"ssd1306": ["This device shares a two-wire addressed bus with the controller.","Connect power and ground and wire SDA and SCL with pull-ups. Set any address pins, then send a transaction to the resulting address and check the device output."],
	"pca9685": ["This device shares a two-wire addressed bus with the controller.","Connect power and ground and wire SDA and SCL with pull-ups. Set any address pins, then send a transaction to the resulting address and check the device output."],
	"pcf8574": ["This device shares a two-wire addressed bus with the controller.","Connect power and ground and wire SDA and SCL with pull-ups. Set any address pins, then send a transaction to the resulting address and check the device output."],
	"controller": ["The programmable board reads circuit inputs and drives outputs using loaded firmware.","Connect power and a shared ground, wire your signal to a labeled input or output, and load a small program. Test one input or output before connecting the full circuit."],
	"native_controller": ["The programmable board reads circuit inputs and drives outputs using loaded firmware.","Connect power and a shared ground, wire your signal to a labeled input or output, and load a small program. Test one input or output before connecting the full circuit."],
	"hd44780": ["The LCD stores character codes and displays them in text cells.","Wire power, contrast and the RS, RW and E controls. Connect the data pins for the selected bus width and initialize the display before writing characters."],
	"ws2812": ["Each pixel takes its color data from the serial stream and passes the remaining data downstream.","Connect power and common ground. Feed the timed GRB stream into DIN, then test the first pixel before chaining another strip from DOUT."],
	"oscillator": ["The enabled oscillator produces a periodic clock when OE is high.","Connect VCC and GND, drive OE high and probe OUT. Compare the waveform with OE low and use edge scheduling if the clock aliases."],
	"quartz": ["A quartz crystal is a frequency-selective resonator.","Put X1 and X2 in a sustaining oscillator circuit. Probe the amplifier output after startup to see whether the circuit oscillates."],
	"opamp": ["The model responds to the voltage difference between its positive and negative inputs.","Connect the supply pins first. For an op-amp follower, feed OUT back to IN− and drive IN+. For a comparator, apply the reference to one input and observe the output as the other crosses it."],
	"lm358": ["The model responds to the voltage difference between its positive and negative inputs.","Connect the supply pins first. For an op-amp follower, feed OUT back to IN− and drive IN+. For a comparator, apply the reference to one input and observe the output as the other crosses it."],
	"lm324": ["The model responds to the voltage difference between its positive and negative inputs.","Connect the supply pins first. For an op-amp follower, feed OUT back to IN− and drive IN+. For a comparator, apply the reference to one input and observe the output as the other crosses it."],
	"comparator": ["The model responds to the voltage difference between its positive and negative inputs.","Connect the supply pins first. For an op-amp follower, feed OUT back to IN− and drive IN+. For a comparator, apply the reference to one input and observe the output as the other crosses it."],
	"bjt": ["This transistor controls current through one path using a signal on its control terminal.","Identify Base or Gate and the two current-path terminals from the labels. Put a load in the current path, apply a compatible control signal and compare the on and off readings."],
	"npn": ["This transistor controls current through one path using a signal on its control terminal.","Identify Base or Gate and the two current-path terminals from the labels. Put a load in the current path, apply a compatible control signal and compare the on and off readings."],
	"pnp": ["This transistor controls current through one path using a signal on its control terminal.","Identify Base or Gate and the two current-path terminals from the labels. Put a load in the current path, apply a compatible control signal and compare the on and off readings."],
	"mosfet": ["This transistor controls current through one path using a signal on its control terminal.","Identify Base or Gate and the two current-path terminals from the labels. Put a load in the current path, apply a compatible control signal and compare the on and off readings."],
	"jfet": ["This transistor controls current through one path using a signal on its control terminal.","Identify Base or Gate and the two current-path terminals from the labels. Put a load in the current path, apply a compatible control signal and compare the on and off readings."],
	"buzzer": ["An active buzzer generates its own tone from DC. A passive speaker follows the applied waveform.","Connect + and − to an appropriate source. Use DC for an active buzzer and a varying signal for a passive speaker, then compare the sound as the source changes."],
	"speaker": ["An active buzzer generates its own tone from DC. A passive speaker follows the applied waveform.","Connect + and − to an appropriate source. Use DC for an active buzzer and a varying signal for a passive speaker, then compare the sound as the source changes."],
	"io_bridge": ["This model uses control inputs to switch a load through output drivers.","Connect the supplies and common ground where provided. Wire the load to the designated output pins, then change one control input at a time and probe the output."],
	"bridge": ["This model uses control inputs to switch a load through output drivers.","Connect the supplies and common ground where provided. Wire the load to the designated output pins, then change one control input at a time and probe the output."],
	"l293d": ["This model uses control inputs to switch a load through output drivers.","Connect the supplies and common ground where provided. Wire the load to the designated output pins, then change one control input at a time and probe the output."],
	"uln2003": ["This model uses control inputs to switch a load through output drivers.","Connect the supplies and common ground where provided. Wire the load to the designated output pins, then change one control input at a time and probe the output."],
	"mux4051": ["Control pins select which signal path is electrically connected.","Power the device and wire a signal to a channel. Set the address or enable controls to defined logic levels and check continuity to the common terminal or matching channel pin."],
	"switch4066": ["Control pins select which signal path is electrically connected.","Power the device and wire a signal to a channel. Set the address or enable controls to defined logic levels and check continuity to the common terminal or matching channel pin."],
	"counter4017": ["The counter advances to the next decoded output on a clock edge.","Power the chip, reset it, and enable counting. Step the clock slowly and watch the output sequence."],
	"regulator": ["A regulator provides a controlled output from an input supply.","Wire input, return and output using the pin labels. Measure the output first with a light load, then check it again as the load changes."],
	"fuse": ["A fuse protects a path by opening it under the conditions defined by the model.","Place it in series with the branch you want to protect. Measure branch current and observe what happens when the modeled threshold is exceeded."],
	"zener": ["These diodes are designed to conduct in reverse when voltage reaches the modeled breakdown region.","Use a current-limited source and connect the device across the nodes being protected. Increase the source and measure the voltage across the diode."],
	"tvs": ["These diodes are designed to conduct in reverse when voltage reaches the modeled breakdown region.","Use a current-limited source and connect the device across the nodes being protected. Increase the source and measure the voltage across the diode."],
	"rs485": ["A transceiver translates logic signals to and from a differential bus.","Connect supply and ground, wire the differential pair, and set the driver and receiver enables. Send a known bit pattern and check the receive output."],
	"module": ["This package contains the circuit saved in its blueprint. Each external pin connects to a node chosen in the IC or PCB builder.","Open the blueprint’s internal circuit to identify power, return, inputs and outputs. Connect those terminals on the breadboard and probe a known input/output pair to check the package before wiring the rest of your circuit."],
}

const EXERCISES := {
	"io_joystick": "Watch both analog readings with the stick released. They should sit near half of VREF. Move the stick along one axis and watch that reading change while the other stays near center. Let go to check the spring return, then press the stick and watch SW go low independently of X and Y.",
	"R": "Use two resistors of the same value in series across a 5 V source. Measure from the junction to ground. It should read about 2.5 V. Replace the resistor on the ground side with a larger value and check that the midpoint voltage rises.",
	"C": "Use a 10 kΩ resistor and a 10 µF capacitor. Plot the junction voltage as the source steps high. It should reach about 63% of the final voltage after 0.1 seconds. Double the resistance and compare the rise times.",
	"LED": "Put a 330 Ω resistor in series with the LED on a 5 V source. Measure the voltage across the resistor and divide by 330 Ω to estimate the LED current. Reverse the LED and compare the readings.",
	"signal_transformer": "Compare the primary and secondary voltages with AC applied and a light load across the secondary. Then reduce the load resistance and compare the secondary voltage again to see the effect of winding resistance.",
	"io_encoder": "Step one detent clockwise and write down each A/B pair. Repeat counterclockwise. The same states appear in reverse order, so a controller can tell which direction the knob moved.",
	"io_rgb": "Light red and green together, each through its own resistor, to mix a color. Then switch off green while leaving red on to check that the channels are independent.",
	"io_relay": "With the coil off, check continuity from COM to NC and from COM to NO. Energize the coil and repeat. The conducting path should switch from NC to NO.",
}

const PIN_ROLES := {
	"io_joystick": {
		"VREF": "Reference voltage for both position tracks.",
		"X": "Horizontal axis wiper. Measure relative to GND.",
		"Y": "Vertical axis wiper. Measure relative to GND.",
		"GND": "Return for the position tracks.",
		"SW": "Push-switch contact. Connect to an input with a pull-up.",
		"COM": "Other push-switch contact. Connect to ground for an active-low input.",
	},
	"signal_transformer": {
		"P+": "Primary winding input, marked end.",
		"P−": "Other end of the primary winding.",
		"S+": "Secondary winding output, marked end.",
		"S−": "Other end of the secondary winding.",
	},
	"LED": {
		"A": "Anode. Current enters here in forward operation.",
		"K": "Cathode. Connect toward the lower potential.",
	},
	"polar_cap": {
		"+": "Positive terminal. Connect to the higher DC potential.",
		"−": "Negative terminal. Connect to the lower DC potential.",
	},
}

static func exercise(entry: Dictionary) -> String:
	return EXERCISES.get(_kind(entry), "")

static func pin_roles(entry: Dictionary) -> Dictionary:
	return PIN_ROLES.get(_kind(entry), {})

static func _kind(entry: Dictionary) -> String:
	var kind := str(entry.get("kind", ""))
	if kind == "worker_model":
		var model := str(entry.get("worker_model", ""))
		return "D" if model == "diode" else model
	return kind

static func lesson(entry: Dictionary) -> Array:
	return LESSONS.get(_kind(entry), [
		"%s exposes the terminals shown in the pin map. The model details below describe the behavior and limits implemented in the simulator." % str(entry.get("name", "This component")),
		"Use the named terminals to connect the part to your circuit. Start with a simple input and probe the output or load before connecting the rest of the circuit."
	])
