extends RefCounted
## Mode-0 SPI: DI on rising edge, DO changes on falling edge. One edge per host tick.
static func tick(m: Dictionary,n: Array,v: Dictionary,p: Array,s: Dictionary,dt: float) -> Dictionary:
	var kind: String=m.worker_model
	var cs: int=9 if kind=="adc3008" else 1 if kind=="dac4921" else 0
	var clk: int=12 if kind=="adc3008" else 2 if kind=="dac4921" else 5
	var di: int=10 if kind=="adc3008" else 3 if kind=="dac4921" else 4
	var rising: bool=p[clk]==1 and not s.get("clock",true)
	var falling: bool=p[clk]==0 and s.get("clock",false)
	var deselected: bool=p[cs]!=0
	var end: bool=deselected and s.get("selected",false)
	s.busy=maxf(0.,float(s.get("busy",0))-dt)
	if kind=="dac4921":
		if end and int(s.get("bits",0))==16:
			var word: int=s.get("word",0)
			s.pending_code=word&4095;s.pending_gain=1 if word&8192 else 2;s.pending_active=(word&4096)!=0
		if p[4]==0:
			s.code=s.get("pending_code",0);s.gain=s.get("pending_gain",1);s.active=s.get("pending_active",false)
	if kind=="eeprom25" and end:
		var command: int=s.get("command",0)
		if s.busy<=0.:
			if command==6 and int(s.get("bits",0))==8:s.wel=true
			if command==4:s.wel=false
			if command==1 and s.get("wel",false) and int(s.get("bits",0))==16:
				if not (int(s.get("status",0))&128 and p[2]==0):s.status=int(s.get("word",0))&140
				s.wel=false;s.busy=.005
			if command==2 and s.get("wel",false) and not s.get("pending",{}).is_empty():
				var memory: Dictionary=s.get("memory",{})
				var protect: int=(int(s.get("status",0))>>2)&3
				var boundary := 32768 if protect==0 else 24576 if protect==1 else 16384 if protect==2 else 0
				for address in s.pending:
					if int(address)<boundary:memory[address]=s.pending[address]
				s.memory=memory;s.wel=false;s.busy=.005
	if deselected:
		s.bits=0;s.word=0;s.command=0;s.pending={};s.adc_started=false;s.serial=-1
	else:
		var held: bool=kind=="eeprom25" and p[6]==0
		if not held and rising and p[di]>=0:
			if kind!="adc3008" or s.get("adc_started",false) or p[di]==1:
				s.adc_started=true;s.bits=int(s.get("bits",0))+1;s.word=(int(s.get("word",0))<<1|int(p[di]))&65535
			var bits: int=s.get("bits",0)
			if kind=="adc3008" and bits==5:
				var word: int=s.word;var channel := word&7
				var analog := float(v.get(n[channel],0))-float(v.get(n[13],0))
				if (word&8)==0:analog=float(v.get(n[channel&6 if channel%2==0 else channel],0))-float(v.get(n[channel+1 if channel%2==0 else channel-1],0))
				var reference := float(v.get(n[14],0))-float(v.get(n[13],0))
				s.sample=clampi(int(floor(analog/reference*1024.)),0,1023) if reference>0. else 0
			if kind=="eeprom25":
				if bits==8:s.command=int(s.word)&255
				if bits==24:s.address=int(s.word)&32767;s.base=int(s.address)&~63
				if int(s.get("command",0))==2 and bits>=32 and (bits-24)%8==0:
					var pending: Dictionary=s.get("pending",{});pending[str(s.address)]=int(s.word)&255;s.pending=pending
					s.address=int(s.base)|((int(s.address)+1)&63)
		if not held and falling:
			var bits: int=s.get("bits",0)
			if kind=="adc3008":s.serial=0 if bits==6 else ((int(s.get("sample",0))>>(16-bits))&1) if bits>=7 and bits<=16 else -1
			if kind=="eeprom25" and s.busy<=0.:
				var command: int=s.get("command",0)
				if command==5 and bits>=8:
					var status: int=int(s.get("status",0))|(2 if s.get("wel",false) else 0)
					s.serial=(status>>(7-(bits-8)%8))&1
				elif command==3 and bits>=24:
					var address := (int(s.get("address",0))+(bits-24)/8)%32768
					s.serial=(int(s.get("memory",{}).get(str(int(address)),255))>>(7-(bits-24)%8))&1
			if kind=="eeprom25" and int(s.get("command",0))==5 and s.busy>0.:
				s.serial=((int(s.get("status",0))|1)>>(7-(bits-8)%8))&1 if bits>=8 else -1
	s.clock=p[clk]==1;s.selected=not deselected
	if not deselected:
		var pin: int=11 if kind=="adc3008" else 1
		if kind!="dac4921" and not (kind=="eeprom25" and p[6]==0) and int(s.get("serial",-1))>=0:s.drive[str(pin)]=s.serial
	return s


