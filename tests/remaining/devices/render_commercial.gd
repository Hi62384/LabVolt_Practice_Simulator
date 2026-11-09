extends SceneTree
## Reserved-window renderer harness; screenshot is produced by actual model handlers.
const LCD=preload("res://scripts/commercial_devices/hd44780.gd")
const R=preload("res://scripts/commercial_devices/registers.gd")
const Publication=preload("res://scripts/io_devices/replication.gd")
const Surface=preload("res://scripts/io_devices/surface.gd")
func _initialize() -> void:call_deferred("run")
func run() -> void:
	root.size=Vector2i(1280,720)
	var background:=ColorRect.new();background.color=Color("17232d");background.size=Vector2(1280,720);root.add_child(background)
	var lcd:=LCD.initial();lcd.powered=true;lcd.time=.02
	LCD.write(lcd,false,0x0C);lcd.time+=.00004
	for byte in "Circuit timer".to_ascii_buffer():LCD.write(lcd,true,byte);lcd.time+=.00004
	LCD.write(lcd,false,0xC0);lcd.time+=.00004
	for byte in "00:42  READY".to_ascii_buffer():LCD.write(lcd,true,byte);lcd.time+=.00004
	var oled:=R.initial("ssd1306");oled.powered=true;R.ssd_command(oled,0xAF)
	for page in 8:
		R.ssd_command(oled,0xB0+page)
		for x in 128:R.ssd_data(oled,255 if x==page*16 else 1<<(x%8))
	var tft:=R.initial("ili9341");tft.powered=true;tft.time=1.;R.tft(tft,false,0x11);tft.time=1.2;R.tft(tft,false,0x29);R.tft(tft,false,0x3A);R.tft(tft,true,0x55);R.tft(tft,false,0x2C)
	for pixel in 240*64:
		var value: int=[0xF800,0x07E0,0x001F][(pixel%240)/80]
		R.tft(tft,true,value>>8);R.tft(tft,true,value&255)
	var index:=0
	for pair in [["hd44780",lcd],["ssd1306",oled],["ili9341",tft]]:
		var view=Surface.new();root.add_child(view);view.position=Vector2(30+index*410,80);view.size=Vector2(380,500);view.present(pair[0],Publication.public_state(pair[0],pair[1]))
		var label:=Label.new();label.text=pair[0];label.position=Vector2(30+index*410,30);label.add_theme_font_size_override("font_size",25);root.add_child(label)
		index+=1
	await process_frame;await process_frame;await RenderingServer.frame_post_draw
	var path:=ProjectSettings.globalize_path("res://../work/wave3/commercial-preview.png")
	var error:=root.get_texture().get_image().save_png(path)
	print("RENDER commercial capture=",error," path=",path)
	for child in root.get_children():child.queue_free()
	await process_frame;await process_frame
	quit(0 if error==OK else 1)
