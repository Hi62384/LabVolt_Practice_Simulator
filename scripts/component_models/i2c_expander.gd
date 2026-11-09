extends RefCounted
## PCF8574 addressed I2C slave, open-drain SDA and INT, quasi-bidirectional I/O.
## Host must provide external bus pullups. Clock stretching is not generated.
static func tick(_n: Array,_v: Dictionary,p: Array,s: Dictionary,_supply: float) -> Dictionary:
	var scl: bool=p[13]==1;var sda: bool=p[14]==1
	var previous_scl: bool=s.get("scl",true);var previous_sda: bool=s.get("sda",true)
	var rising := scl and not previous_scl;var falling := not scl and previous_scl
	# SDA changes caused by this slave's ACK must not be mistaken for START/STOP.
	var self_drive: bool=s.get("sda_low",false)
	if scl and previous_scl and previous_sda and not sda and not self_drive:
		s.phase="address";s.bits=0;s.byte=0;s.matched=false;s.ack=false;s.sda_low=false
	elif scl and previous_scl and not previous_sda and sda and not self_drive:
		s.phase="idle";s.sda_low=false
	var phase: String=s.get("phase","idle")
	if rising and phase in ["address","write"]:
		s.byte=(int(s.get("byte",0))<<1)|(1 if sda else 0);s.bits=int(s.get("bits",0))+1
		if s.bits==8:
			if phase=="address":
				var address := 32+(1 if p[0]==1 else 0)+(2 if p[1]==1 else 0)+(4 if p[2]==1 else 0)
				s.matched=(int(s.byte)>>1)==address;s.read=(int(s.byte)&1)!=0
			else:s.latch=int(s.byte)&255;s.interrupt=false
			s.phase="ack_start";s.bits=0;s.byte=0
	elif falling and phase=="ack_start":s.sda_low=s.get("matched",false);s.phase="ack_high"
	elif rising and phase=="ack_high":s.phase="ack_end"
	elif falling and phase=="ack_end":
		s.sda_low=false
		if not s.get("matched",false):s.phase="idle"
		elif s.get("read",false):s.phase="read";s.read_bit=7;s.read_byte=port(p,s);s.sda_low=(int(s.read_byte)&128)==0;s.interrupt=false
		else:s.phase="write"
	elif rising and phase=="read":
		s.read_bit=int(s.get("read_bit",7))-1
		if s.read_bit<0:s.phase="master_ack_start"
	elif falling and phase=="read":s.sda_low=(int(s.get("read_byte",255))&(1<<int(s.read_bit)))==0
	elif falling and phase=="master_ack_start":s.sda_low=false;s.phase="master_ack"
	elif rising and phase=="master_ack":s.continue_read=not sda;s.phase="master_ack_end"
	elif falling and phase=="master_ack_end":
		if s.get("continue_read",false):s.phase="read";s.read_bit=7;s.read_byte=port(p,s);s.sda_low=(int(s.read_byte)&128)==0
		else:s.phase="idle";s.sda_low=false
	var actual := port(p,s)
	if s.has("port") and actual!=int(s.port):s.interrupt=true
	s.port=actual;s.scl=scl;s.sda=sda
	if s.get("sda_low",false):s.drive["14"]=0
	if s.get("interrupt",false):s.drive["12"]=0
	for bit in 8:
		if not (int(s.get("latch",255))&(1<<bit)):s.drive[str([3,4,5,6,8,9,10,11][bit])]=0
	return s

static func port(p: Array,s: Dictionary) -> int:
	var word := 0
	for bit in 8:
		if p[[3,4,5,6,8,9,10,11][bit]]==1 and (int(s.get("latch",255))&(1<<bit)):word|=1<<bit
	return word
