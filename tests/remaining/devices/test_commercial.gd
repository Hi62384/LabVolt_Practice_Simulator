extends SceneTree
const P=preload("res://scripts/commercial_devices/peripherals.gd")
const C=preload("res://scripts/commercial_devices/catalog.gd")
const R=preload("res://scripts/commercial_devices/registers.gd")
const LCD=preload("res://scripts/commercial_devices/hd44780.gd")
const Controls=preload("res://scripts/io_devices/controls.gd")
const Catalog=preload("res://scripts/electronics_catalog.gd")
const Models=preload("res://scripts/device_models.gd")
var checks:=0
var failed:=0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value:failed+=1;printerr("FAIL "+label)
func _initialize() -> void:
	for kind in C.all():
		check(Catalog.all().has(kind),"catalog "+kind)
		var names: Array=Catalog.all()[kind].pins;var nodes: Array=[]
		for i in names.size():nodes.append("n"+str(i))
		check(not Models.expand(Catalog.all()[kind],kind,nodes,{},{}).is_empty(),"solver expansion "+kind)
	var s:=LCD.initial();s.time=.02
	LCD.write(s,false,0x38);s.time+=.00004;LCD.write(s,false,0x0C);s.time+=.00004
	for byte in "HELLO".to_ascii_buffer():LCD.write(s,true,byte);s.time+=.00004
	check(LCD.text(s)[0].begins_with("HELLO"),"HD44780 text from DDRAM")
	LCD.write(s,false,0xC0);s.time+=.00004;LCD.write(s,true,ord("A"));s.time+=.00004
	check(LCD.text(s)[1].begins_with("A"),"second-row64address")
	LCD.write(s,false,1);check(LCD.read(s,false)&128!=0,"busy flag")
	LCD.write(s,true,ord("X"));check(s.ram[0]==32,"busy rejects early writes")
	s.time+=.002;LCD.write(s,false,0x40);s.time+=.00004;LCD.write(s,true,31)
	check(s.cgram[0]==31,"custom glyph RAM")
	s.columns=20;s.rows=4;s.ram[20]=ord("3");s.ram[84]=ord("4")
	check(LCD.text(s)[2].begins_with("3") and LCD.text(s)[3].begins_with("4"),"20x4 actual DDRAM rowmapping")
	var prior:=s.duplicate();s.time+=.00004;LCD.write(s,false,1)
	check(prior.ram[20]==ord("3") and s.ram[20]==32,"LCD copyonwrite protects prior publishedruntime")
	var oled:=R.initial("ssd1306")
	for byte in [0x20,0,0x21,2,3,0x22,1,2,0xAF]:R.ssd_command(oled,byte)
	for byte in [0x55,0xAA,0xFF]:R.ssd_data(oled,byte)
	check(oled.ram[130]==0x55 and oled.ram[131]==0xAA and oled.ram[258]==0xFF,"OLED horizontal range/page wrapping")
	check(oled.display,"OLED actual display command")
	var pwm:=R.initial("pca9685");R.i2c_start("pca9685",pwm,false)
	R.i2c_write("pca9685",pwm,254);check(not R.i2c_write("pca9685",pwm,121),"prescale write while awake rejected")
	R.i2c_start("pca9685",pwm,false);R.i2c_write("pca9685",pwm,0);R.i2c_write("pca9685",pwm,0x30)
	R.i2c_start("pca9685",pwm,false);R.i2c_write("pca9685",pwm,254);check(R.i2c_write("pca9685",pwm,121),"sleep permits prescale")
	R.i2c_start("pca9685",pwm,false);R.i2c_write("pca9685",pwm,0);R.i2c_write("pca9685",pwm,0x20)
	R.i2c_start("pca9685",pwm,false);R.i2c_write("pca9685",pwm,6)
	for byte in [0,0,0,8]:R.i2c_write("pca9685",pwm,byte)
	R.i2c_stop("pca9685",pwm)
	pwm.phase_time=0.0;pwm.time=.001;check(R.pwm(pwm,0)==1,"PWM on at count0")
	pwm.phase_time=2048.*122./25000000.;check(R.pwm(pwm,0)==0,"PWM off at count2048")
	var tft:=R.initial("ili9341")
	R.tft(tft,false,0x3A);R.tft(tft,true,0x55);R.tft(tft,false,0x2C)
	R.tft(tft,true,0xF8);R.tft(tft,true,0)
	check(tft.gram["0"][0]==0xF800 and tft.x==1,"TFT real RGB565 RAM pixel")
	R.tft(tft,false,0x3A);R.tft(tft,true,0x66);R.tft(tft,false,0x2C)
	for byte in [4,8,12]:R.tft(tft,true,byte)
	check(tft.gram["0"][0]==(0x1000000|(4<<16)|(8<<8)|12),"TFT RGB666 retainsall6bitsperchannel")
	check(Controls.apply("xpt2046",Controls.defaults("xpt2046"),{"op":"touch","x":.25,"y":.75,"pressed":true,"revision":0}).ok,"touch host controls")
	var mapped: Array=C.logical_nodes("pca9685",C.pins("pca9685"))
	check(mapped[0]=="VDD" and mapped[1]=="VSS" and mapped[11]=="LED0" and mapped[26]=="LED15","PCA actualTSSOP pinmap")
	print("COMMERCIAL checks=",checks," failures=",failed)
	quit(1 if failed else 0)
