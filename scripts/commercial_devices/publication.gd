extends RefCounted
const LCD=preload("res://scripts/commercial_devices/hd44780.gd")
static func public_state(kind: String,s: Dictionary) -> Dictionary:
	var out:={"powered":bool(s.get("powered",false)) and not s.get("reset",false),"control":s.get("control",{}).duplicate(true)}
	if not out.powered:return out
	if str(s.get("io_fault",""))!="":out.io_fault=s.io_fault
	match kind:
		"hd44780":
			out.display=s.get("display",false);out.lines=LCD.text(s);out.cgram=s.get("cgram",[]).duplicate();out.cells=[]
			out.columns=int(s.get("columns",16));out.rows=int(s.get("rows",2))
			for row in out.rows:
				for col in out.columns:
					var base: int=[0,64,20,84][row]
					out.cells.append(s.ram[(base&64)+posmod((base&63)+col+int(s.shift),40)])
			out.cursor=s.get("cursor",false);out.address=s.get("address",0)
			out.shift=s.get("shift",0);out.blink=bool(s.get("blink",false)) and fposmod(float(s.get("time",0)),1.0)<.5
			out.backlight=roundf(clampf(float(s.get("backlight",0)),0,1)*255.)/255.
		"ssd1306":
			for key in ["ram","display","invert","all_on","contrast","segment_remap","com_reverse","start_line","offset"]:out[key]=s.get(key,false)
		"ili9341":
			for key in ["gram","display","sleep","invert","madctl"]:out[key]=s.get(key,false)
			out.sleep=bool(s.get("sleep",true)) or float(s.get("time",0))<float(s.get("ready_at",0))
		"ws2812":out.pixels=s.get("pixels",[]).duplicate()
		"pca9685":out.external_clock=(int(s.get("registers",[0])[0])&64)!=0
		"oscillator":out.undersampled=s.get("undersampled",false)
	return out
