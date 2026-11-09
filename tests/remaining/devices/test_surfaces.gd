extends SceneTree
const Surface=preload("res://scripts/io_devices/surface.gd")
const Physical=preload("res://scripts/io_devices/physical_surface.gd")
const LCD=preload("res://scripts/commercial_devices/hd44780.gd")
const R=preload("res://scripts/commercial_devices/registers.gd")
const Publication=preload("res://scripts/io_devices/replication.gd")
const Controls=preload("res://scripts/io_devices/controls.gd")
var checks:=0
var failed:=0
func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:failed+=1;printerr("FAIL "+label)
func _initialize() -> void:call_deferred("run")
func run() -> void:
	var lcd:=LCD.initial();lcd.powered=true;lcd.time=.02
	LCD.write(lcd,false,0x0C);lcd.time+=.00004
	for byte in "REAL LCD TEXT".to_ascii_buffer():LCD.write(lcd,true,byte);lcd.time+=.00004
	var oled:=R.initial("ssd1306");oled.powered=true;R.ssd_command(oled,0xAF);R.ssd_data(oled,0x55)
	var tft:=R.initial("ili9341");tft.powered=true;tft.time=.2;R.tft(tft,false,0x11);tft.time=.4;R.tft(tft,false,0x29);R.tft(tft,false,0x3A);R.tft(tft,true,0x55);R.tft(tft,false,0x2C);R.tft(tft,true,0xF8);R.tft(tft,true,0)
	for pair in [["hd44780",lcd],["ssd1306",oled],["ili9341",tft]]:
		var kind: String=pair[0];var published:=Publication.public_state(kind,pair[1])
		var a=Surface.new();root.add_child(a);a.size=Vector2(256,256);a.present(kind,published)
		var b=Physical.new();root.add_child(b);b.present(kind,published)
		check(a.live==b.surface.live,"same actual2D/physical state "+kind)
		check(b.physical_size.x>.119,"readable physical extent "+kind)
		a.present(kind,published);check(a.pending.is_empty(),"display no input injection "+kind)
		a.queue_free();b.queue_free()
	var touch=Surface.new();root.add_child(touch);touch.interact=true;touch.kind="xpt2046";touch.control=Controls.defaults("xpt2046");touch.dragging=true
	var commands: Array=[];touch.command_requested.connect(func(command):commands.append(command))
	touch.release_capture();check(commands.size()==1 and commands[0].op=="release","touch lostcapture releaseshostinput")
	touch.queue_free()
	check(not Publication.public_state("ssd1306",{"powered":true,"reset":true}).powered,"reset publication safe andblank")
	await process_frame;await process_frame
	print("SURFACES checks=",checks," failures=",failed)
	quit(1 if failed else 0)
