extends RefCounted
const Boards=preload("res://scripts/firmware_backends/native_boards.gd")
static func pins(board: String) -> Array:
	var result: Array=[]
	var model: Dictionary=Boards.catalog().get("native_"+board,{})
	for i in model.get("pins",[]).size():
		var label: String=model.pins[i]
		var role := "GPIO"
		if label.begins_with("GND") or label=="AGND":role="ground"
		elif label in ["RESET","RESET2","RUN"]:role="active-low reset"
		elif label in ["5V","3V3","VIN","VSYS","VBUS","IOREF","3V3_EN"]:role="power/control"
		elif label in ["AREF","ADC_VREF"]:role="ADC reference"
		elif label=="NC":role="not connected"
		if board=="nano" and label in ["A6","A7"]:role="ADC input only"
		result.append({"index":i,"label":label,"role":role,"header_number":i+1 if board in ["pico","nano"] else 0})
	return result
static func summary(board: String) -> String:
	if board=="nano":return "Classic Nano (ATmega328P 16MHz/5V): same D0–D13 and A0–A5 electrical peripherals as Uno, plus analog-only A6/A7. Both RESET and GND header aliases are wired. Not Nano Every, Nano 33 or Nano ESP32. SPI D13/D11/D12; I2C A5/A4; UART D1/D0. External I2C pullups required."
	if board=="uno":return "Power: 5V/GND regulated rail (4.5–5.5 V), or educational VIN regulator. RESET is active low. A0–A5: ADC; D3/5/6/9/10/11: timer PWM; D0/1: UART. SDA/SCL alias A4/A5. Header array order is shown by the physical board labels, not ATmega package numbers."
	return "Power: 3V3/GND logic rail (3.0–3.6 V), or VSYS/VBUS regulator model. RUN is active low. GP26/27/28: header ADC; GP23/24/25/29 are internal board signals. ADC_VREF is physical pin 35; GP25 drives the onboard LED. Single core; no boot ROM, USB or MicroPython runtime."
