extends RefCounted
## Bounded reliable uploads. Executable paths and backend capabilities never cross RPC.
const Schema=preload("res://scripts/inventory_authority/firmware_schema.gd")
const Board=preload("res://scripts/breadboard_model.gd")
var uploads := {}
var began := {}
func target(station,id: String) -> String:
 for device in Board.devices(station.board):
  if device.id==id and device.part.type in ["native_uno","native_pico","native_nano"]:return str(device.part.type).trim_prefix("native_")
 return ""
func apply(peer: int,index: int,action: Dictionary,station) -> String:
 var now := Time.get_ticks_msec()
 for actor in uploads.keys():
  if now-int(uploads[actor].time)>10000:uploads.erase(actor)
 var id := str(action.get("id",""));var board := target(station,id)
 if station.board_owner!=peer or int(action.get("board_epoch",-1))!=station.board_epoch or board=="":return "Native board changed or belongs to another player"
 var op := str(action.get("op",""))
 if op=="native_control":
  if not action.get("controls") is Dictionary:return "Invalid native control"
  var control: Dictionary=action.controls
  for key in control:
   if key in ["run","resume","reset","step"]:
    if not control[key] is bool:return "Invalid native switch"
   elif key=="breakpoints":
    if not control[key] is Array or control[key].size()>64:return "Invalid breakpoint list"
    for address in control[key]:
     if not (address is int) or address<0 or address>0xffffffff:return "Invalid breakpoint address"
   elif key=="uart_rx":
    if not control[key] is Array or control[key].size()>128:return "Invalid UART data"
    for byte in control[key]:
     if not byte is Dictionary or byte.size()!=2 or byte.get("port")!=0 or not byte.get("value") is int or byte.value<0 or byte.value>255:return "Invalid UART byte"
   else:return "Unsupported native control"
  if not station.board.has("programs"):station.board.programs={}
  if not station.board.programs.has(id):station.board.programs[id]={}
  if control.has("run"):station.board.programs[id].run=control.run
  var actual := control.duplicate(true);actual.erase("run")
  station.native_controls[id]=actual;station.revision+=1;return ""
 if op=="native_begin":
  if now-int(began.get(peer,-10000))<1000:return "Wait a moment before another upload"
  if not action.get("bytes") is int or action.bytes<1 or action.bytes>786432:return "Program and source exceed upload limit"
  var digest := str(action.get("hash",""))
  if digest.length()!=64 or not digest.is_valid_hex_number():return "Invalid program checksum"
  began[peer]=now
  uploads[peer]={"index":index,"id":id,"epoch":station.board_epoch,"bytes":action.bytes,"hash":digest,"chunks":[],"received":0,"time":now}
  return ""
 if not uploads.has(peer):return "Upload expired; try again"
 var upload: Dictionary=uploads[peer]
 if upload.index!=index or upload.id!=id or upload.epoch!=station.board_epoch:uploads.erase(peer);return "Upload target changed"
 if op=="native_chunk":
  if not action.get("data") is String or action.data.to_utf8_buffer().size()>8000 or int(action.get("sequence",-1))!=upload.chunks.size():uploads.erase(peer);return "Invalid upload chunk"
  upload.received+=action.data.to_utf8_buffer().size()
  if upload.received>upload.bytes:uploads.erase(peer);return "Upload size exceeded"
  upload.chunks.append(action.data);upload.time=now;return ""
 if op!="native_finish":return "Unknown native upload action"
 uploads.erase(peer)
 var text := "".join(upload.chunks)
 if upload.received!=upload.bytes or text.sha256_text()!=upload.hash:return "Program checksum mismatch"
 var payload=JSON.parse_string(text)
 if not payload is Dictionary or payload.size()!=2 or not Schema.record(payload.get("program")) or not Schema.files(payload.get("sources"),false):return "Invalid compiled image or source files"
 if payload.program.board!=board:return "Program targets a different board"
 var program := {"native_firmware":payload.program,"native_sources":payload.sources,"run":true}
 if not station.board.has("programs"):station.board.programs={}
 if station.board.programs.size()>=16 and not station.board.programs.has(id):return "Device program limit reached"
 station.board.programs[id]=program;station.board_epoch+=1;station.native_controls.erase(id);station.revision+=1
 return ""
