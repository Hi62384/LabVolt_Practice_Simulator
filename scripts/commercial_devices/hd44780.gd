extends RefCounted
static func initial() -> Dictionary:
	var ram: Array=[];ram.resize(128);ram.fill(32)
	var cg: Array=[];cg.resize(64);cg.fill(0)
	return {"ram":ram,"cgram":cg,"address":0,"cg":false,"increment":true,"entry_shift":false,"display":false,"cursor":false,"blink":false,"shift":0,"four":false,"two_line":false,"nibble":-1,"read_half":false,"busy_until":0.01,"e":false,"time":0.0,"powered":true,"read_drive":-1}
static func advance(s: Dictionary,direction: int) -> void:
	var next:=int(s.address)+direction
	if s.cg:s.address=posmod(next,64);return
	if s.get("two_line",false):
		if next==40:next=64
		elif next==104:next=0
		elif next==63:next=39
		elif next<0:next=103
	else:next=posmod(next,80)
	s.address=next&127
static func write(s: Dictionary,rs: bool,value: int) -> void:
	if float(s.time)<float(s.busy_until):s.ignored_busy=int(s.get("ignored_busy",0))+1;return
	value&=255
	if rs:
		var key: String="cgram" if s.cg else "ram"
		var memory: Array=s[key].duplicate();memory[int(s.address)%(64 if s.cg else 128)]=value&31 if s.cg else value;s[key]=memory
		advance(s,1 if s.increment else -1)
		if s.entry_shift and not s.cg:s.shift=posmod(int(s.shift)+(1 if s.increment else -1),40)
	elif value&128:s.cg=false;s.address=value&127
	elif value&64:s.cg=true;s.address=value&63
	elif value&32:s.four=(value&16)==0;s.two_line=(value&8)!=0
	elif value&16:
		if value&8:s.shift=posmod(int(s.shift)+(-1 if value&4 else 1),40)
		else:s.address=posmod(int(s.address)+(1 if value&4 else -1),128)
	elif value&8:s.display=(value&4)!=0;s.cursor=(value&2)!=0;s.blink=(value&1)!=0
	elif value&4:s.increment=(value&2)!=0;s.entry_shift=(value&1)!=0
	elif value&2:s.address=0;s.cg=false;s.shift=0
	elif value==1:s.ram=s.ram.duplicate();s.ram.fill(32);s.address=0;s.cg=false;s.shift=0
	s.busy_until=float(s.time)+(0.00152 if not rs and value in [1,2,3] else 0.000037)
static func read(s: Dictionary,rs: bool) -> int:
	return int(s["cgram" if s.cg else "ram"][int(s.address)%(64 if s.cg else 128)]) if rs else ((128 if float(s.time)<float(s.busy_until) else 0)|(int(s.address)&127))
static func edge(s: Dictionary,p: Array) -> void:
	var e: bool=p[5]>=2.2;var rw: bool=p[4]>=2.2;var rs: bool=p[3]>=2.2
	if e and not s.e:s.e_rise=float(s.time)
	s.read_drive=-1
	if e and rw:
		var value:=read(s,rs)
		s.read_drive=(value&15 if s.read_half else value>>4) <<4 if s.four else value
	if not e and s.e:
		if float(s.time)-float(s.get("e_rise",s.time))<0.00000023:
			s.ignored_short=int(s.get("ignored_short",0))+1;s.e=e;return
		if rw:
			if not s.four or s.read_half:
				if rs:advance(s,1 if s.increment else -1)
				s.read_half=false
			else:s.read_half=true
		else:
			var value:=0
			for bit in 8:
				if p[6+bit]>=2.2:value|=1<<bit
			if s.four:
				if int(s.nibble)<0:s.nibble=value&240
				else:value=int(s.nibble)|(value>>4);s.nibble=-1;write(s,rs,value)
			else:write(s,rs,value)
	s.e=e
static func text(s: Dictionary) -> Array:
	var lines: Array=[]
	var columns:=int(s.get("columns",16));var rows:=int(s.get("rows",2))
	for row in rows:
		var line:=""
		for col in columns:
			var base: int=[0,64,20,84][row]
			var value: int=s.ram[(base&64)+posmod((base&63)+col+int(s.shift),40)]
			line+=String.chr(value) if value>=32 and value<=126 else "□"
		lines.append(line)
	return lines
