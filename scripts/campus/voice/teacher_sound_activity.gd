extends RefCounted
## Only short-lived numeric activity metadata is retained; PCM is never stored.
const WINDOW_MS:=20
const MIN_WINDOWS:=6
const QUIET_RMS:=0.04
const COOLDOWN_MS:=4000
var state:={}

func observe(peer: int,packet: PackedByteArray,now_ms: int,sensitivity: float=1.0) -> float:
 if packet.size()!=640:return 0.0
 var sum:=0.0
 for i in range(0,packet.size(),2):
  var sample:=float(packet.decode_s16(i))/32768.0
  sum+=sample*sample
 var rms:=sqrt(sum/320.0)*clampf(sensitivity,.5,2.0) if is_finite(sensitivity) else sqrt(sum/320.0)
 var entry: Dictionary=state.get(peer,{"windows":0,"last":-COOLDOWN_MS,"last_window":now_ms})
 if now_ms-int(entry.last_window)>200 or now_ms<int(entry.last_window):entry.windows=0
 entry.last_window=now_ms
 if rms<QUIET_RMS:entry.windows=0
 else:entry.windows=mini(MIN_WINDOWS,int(entry.windows)+1)
 state[peer]=entry
 if int(entry.windows)<MIN_WINDOWS or now_ms-int(entry.last)<COOLDOWN_MS:return 0.0
 entry.last=now_ms;entry.windows=0
 return clampf(.25+(rms-QUIET_RMS)*2.5,.25,1.0)

func forget(peer: int) -> void:state.erase(peer)
