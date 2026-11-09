extends RefCounted
const PINS={"hd44780":["VSS","VDD","VO","RS","RW","E","D0","D1","D2","D3","D4","D5","D6","D7","LED+","LED-"],"ssd1306":["VCC","GND","SCL","SDA","RES","SA0"],"ili9341":["VCC","GND","SCK","MOSI","MISO","CS","DC","RESET"],"xpt2046":["VCC","GND","SCK","DIN","DOUT","CS","PENIRQ"],"ws2812":["VCC","GND","DIN","DOUT"],"oscillator":["VCC","GND","OUT","OE"],"quartz":["X1","X2"],"lm358":["OUT1","IN1-","IN1+","V-","IN2+","IN2-","OUT2","V+"],"lm324":["OUT1","IN1-","IN1+","V+","IN2+","IN2-","OUT2","OUT3","IN3-","IN3+","V-","IN4+","IN4-","OUT4"]}
static func pins(kind: String) -> Array:
	if kind=="hd44780_20x4":kind="hd44780"
	if kind=="pca9685":
		return ["A0","A1","A2","A3","A4","A5","LED0","LED1","LED2","LED3","LED4","LED5","LED6","VSS","LED7","LED8","LED9","LED10","LED11","LED12","LED13","LED14","LED15","OE","SCL","SDA","EXTCLK","VDD"]
	return PINS.get(kind,[]).duplicate()
static func logical_nodes(kind: String,n: Array) -> Array:
	if kind!="pca9685":return n
	var order: Array=[27,13,24,25,23,0,1,2,3,4,5,6,7,8,9,10,11,12,14,15,16,17,18,19,20,21,22,26]
	var mapped: Array=[]
	for index in order:mapped.append(n[index])
	return mapped
static func supports(kind: String) -> bool:return kind in ["pca9685","hd44780_20x4"] or PINS.has(kind)
static func all() -> Dictionary:
	var out:={}
	for row in [
		["hd44780","HD44780 · 16 × 2 LCD","Output","4.5–5.5 V parallel4/8bit,80byteDDRAM,64byteCGRAM,busy/address reads.37us commands/1.52ms clear.3V backlight LED needs series resistor. Original glyphs; no copied CGROM."],
		["ssd1306","SSD1306 · 128 × 64 OLED","Output","2.7–3.6 V I2C0x3C/3D,1024byteGDDRAM,page/horizontal/vertical addressing,contrast/invert/remap/display commands. External pullups; RES active-low."],
		["ili9341","ILI9341 · SPI TFT 240 × 320","Output","2.7–3.6 V4wireSPI mode0; RGB565/RGB666 windowed RAM writes,MADCTL,reset/sleep/display. Readback/gamma/scroll/parallel modes not implemented."],
		["xpt2046","XPT2046 · resistive touch module","Input","2.7–3.6 V SPI mode0,12bitX/Y/Z1/Z2 and active-low PENIRQ. Host panel touches;400ohm sheet/100ohm pressed contact. No temperature/battery ADC,8bit/pipelined modes."],
		["ws2812","WS2812B · 8 pixel GRB strip","Output","4.5–5.5 V,GRB24bit,0high0.25–0.55us/1high0.65–0.95us,1.25us bit±0.3us,reset≥50us. Legacy timing revision; submicrosecond electrical edges required."],
		["pca9685","PCA9685 · 16 channel PWM","IC","2.3–5.5 V,I2C0x40+addresspins,12bitPWM,MODE1/2,prescale,full-on/off,auto-increment,OE.25MHz internal or edge-counted EXTCLK; selectexternal whileasleep."],
		["oscillator","1 MHz enabled oscillator module","PCB","2.7–5.5 V,1MHz,50% nominal duty,OE high enables40ohmoutput. Edge scheduling needed; fixed-step aliasing is reported."],
		["quartz","32.768 kHz quartz crystal","Basic","Passive BVD equivalent:8H motional inductance,computed2.95pF series capacitance,35kohm ESR,1.2pF shunt. Requires an actual sustaining oscillator circuit; not a clock source."],
		["lm358","LM358 dual op-amp","IC","Educational DC commercial-pin model,3–30V supply,common-modeV-..V+-1.5V,100000gain,50ohmoutput,outputheadroom1.5V/20mV. No slew/temperature/SPICE accuracy."],
		["lm324","LM324 quad op-amp","IC","Educational DC commercial-pin model,3–30V supply,common-modeV-..V+-1.5V,100000gain,50ohmoutput,outputheadroom1.5V/20mV. No slew/temperature/SPICE accuracy."]]:
		out[row[0]]={"name":row[1],"kind":row[0],"category":row[2],"rating":row[3],"pins":pins(row[0]),"unit":"","price":24,"space":5,"rarity":"Uncommon","io_version":1,"commercial_version":1}
	out.hd44780.columns=16;out.hd44780.rows=2
	out.hd44780_20x4=out.hd44780.duplicate(true);out.hd44780_20x4.name="HD44780 · 20 × 4 LCD";out.hd44780_20x4.columns=20;out.hd44780_20x4.rows=4
	return out
