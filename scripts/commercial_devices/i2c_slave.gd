extends RefCounted
const Registers=preload("res://scripts/commercial_devices/registers.gd")
static func tick(kind: String,s: Dictionary,scl: bool,sda: bool,address: int) -> void:
	var b: Dictionary=s.get("bus",{"scl":true,"sda":true,"phase":"idle","low":false}).duplicate()
	var old_scl: bool=b.scl;var old_sda: bool=b.sda
	if scl and old_scl and sda!=old_sda:
		if not sda:b={"phase":"receive","low":false,"bits":0,"byte":0,"address":true,"selected":false,"reading":false};s.pending_reset=false
		else:Registers.i2c_stop(kind,s);b.phase="idle";b.low=false
	elif scl and not old_scl:
		match str(b.phase):
			"receive":
				b.byte=((int(b.get("byte",0))<<1)|(1 if sda else 0))&255;b.bits=int(b.get("bits",0))+1
				if int(b.bits)==8:
					var ack:=false
					if b.get("address",true):
						b.reading=(int(b.byte)&1)!=0
						var received:=int(b.byte)>>1
						b.general=kind=="pca9685" and received==0 and not b.reading
						b.selected=received==address and (kind=="pca9685" or not b.reading)
						if kind=="pca9685" and not b.reading:
							b.selected=b.selected or b.general
							for alias in [[1,5],[8,2],[4,3],[2,4]]:
								if int(s.registers[0])&int(alias[0]) and received==(int(s.registers[int(alias[1])])>>1):b.selected=true
						b.address=false;ack=b.selected
						if b.selected:Registers.i2c_start(kind,s,b.reading)
					elif b.selected:
						if b.get("general",false):
							ack=int(b.byte)==6 and not b.get("general_received",false)
							b.general_received=true;s.pending_reset=ack
						else:ack=Registers.i2c_write(kind,s,int(b.byte))
					b.ack=ack;b.phase="ack_wait_fall"
			"ack_hold":Registers.i2c_ack(kind,s);b.phase="ack_release"
			"send":
				b.bits=int(b.bits)+1
				if int(b.bits)==8:b.phase="read_ack_wait_fall"
			"read_ack":b.master_ack=not sda;b.phase="read_ack_done"
	elif not scl and old_scl:
		match str(b.phase):
			"ack_wait_fall":b.low=b.get("ack",false);b.phase="ack_hold"
			"ack_release":
				b.low=false;b.bits=0;b.byte=0
				if b.reading and b.selected:
					b.byte=Registers.i2c_read(kind,s);b.low=(int(b.byte)&128)==0;b.phase="send"
				else:b.phase="receive"
			"send":b.low=(int(b.byte)&(128>>int(b.bits)))==0
			"read_ack_wait_fall":b.low=false;b.phase="read_ack"
			"read_ack_done":
				if b.master_ack:b.byte=Registers.i2c_read(kind,s);b.bits=0;b.low=(int(b.byte)&128)==0;b.phase="send"
				else:b.low=false;b.phase="idle"
	b.scl=scl;b.sda=sda;s.bus=b
