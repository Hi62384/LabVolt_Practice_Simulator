extends SceneTree
const P=preload("res://scripts/commercial_devices/peripherals.gd")
const C=preload("res://scripts/commercial_devices/catalog.gd")
const Publish=preload("res://scripts/io_devices/replication.gd")
const Surface=preload("res://scripts/io_devices/surface.gd")
var kind:=""
var nodes: Array=[]
var v:={}
var state:={}
var controls:={}
var supply:=3.3
var checks:=0
var failed:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failed+=1;printerr("FAIL "+label)
func setup(type: String) -> void:
	kind=type;nodes=[];v={};state={};controls={};supply=5.0 if type in ["hd44780","ws2812"] else 3.3
	for i in C.pins(kind).size():nodes.append(str(i));v[str(i)]=0.0
	v["1" if kind=="hd44780" else "0"]=supply
	if kind=="ssd1306":v["4"]=supply
	if kind=="ili9341":v["7"]=supply;v["5"]=supply
	tick(.0001)
func tick(dt: float=.000001) -> void:
	state=P.tick({"id":"test","model":kind,"nodes":nodes,"logical_pins":true,"control":controls}, {"ok":true,"v":v},state,dt)
func wire(scl: bool,sda: bool) -> bool:
	v["2"]=supply if scl else 0.0
	v["3"]=supply if sda and not state.get("bus",{}).get("low",false) else 0.0
	tick()
	return float(v["3"])>supply*.7
func start() -> void:wire(true,true);wire(true,false)
func stop() -> void:wire(false,false);wire(true,false);wire(true,true)
func send(byte: int) -> bool:
	for bit in 8:
		wire(false,(byte&(128>>bit))!=0);wire(true,(byte&(128>>bit))!=0)
	wire(false,true);var ack:=not wire(true,true);wire(false,true)
	return ack
func receive(ack: bool) -> int:
	var value:=0
	for bit in 8:
		value=(value<<1)|(1 if wire(true,true) else 0);wire(false,true)
	wire(false,not ack);wire(true,not ack);wire(false,true)
	return value
func lcd(byte: int,rs: bool,four: bool=false) -> void:
	v["3"]=5.0 if rs else 0.0
	for nibble in ([byte&240,(byte<<4)&240] if four else [byte]):
		for bit in 8:v[str(6+bit)]=5.0 if int(nibble)&(1<<bit) else 0.0
		v["5"]=0.0;tick(.000001);v["5"]=5.0;tick(.000001);v["5"]=0.0;tick(.000001)
	tick(.00004)
func spi(byte: int,data: bool=true) -> void:
	v["5"]=0.0
	if kind=="ili9341":v["6"]=supply if data else 0.0
	for bit in 8:
		v["2"]=0.;v["3"]=supply if byte&(128>>bit) else 0.;tick()
		v["2"]=supply;tick()
	v["2"]=0.;tick()
func _initialize() -> void:
	setup("hd44780");tick(.01)
	lcd(0x20,false);lcd(0x28,false,true);lcd(0x0C,false,true)
	for byte in "HELLO 4-BIT".to_ascii_buffer():lcd(byte,true,true)
	check(Publish.public_state(kind,state).lines[0].begins_with("HELLO 4-BIT"),"raw LCD4bit initialization and text")
	lcd(0xA7,false,true);lcd(ord("Z"),true,true)
	check(state.address==0x40,"HD two-line DDRAM wraps39to64")
	var before:=state.duplicate(true)
	check(P.tick({"model":kind,"nodes":nodes},{"ok":true,"v":v},state,-1)==before,"negative host time freezes")
	v["1"]=0.;tick();check(not state.powered,"LCD power loss")
	setup("ssd1306");wire(true,true);start()
	check(not send(0x7A),"OLED wrong address NACK");stop();start()
	check(send(0x78),"OLED correct address ACK")
	check(send(0x00) and send(0xAF),"OLED control-command stream ACK")
	stop();start();check(send(0x78) and send(0x40) and send(0xA5),"OLED framebuffer rawI2C ACK")
	stop();check(state.ram[0]==0xA5 and state.display,"OLED actual rawI2C state")
	check(Publish.public_state(kind,state).ram[0]==0xA5,"OLED renderer gets actual RAM")
	v["4"]=0.;tick();v["4"]=supply;tick();check(state.ram[0]==0 and not state.display,"OLED RESET clearsstate")
	v["2"]=5.;tick();check(state.has("io_fault"),"OLED5V input on3.3V logic rejected")
	v["2"]=1.65;tick();check(state.has("io_fault"),"undefinedCMOS clock voltage cannotdecodebits")
	v["0"]=NAN;tick();check(not state.powered,"nonfinite supply cannotpowerdevice")
	setup("pca9685");wire(true,true);start();check(send(0x80) and send(6) and send(0x34),"PCA electrical register write")
	stop();start();send(0x80);send(6);start();check(send(0x81),"PCA repeated-start readaddress ACK")
	check(receive(false)==0x34,"PCA raw open-drain readback")
	stop()
	# Select EXTCLK while asleep, prescale4, channel0 ON0/OFF2; then wake.
	for transaction in [[0,0x10],[0,0x50],[254,3],[6,0],[7,0],[8,2],[9,0],[0,0x40]]:
		start();check(send(0x80) and send(transaction[0]) and send(transaction[1]),"PCA externalclock configuration ACK");stop()
	check(preload("res://scripts/commercial_devices/registers.gd").pwm(state,0)==1,"PCA external startsatONcount")
	for edge in 8:v["27"]=0.;tick();v["27"]=supply;tick()
	check(preload("res://scripts/commercial_devices/registers.gd").pwm(state,0)==0 and state.get("external_count",-1)==2,"PCA8actualexternaledges advance2prescaledcounts")
	start();send(0x80);send(7);send(16)
	check(preload("res://scripts/commercial_devices/registers.gd").pwm(state,0)==0,"PCA defaultOCH holdsPWMuntilSTOP")
	stop();check(preload("res://scripts/commercial_devices/registers.gd").pwm(state,0)==1,"PCA STOP latchesfullON")
	start();send(0x80);send(1);send(12);stop()
	start();send(0x80);send(7);send(0)
	check(preload("res://scripts/commercial_devices/registers.gd").pwm(state,0)==0,"PCA OCH1 latchesonACKbeforeSTOP");stop()
	start();check(send(0) and send(6),"PCA generalcall software reset ACK");stop()
	check(state.registers[0]==1 and state.registers[254]==30 and state.registers[8]==0,"PCA reset restores registerdefaults")
	start();check(send(0xE0),"PCA default ALLCALL writeaddressACK");stop()
	setup("ili9341");spi(0x11,false);spi(0x29,false);spi(0x3A,false);spi(0x55)
	spi(0x2C,false);spi(0x07);spi(0xE0)
	check(state.gram.get("0",[])[0]==0x07E0 and state.display and not state.sleep,"TFT rawSPI greenpixel and state")
	var published:=Publish.public_state(kind,state)
	check(published.gram["0"][0]==0x07E0 and not published.has("time"),"TFT publication actualpixel no ticktime")
	check(published.sleep,"TFT120ms sleepout delay blocksrender")
	for i in 13:tick(.01)
	check(not Publish.public_state(kind,state).sleep,"TFT hosttime wakesdisplay")
	setup("xpt2046");controls={"x":.25,"y":.75,"pressed":true}
	v["5"]=supply;tick();spi(0xD0)
	var conversion:=0
	for bit in 16:
		v["3"]=0.;v["2"]=supply;tick();conversion=(conversion<<1)|(1 if state.miso else 0)
		v["2"]=0.;tick()
	check(conversion==(1024<<3),"XPT2046 rawSPI12bitX conversion framing")
	check(state.control.pressed and absf(float(state.control.y)-.75)<.001,"touch published state actualhostcontrols")
	setup("ws2812")
	v["2"]=0.;tick(.00006)
	var low_duration:=0.000001
	for pixel in 8:
		for byte in [0x20,0x80,0x40]:
			for bit in 8:
				var high: bool=(byte&(128>>bit))!=0
				v["2"]=5.;tick(low_duration)
				v["2"]=0.;tick(.0000008 if high else .00000035)
				low_duration=.00000045 if high else .0000009
	v["2"]=0.;tick(.00006)
	check(state.get("pixels",[]).size()==24,"WS2812 raw timing frame latched")
	if state.get("pixels",[]).size()==24:check(state.pixels.slice(0,3)==[128,32,64],"WS2812 GRB wire toRGB render")
	check(state.get("frames",0)==1,"WS2812 one resetoneframe")
	var original: Array=state.pixels.duplicate()
	#24bits update ONLY firstpixel; remaining seven retainprevious latcheddata.
	low_duration=.000001
	for byte in [0,0,255]:
		for bit in 8:
			var high: bool=(byte&(128>>bit))!=0
			v["2"]=5.;tick(low_duration);v["2"]=0.;tick(.0000008 if high else .00000035)
			low_duration=.00000045 if high else .0000009
	tick(.00006)
	check(state.pixels.slice(0,3)==[0,0,255] and state.pixels.slice(3)==original.slice(3),"WS partialstrip update preservesremainingpixels")
	var frames:=int(state.frames);var saved: Array=state.pixels.duplicate()
	for bit in 24:v["2"]=5.;tick(.000001);v["2"]=0.;tick(.000004)
	tick(.00006)
	check(state.frames==frames and state.pixels==saved and state.get("error_frames",0)>0,"invalidWS timings cannot manufactureframe")
	var after:=state.duplicate(true);tick(0.0)
	check(state==after,"same-time resampledoesnot advancehosttimeorframes")
	print("EDGES checks=",checks," failures=",failed)
	quit(1 if failed else 0)
