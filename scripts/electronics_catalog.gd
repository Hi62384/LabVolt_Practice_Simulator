extends RefCounted

static func polarity_labels(entry: Dictionary) -> Array:
	var pins: Array = entry.get("pins",[])
	if pins.size()!=2:return []
	if entry.get("kind","") in ["LED","D","photodiode"]:return ["A","K"]
	if pins==["+","−"] or pins==["+","-"]:return ["+","−"]
	return []
const CATEGORIES := ["Basic","IC","PCB","Input","Output"]
static var _simulation_entries: Dictionary={}
# Copy one immutable built-in definition instead of rebuilding the complete shop
# catalogue at every electrical edge. Runtime state is never stored here.
static func simulation_entry(id: String) -> Dictionary:
	if _simulation_entries.is_empty():_simulation_entries=all()
	if id.begins_with("cv1:") and not _simulation_entries.has(id):
		var configured: Dictionary=preload("res://scripts/electronics/component_values/values.gd").resolve(id,_simulation_entries)
		if not configured.ok:return {}
		if _simulation_entries.size()<512:_simulation_entries[id]=configured.entry.duplicate(true)
		return configured.entry
	return _simulation_entries.get(id,{}).duplicate(true)
static func all() -> Dictionary:
	var entries := {}
	for value in [100,220,470,1000,2200,4700,10000,47000,100000]:
		entries["r"+str(value)]={"name":"%s Ω resistor"%value,"category":"Basic","kind":"R","value":float(value),"unit":"Ω","rating":"0.25 W · ideal resistance","price":1,"space":1,"rarity":"Common","pins":["1","2"]}
	for uf in [0.1,1.0,10.0,100.0]:
		entries["c"+str(uf)]={"name":"%s μF capacitor"%uf,"category":"Basic","kind":"C","value":uf*1e-6,"unit":"F","rating":"50 V · ideal non-polar storage","price":2,"space":1,"rarity":"Common","pins":["1","2"]}
	for mh in [1,10,100]:entries["l"+str(mh)]={"name":"%s mH inductor"%mh,"category":"Basic","kind":"L","value":mh*.001,"unit":"H","rating":"Ideal inductor, no core saturation","price":3,"space":2,"rarity":"Common","pins":["1","2"]}
	entries.diode={"name":"Silicon diode","category":"Basic","kind":"D","value":.65,"vf":.65,"ron":2,"unit":"V","rating":"Piecewise-linear forward model; no avalanche","price":2,"space":1,"rarity":"Common","pins":["Anode (A)","Cathode (K)"]}
	entries.led={"name":"Red LED","category":"Output","kind":"LED","value":1.8,"vf":1.8,"ron":10,"unit":"V","rating":"20 mA nominal · use a series resistor","price":3,"space":1,"rarity":"Common","pins":["Anode (A)","Cathode (K)"]}
	entries.button={"name":"Momentary button","category":"Input","kind":"button","value":.01,"unit":"Ω","rating":"NO · 10 mΩ closed","price":3,"space":2,"rarity":"Common","pins":["1","2"]}
	entries.toggle={"name":"Toggle switch","category":"Input","kind":"toggle","value":.01,"unit":"Ω","rating":"SPST · latched","price":3,"space":2,"rarity":"Common","pins":["1","2"]}
	entries.battery={"name":"5 V battery module","category":"PCB","kind":"V","value":5.0,"resistance":1.0,"unit":"V","capacity_ah":0.30,"rating":"0.30 Ah · nominal voltage and internal resistance","price":10,"space":5,"rarity":"Uncommon","pins":["+","−"]}
	for source in [
		["battery_ac","AC Battery",16,"Fixed sine wave · set frequency and peak voltage when buying"],
		["battery_adjustable","Adjustable Battery",18,"Adjustable DC output · scroll to change voltage"],
		["battery_generator","Function Generator Battery",24,"Set frequency and peak voltage when buying · click to change waveform"],
		["battery_generator_adjustable","Adjustable Function Generator Battery",32,"Click to change waveform · scroll for voltage · Shift+scroll for frequency"],
	]:
		var mode: String=source[0]
		var entry := {"name":source[1],"category":"PCB","kind":"portable_source","source_mode":mode,"value":5.0,"resistance":1.0,"unit":"V","rating":source[3],"price":source[2],"space":5,"rarity":"Uncommon","pins":["+","−"]}
		if mode!="battery_adjustable":entry.frequency=60.0
		entries[mode]=entry
	entries.pot10k={"name":"10 kΩ potentiometer","category":"Input","kind":"pot","value":10000.,"unit":"Ω","rating":"Three pins: end / wiper / end · ideal track","price":12,"space":2,"rarity":"Common","pins":["End A","Wiper","End B"]}
	entries.polar_cap={"name":"100 µF polarized capacitor","category":"Basic","kind":"polar_cap","value":100e-6,"unit":"F","rating":"25 V nominal. Mind polarity: the model includes reverse leakage above the reverse knee.","price":4,"space":2,"rarity":"Common","pins":["+","−"]}
	entries.variable_cap={"name":"Variable capacitor","category":"Basic","kind":"variable_cap","value":500e-12,"minimum":10e-12,"unit":"F","rating":"Adjust from 10 to 500 pF using Interact and the mouse wheel.","price":12,"space":2,"rarity":"Uncommon","pins":["1","2"]}
	entries.variable_inductor={"name":"Variable inductor","category":"Basic","kind":"variable_inductor","value":.1,"minimum":.001,"unit":"H","rating":"Adjust from 1 to 100 mH using Interact and the mouse wheel.","price":14,"space":3,"rarity":"Uncommon","pins":["1","2"]}
	entries.signal_transformer={"name":"2:1 signal transformer","category":"Basic","kind":"signal_transformer","unit":"","rating":"Two isolated, magnetically coupled windings with winding resistance.","price":26,"space":5,"rarity":"Rare","pins":["P+","P−","S+","S−"]}
	entries.photodiode={"name":"Photodiode","category":"Basic","kind":"photodiode","value":.0008,"unit":"A","rating":"Up to 0.8 mA photocurrent. Adjust simulated light with Interact and the mouse wheel.","price":8,"space":1,"rarity":"Uncommon","pins":["Anode","Cathode"]}
	entries.solar_panel={"name":"Mini solar panel","category":"Basic","kind":"solar_panel","value":.065,"unit":"A","rating":"Up to 65 mA at full simulated light. Larger body and kit space than a photodiode.","price":22,"space":6,"rarity":"Rare","pins":["+","−"]}
	entries.seven_segment={"name":"Seven-segment LED · common cathode","category":"Output","kind":"seven_segment","unit":"V","rating":"Educational nine-pin module: a–g, decimal, common cathode. Series resistors required.","price":12,"space":4,"rarity":"Uncommon","pins":["a","b","c","d","e","f","g","DP","COM"]}
	for entry in [["hc00","74HC00","NAND"],["hc08","74HC08","AND"],["hc32","74HC32","OR"],["hc86","74HC86","XOR"],["hc04","74HC04","NOT"]]:
		var names: Array=["1A","1B","1Y","2A","2B","2Y","GND","3Y","3A","3B","4Y","4A","4B","VCC"]
		if entry[2]=="NOT":names=["1A","1Y","2A","2Y","3A","3Y","GND","4Y","4A","5Y","5A","6Y","6A","VCC"]
		entries[entry[0]]={"name":entry[1]+" "+entry[2],"category":"IC","kind":"logic","gate":entry[2],"unit":"V","rating":"Approximate 2–6 V logic · 40 Ω outputs · 0.5 ms update; not a timing-accurate silicon model","price":8,"space":3,"rarity":"Uncommon","pins":names}
	entries.lv_mcu={"name":"LV Micro · programmable controller","category":"PCB","kind":"controller","unit":"V","rating":"LabVolt Script (not Arduino/Pico). VIN 2.7–5.5 V; D0/D1 I/O, A0 ADC, PWM 50 Hz; 40 Ω output drivers.","price":20,"space":5,"rarity":"Uncommon","pins":["VIN","GND","D0","D1","A0","PWM"]}
	entries.timer555={"name":"NE555 timer","category":"IC","kind":"timer555","unit":"V","rating":"Behavioral 4.5–16 V timer; control divider, trigger latch and discharge. 0.5 ms resolution, 40 Ω output. No silicon timing/thermal model.","price":8,"space":3,"rarity":"Common","pins":["GND","TRIG","OUT","RESET","CTRL","THRES","DISCH","VCC"]}
	entries.flip74={"name":"74HC74 dual D flip-flop","category":"IC","kind":"flip74","unit":"V","rating":"Behavioral 2–6 V positive-edge flip-flops, asynchronous active-low preset/clear. 0.5 ms resolution, 40 Ω drivers.","price":8,"space":3,"rarity":"Uncommon","pins":["1CLR","1D","1CLK","1PRE","1Q","1/Q","GND","2/Q","2Q","2PRE","2CLK","2D","2CLR","VCC"]}
	entries.spi_display={"name":"LV Text Display · 16 × 2","category":"Output","kind":"spi_display","unit":"V","rating":"Educational 2–6 V SPI display. CS low, rising CLK samples DATA MSB first. First byte: cell 0–31; following bytes: ASCII. Not HD44780 compatible.","price":18,"space":5,"rarity":"Uncommon","pins":["VCC","GND","DATA","CLK","/CS"]}
	for variant in [["led_green","Green LED",2.1,"62e68d"],["led_blue","Blue LED",3.,"69aaff"],["led_yellow","Yellow LED",2.,"ffd45b"]]:
		entries[variant[0]]={"name":variant[1],"category":"Output","kind":"LED","value":variant[2],"vf":variant[2],"ron":10,"color":variant[3],"unit":"V","rating":"20 mA nominal · series resistor required","price":3,"space":1,"rarity":"Common","pins":["Anode (A)","Cathode (K)"]}
	entries.buzzer={"name":"Active buzzer · 440 Hz","category":"Output","kind":"buzzer","unit":"V","rating":"3–5 V active sounder; 1 kΩ electrical load. Volume follows applied voltage.","price":6,"space":2,"rarity":"Common","pins":["+","−"]}
	for polarity in ["NPN","PNP"]:
		entries[polarity.to_lower()]={"name":polarity+" transistor · educational","category":"Basic","kind":"bjt","polarity":polarity,"unit":"A","rating":"Piecewise-linear two-junction transport model. βF 99, βR 1, junction threshold 0.65 V. No capacitance, temperature, avalanche or Early effect; not a specific commercial part.","price":4,"space":2,"rarity":"Common","pins":["Collector","Base","Emitter"]}
	entries.shift595={"name":"74HC595 serial output register","category":"IC","kind":"shift595","unit":"V","rating":"Behavioral 2–6 V, 0.5 ms resolution. Separate shift/latch clocks, asynchronous shift clear, tri-state outputs and cascade. 40 Ω drivers; not silicon timing accurate.","price":10,"space":4,"rarity":"Uncommon","pins":["QB","QC","QD","QE","QF","QG","QH","GND","QH serial","/SRCLR","SRCLK","RCLK","/OE","SER","QA","VCC"]}
	entries.speaker={"name":"Passive speaker · 8 Ω","category":"Output","kind":"speaker","unit":"V","rating":"8 Ω resistive educational load; sound follows circuit waveform, DC removed. 2 kHz sampling; use tones below 800 Hz. No mechanical resonance model.","price":8,"space":3,"rarity":"Common","pins":["+","−"]}
	entries.opamp={"name":"Rail-limited op-amp · educational","category":"IC","kind":"opamp","unit":"V","rating":"DC ideal amplifier: gain 100000, 50 Ω output, 10 MΩ inputs, output bounded by supply rails. No bandwidth, slew rate or supply-current model; not a commercial chip.","price":8,"space":3,"rarity":"Common","pins":["IN+","IN−","V+","V−","OUT"]}
	entries.merge(preload("res://scripts/component_models/catalog.gd").all(),false)
	entries.merge(preload("res://scripts/io_devices/catalog.gd").all(),false)
	entries.merge(preload("res://scripts/commercial_devices/catalog.gd").all(),false)
	entries.merge(preload("res://scripts/firmware_backends/native_boards.gd").catalog(),false)
	entries.merge(preload("res://scripts/physical_resistors.gd").catalog_entries(),false)
	var tiers := {"Rare":["ssd1306","hd44780_20x4","ws2812","native_nano"],"Epic":["native_uno","pca9685","xpt2046"],"Legendary":["native_pico","ili9341"]}
	for tier in tiers:
		for id in tiers[tier]:
			if entries.has(id):entries[id].rarity=tier
	return entries
