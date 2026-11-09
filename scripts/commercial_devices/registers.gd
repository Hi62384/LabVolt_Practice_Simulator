extends RefCounted
## Protocol command handlers shared by raw electrical frontends and bus adapters.
static func initial(kind: String) -> Dictionary:
	match kind:
		"ssd1306":
			var ram: Array=[];ram.resize(1024);ram.fill(0)
			return {"ram":ram,"display":false,"invert":false,"all_on":false,"column":0,"page":0,"col_start":0,"col_end":127,"page_start":0,"page_end":7,"address_mode":2,"contrast":127,"segment_remap":false,"com_reverse":false,"start_line":0,"offset":0,"pending":[],"command":0,"needed":0}
		"pca9685":
			var regs: Array=[];regs.resize(256);regs.fill(0);regs[0]=1;regs[1]=4;regs[2]=0xE2;regs[3]=0xE4;regs[4]=0xE8;regs[5]=0xE0;regs[254]=30
			return {"registers":regs,"output_registers":regs.duplicate(),"pointer":0,"expect_pointer":true,"phase_time":0.0,"extclk_unsupported":false,"external_count":0,"external_prescale":0,"ext_high":false}
		"ili9341":return {"gram":{},"command":0,"pending":[],"display":false,"sleep":true,"format":0x66,"madctl":0,"x0":0,"x1":239,"y0":0,"y1":319,"x":0,"y":0,"pixel_bytes":[],"unsupported":0}
	return {}

static func ssd_command(s: Dictionary,byte: int) -> void:
	if int(s.needed)>0:
		var pending: Array=s.pending.duplicate();pending.append(byte);s.pending=pending;s.needed-=1
		if int(s.needed)==0:
			match int(s.command):
				0x20:
					if int(pending[0])<=2:s.address_mode=int(pending[0])
				0x21:
					if int(pending[0])<=int(pending[1]) and int(pending[1])<=127:s.col_start=int(pending[0]);s.col_end=int(pending[1]);s.column=s.col_start
				0x22:
					if int(pending[0])<=int(pending[1]) and int(pending[1])<=7:s.page_start=int(pending[0]);s.page_end=int(pending[1]);s.page=s.page_start
				0x81:s.contrast=pending[0]
				0xD3:s.offset=int(pending[0])&63
		return
	match byte:
		0xAE:s.display=false
		0xAF:s.display=true
		0xA6:s.invert=false
		0xA7:s.invert=true
		0xA4:s.all_on=false
		0xA5:s.all_on=true
		0xA0,0xA1:s.segment_remap=byte==0xA1
		0xC0,0xC8:s.com_reverse=byte==0xC8
		0x20,0x81,0x8D,0xA8,0xD3,0xD5,0xD9,0xDA,0xDB:s.command=byte;s.needed=1;s.pending=[]
		0x21,0x22:s.command=byte;s.needed=2;s.pending=[]
		_:
			if byte>=0xB0 and byte<=0xB7:s.page=byte&7
			elif byte<=0x0F:s.column=(int(s.column)&0x70)|(byte&15)
			elif byte>=0x10 and byte<=0x1F:s.column=((byte&7)<<4)|(int(s.column)&15)
			elif byte>=0x40 and byte<=0x7F:s.start_line=byte&63
			else:s.unsupported=int(s.get("unsupported",0))+1

static func ssd_data(s: Dictionary,byte: int) -> void:
	var ram: Array=s.ram.duplicate();ram[int(s.page)*128+int(s.column)]=byte;s.ram=ram
	if int(s.address_mode)==1:
		s.page=int(s.page)+1
		if int(s.page)>int(s.page_end):s.page=s.page_start;s.column=int(s.column)+1
		if int(s.column)>int(s.col_end):s.column=s.col_start
	else:
		s.column=int(s.column)+1
		if int(s.column)>(int(s.col_end) if int(s.address_mode)==0 else 127):
			s.column=s.col_start if int(s.address_mode)==0 else 0
			if int(s.address_mode)==0:s.page=int(s.page)+1
		if int(s.page)>int(s.page_end):s.page=s.page_start

static func i2c_start(kind: String,s: Dictionary,reading: bool) -> void:
	if kind=="pca9685":s.expect_pointer=not reading
	else:s.control_pending=true;s.co=false;s.data_mode=false

static func i2c_write(kind: String,s: Dictionary,byte: int) -> bool:
	byte&=255
	if kind=="ssd1306":
		if s.get("control_pending",true):
			if byte&63:return false
			s.co=(byte&128)!=0;s.data_mode=(byte&64)!=0;s.control_pending=false
		else:
			if s.data_mode:ssd_data(s,byte)
			else:ssd_command(s,byte)
			if s.co:s.control_pending=true
		return true
	if kind=="pca9685":
		if s.expect_pointer:s.pointer=byte;s.expect_pointer=false;return true
		var pointer:=int(s.pointer)
		# PRE_SCALE/EXTCLK selection require SLEEP; EXTCLK stays latched until reset.
		if pointer==254 and (int(s.registers[0])&16)==0:return false
		if pointer==0:
			if byte&64 and (int(s.registers[0])&64)==0 and (int(s.registers[0])&16)==0:return false
			if int(s.registers[0])&64:byte|=64
			if int(s.registers[0])&16 and (byte&16)==0:s.ready_at=float(s.get("time",0))+(0.0 if byte&64 else .0005)
		var regs: Array=s.registers.duplicate()
		if pointer==254:byte=clampi(byte,3,255)
		regs[pointer]=byte;s.registers=regs
		if pointer>=250 and pointer<=253:
			for channel in 16:regs[6+channel*4+pointer-250]=byte
		if (pointer>=6 and pointer<=69) or (pointer>=250 and pointer<=253):s.output_pending=true
		else:
			var outputs: Array=s.get("output_registers",regs).duplicate();outputs[pointer]=byte;s.output_registers=outputs
		s.extclk_unsupported=false
		if int(regs[0])&32:s.pointer=(pointer+1)&255
		if pointer==0 and byte&128:s.phase_time=0.0;s.external_count=0;s.external_prescale=0
		return true
	return false

static func i2c_ack(kind: String,s: Dictionary) -> void:
	if kind=="pca9685" and int(s.registers[1])&8 and s.get("output_pending",false):s.output_registers=s.registers.duplicate();s.output_pending=false

static func i2c_stop(kind: String,s: Dictionary) -> void:
	if kind!="pca9685":return
	if s.get("pending_reset",false):
		var defaults:=initial(kind)
		for key in defaults:s[key]=defaults[key]
		s.pending_reset=false;s.ready_at=float(s.get("time",0))+.0005
	if s.get("output_pending",false):s.output_registers=s.registers.duplicate();s.output_pending=false

static func i2c_read(kind: String,s: Dictionary) -> int:
	if kind!="pca9685":return 255
	var byte:=int(s.registers[int(s.pointer)])
	if int(s.registers[0])&32:s.pointer=(int(s.pointer)+1)&255
	return byte

static func pwm(s: Dictionary,channel: int) -> int:
	var r: Array=s.get("output_registers",s.registers)
	if int(s.registers[0])&16 or float(s.get("time",0))<float(s.get("ready_at",0)):return 0
	var base:=6+channel*4
	var on: int=int(r[base])|((int(r[base+1])&15)<<8)
	var off: int=int(r[base+2])|((int(r[base+3])&15)<<8)
	if int(r[253])&16 or int(r[base+3])&16:return 1 if int(r[1])&16 else 0
	if int(r[251])&16 or int(r[base+1])&16:return 0 if int(r[1])&16 else 1
	var count: int=int(s.get("external_count",0)) if int(r[0])&64 else int(floor(float(s.phase_time)*25000000.0/(int(r[254])+1)))&4095
	var high:=posmod(count-on,4096)<posmod(off-on,4096)
	return (1 if not high else 0) if int(r[1])&16 else (1 if high else 0)

static func tft(s: Dictionary,data: bool,byte: int) -> void:
	if not data:
		s.command=byte;s.pending=[];s.pixel_bytes=[]
		match byte:
			0x01:
				var reset:=initial("ili9341")
				for key in reset:s[key]=reset[key]
			0x10:s.sleep=true
			0x11:s.sleep=false;s.ready_at=float(s.get("time",0))+.12
			0x28:s.display=false
			0x29:s.display=true
			0x2C:s.x=s.x0;s.y=s.y0
			0x20:s.invert=false
			0x21:s.invert=true
		return
	var command:=int(s.command)
	if command in [0x2A,0x2B]:
		var pending: Array=s.pending.duplicate();pending.append(byte);s.pending=pending
		if pending.size()==4:
			var start: int=(int(pending[0])<<8)|int(pending[1]);var end: int=(int(pending[2])<<8)|int(pending[3])
			var maximum: int=(320 if command==0x2A else 240) if int(s.madctl)&32 else (240 if command==0x2A else 320)
			if start<=end and end<maximum:
				if command==0x2A:s.x0=start;s.x1=end
				else:s.y0=start;s.y1=end
			s.pending=[]
	elif command==0x36:s.madctl=byte
	elif command==0x3A:s.format=byte
	elif command in [0x2C,0x3C]:
		if not int(s.format) in [0x55,0x66]:s.unsupported=int(s.unsupported)+1;return
		var pending: Array=s.pixel_bytes.duplicate();pending.append(byte);s.pixel_bytes=pending
		if pending.size()==(2 if int(s.format)==0x55 else 3):
			var color: int=(int(pending[0])<<8)|int(pending[1]) if pending.size()==2 else 0x1000000|((int(pending[0])&252)<<16)|((int(pending[1])&252)<<8)|(int(pending[2])&252)
			var x:=int(s.x);var y:=int(s.y)
			if int(s.madctl)&32:
				var swap:=x;x=y;y=swap
			if int(s.madctl)&64:x=239-x
			if int(s.madctl)&128:y=319-y
			if int(s.madctl)&8:
				color=(0x1000000|((color&255)<<16)|(color&65280)|((color>>16)&255)) if color&0x1000000 else ((color&31)<<11)|(color&2016)|((color>>11)&31)
			if x<0 or x>=240 or y<0 or y>=320:s.unsupported=int(s.unsupported)+1;s.pixel_bytes=[];return
			var tiles: Dictionary=s.gram.duplicate();var key:=str((y/16)*15+x/16)
			var tile: Array=tiles.get(key,[]).duplicate()
			if tile.is_empty():tile.resize(256);tile.fill(0)
			tile[(y%16)*16+x%16]=color;tiles[key]=tile;s.gram=tiles;s.pixel_bytes=[]
			s.x=int(s.x)+1
			if int(s.x)>int(s.x1):s.x=s.x0;s.y=int(s.y)+1
			if int(s.y)>int(s.y1):s.y=s.y0
