extends RefCounted
## Engine-provided font for ASCII. Custom HD CGRAM is drawn from actual row bits.
## No manufacturer's ROM glyphs or external bitmap/font asset is copied.
static func draw(canvas: Control,kind: String,s: Dictionary) -> void:
	canvas.draw_rect(Rect2(4,40,248,176),Color("071016"))
	if not s.get("powered",false):return
	if s.has("io_fault"):
		canvas.draw_string(ThemeDB.fallback_font,Vector2(12,238),"Check logic voltage",HORIZONTAL_ALIGNMENT_LEFT,-1,18,Color("f3a163"))
	if kind=="hd44780" and s.get("display",false):
		canvas.draw_rect(Rect2(4,40,248,176),Color("102619").lerp(Color("355b2f"),float(s.get("backlight",0))))
		var cells: Array=s.get("cells",[]);var cg: Array=s.get("cgram",[])
		var columns:=int(s.get("columns",16));var rows:=int(s.get("rows",2))
		var font_size:=18
		while font_size>8 and ThemeDB.fallback_font.get_string_size("M",HORIZONTAL_ALIGNMENT_LEFT,-1,font_size).x>236.0/columns-1:font_size-=1
		for i in mini(columns*rows,cells.size()):
			var x:=10+(i%columns)*(236.0/columns);var y:=50+(i/columns)*(154/rows);var value:=int(cells[i])
			if value<16 and cg.size()==64:
				for row in 8:
					for col in 5:
						if int(cg[(value&7)*8+row])&(16>>col):canvas.draw_rect(Rect2(x+col*2,y+row*3,2,3),Color("9fcf7a"))
			elif value>=32 and value<=126:canvas.draw_string(ThemeDB.fallback_font,Vector2(x,y+22),String.chr(value),HORIZONTAL_ALIGNMENT_LEFT,-1,font_size,Color("b9dc8a"))
			var base: int=[0,64,20,84][i/columns]
			var address: int=(base&64)+posmod((base&63)+(i%columns)+int(s.get("shift",0)),40)
			if address==int(s.get("address",-1)):
				if s.get("cursor",false):canvas.draw_rect(Rect2(x,y+25,10,2),Color("b9dc8a"))
				if s.get("blink",false):canvas.draw_rect(Rect2(x,y+2,10,24),Color("b9dc8a"))
	elif kind=="ssd1306" and s.get("display",false):
		var ram: Array=s.get("ram",[])
		if ram.size()!=1024:return
		for y in 64:
			for x in 128:
				var row:=posmod(y+int(s.get("start_line",0))-int(s.get("offset",0)),64)
				if s.get("com_reverse",false):row=63-row
				var col:=127-x if s.get("segment_remap",false) else x
				var on: bool=s.get("all_on",false) or (int(ram[(row/8)*128+col])&(1<<(row%8)))!=0
				if s.get("invert",false):on=not on
				if on:canvas.draw_rect(Rect2(x*1.9+6,y*2.5+46,1.9,2.5),Color(0.5,1,0.9)*(0.1+float(s.get("contrast",127))/283.))
	elif kind=="ili9341" and s.get("display",false) and not s.get("sleep",true):
		var tiles: Dictionary=s.get("gram",{})
		for key in tiles:
			var index:=int(key);var tile: Array=tiles[key]
			for pixel in mini(256,tile.size()):
				var value:=int(tile[pixel]);var x: int=(index%15)*16+pixel%16;var y: int=(index/15)*16+pixel/16
				var color:=Color(float((value>>11)&31)/31.,float((value>>5)&63)/63.,float(value&31)/31.)
				if value&0x1000000:color=Color(float((value>>16)&252)/252.,float((value>>8)&252)/252.,float(value&252)/252.)
				if s.get("invert",false):color=Color(1.-color.r,1.-color.g,1.-color.b,1.)
				canvas.draw_rect(Rect2(44+x*.7,16+y*.7,.72,.72),color)
	elif kind=="ws2812":
		var pixels: Array=s.get("pixels",[])
		for i in 8:
			var color:=Color.BLACK
			if pixels.size()==24:color=Color(float(pixels[i*3])/255.,float(pixels[i*3+1])/255.,float(pixels[i*3+2])/255.)
			canvas.draw_circle(Vector2(35+(i%4)*62,90+(i/4)*70),22,color)
	elif kind=="xpt2046":
		var c: Dictionary=s.get("control",{})
		canvas.draw_string(ThemeDB.fallback_font,Vector2(20,30),"Resistive touch panel",HORIZONTAL_ALIGNMENT_LEFT,-1,19,Color.WHITE)
		if c.get("pressed",false):canvas.draw_circle(Vector2(float(c.get("x",.5)),float(c.get("y",.5)))*220+Vector2(18,18),8,Color("edb15f"))
