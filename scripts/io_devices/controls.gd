extends RefCounted
## Pure host-side reducer. Both views submit the same command. Stale requests fail.
static func defaults(kind: String) -> Dictionary:
	match kind:
		"io_encoder":return {"revision":0,"detent":0}
		"io_keypad":return {"revision":0,"keys":0}
		"io_slider":return {"revision":0,"x":0.5}
		"io_joystick":return {"revision":0,"x":0.5,"y":0.5,"pressed":false}
		"io_selector":return {"revision":0,"position":0}
		"xpt2046":return {"revision":0,"x":0.5,"y":0.5,"pressed":false}
	return {}

static func apply(kind: String, old: Dictionary, command: Dictionary) -> Dictionary:
	var state := defaults(kind)
	if state.is_empty():return {"ok":false,"error":"Device is not an input"}
	state.merge(old,true)
	if command.get("revision",-1)!=state.revision:return {"ok":false,"error":"Stale input revision"}
	var op := str(command.get("op",""))
	var valid := false
	match kind:
		"xpt2046":
			if op=="touch" and number(command.get("x")) and number(command.get("y")) and command.get("pressed") is bool:
				state.x=clampf(float(command.x),0,1);state.y=clampf(float(command.y),0,1);state.pressed=command.pressed;valid=true
			elif op=="release":state.pressed=false;valid=true
		"io_encoder":
			if op=="turn" and command.get("steps") is int and absi(command.steps)<=16:
				state.detent=clampi(int(state.detent)+int(command.steps),-100000,100000);valid=true
		"io_keypad":
			if op=="key" and command.get("key") is int and command.key>=0 and command.key<12 and command.get("pressed") is bool:
				var bit := 1<<int(command.key)
				state.keys=(int(state.keys)|bit) if command.pressed else (int(state.keys)&~bit);valid=true
			elif op=="release":state.keys=0;valid=true
		"io_selector":
			if op=="select" and command.get("position") is int and command.position in [0,1,2]:state.position=command.position;valid=true
		"io_slider","io_joystick":
			if op=="move" and number(command.get("x")) and (kind=="io_slider" or number(command.get("y"))):
				state.x=clampf(float(command.x),0,1)
				if kind=="io_joystick":state.y=clampf(float(command.y),0,1)
				valid=true
			elif kind=="io_joystick" and op=="press" and command.get("pressed") is bool:state.pressed=command.pressed;valid=true
			elif kind=="io_joystick" and op=="release":state.x=.5;state.y=.5;state.pressed=false;valid=true
	if not valid:return {"ok":false,"error":"Invalid input command"}
	state.revision=int(state.revision)+1
	return {"ok":true,"state":state}

static func number(value: Variant) -> bool:
	return (value is float or value is int) and is_finite(float(value))

## normalized point from canvas or physical-board UV, in interact mode only.
static func pointer(kind: String, point: Vector2, pressed: bool, revision: int) -> Dictionary:
	match kind:
		"xpt2046":return {"op":"touch","x":point.x,"y":point.y,"pressed":pressed,"revision":revision}
		"io_keypad":return {"op":"key","key":clampi(int(point.y*4),0,3)*3+clampi(int(point.x*3),0,2),"pressed":pressed,"revision":revision}
		"io_selector":return {"op":"select","position":clampi(int(point.x*3),0,2),"revision":revision}
		"io_slider":return {"op":"move","x":point.x,"revision":revision}
		"io_joystick":return {"op":"move","x":point.x,"y":point.y,"revision":revision} if pressed else {"op":"release","revision":revision}
	return {}
