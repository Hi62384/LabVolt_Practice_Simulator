extends RefCounted
# Step-bounded behavioral devices. State advances only on the authoritative station.
static func tick(kind: String,n: Array,v: Dictionary,old: Dictionary,dt: float) -> Dictionary:
 var s := old.duplicate(true)
 var g := float(v.get(n[0] if kind=="timer555" else n[6] if kind=="flip74" else n[7] if kind=="shift595" else n[1],0))
 var supply := float(v.get(n[7] if kind=="timer555" else n[13] if kind=="flip74" else n[15] if kind=="shift595" else n[0],0))-g
 var powered := supply>= (4.5 if kind=="timer555" else 2.0) and supply<= (16.0 if kind=="timer555" else 6.0)
 s.powered=powered
 if not powered:return {"powered":false}
 var pins: Array=[]
 for pin in n:pins.append(float(v.get(pin,0))-g)
 match kind:
  "timer555":
   var threshold := float(pins[4]);var q: bool=s.get("q",false)
   if pins[3]<.7:q=false
   elif pins[1]<threshold*.5:q=true
   elif pins[5]>threshold:q=false
   s.q=q
  "flip74":
   for entry in [["a",0,1,2,3],["b",12,11,10,9]]:
    var key: String=entry[0];var clk: bool=pins[entry[3]]>=supply*.7
    var clear: bool=pins[entry[1]]<supply*.3;var preset: bool=pins[entry[4]]<supply*.3
    var q: bool=s.get(key,false)
    if clear:q=false
    elif preset:q=true
    elif clk and not s.get(key+"clk",false):q=pins[entry[2]]>=supply*.7
    s[key]=q;s[key+"bar"]=not q if not (clear and preset) else true
    if clear and preset:s[key]=true
    s[key+"clk"]=clk
  "shift595":
   var clk: bool=pins[10]>=supply*.7;var latch: bool=pins[11]>=supply*.7
   var previous: int=int(s.get("shift",0))
   if latch and not s.get("latch_clk",false):s.latched=previous
   if pins[9]<supply*.3:s.shift=0
   elif clk and not s.get("shift_clk",false):s.shift=((previous<<1)|(1 if pins[13]>=supply*.7 else 0))&255
   s.enabled=pins[12]<supply*.3;s.shift_clk=clk;s.latch_clk=latch
  "spi_display":
   var active: bool=pins[4]<supply*.3;var clk: bool=pins[3]>supply*.7
   if not active:s.bits=0;s.byte=0;s.address=-1
   elif clk and not s.get("clk",false):
    s.byte=(int(s.get("byte",0))<<1)|(1 if pins[2]>supply*.7 else 0);s.bits=int(s.get("bits",0))+1
    if s.bits==8:
     if int(s.get("address",-1))<0:s.address=int(s.byte)%32
     else:
      var cells: Array=s.get("cells",[])
      if cells.size()!=32:cells.resize(32);cells.fill(32)
      cells[s.address]=clampi(int(s.byte),32,126);s.cells=cells;s.address=(int(s.address)+1)%32
     s.bits=0;s.byte=0
   s.clk=clk
 return s
static func expand(kind: String,id: String,n: Array,state: Dictionary) -> Array:
 var out: Array=[{"id":id,"kind":"stateful","model":kind,"nodes":n}]
 var ground: String=n[0] if kind=="timer555" else n[6] if kind=="flip74" else n[7] if kind=="shift595" else n[1]
 var supply: String=n[7] if kind=="timer555" else n[13] if kind=="flip74" else n[15] if kind=="shift595" else n[0]
 out.append({"id":id+"/power","kind":"R","a":supply,"b":ground,"value":2000.})
 var driven := {}
 if kind=="timer555":
  # Internal 5k divider exposes the control-voltage pin, including external modulation.
  out.append({"id":id+"/divider1","kind":"R","a":supply,"b":n[4],"value":5000.})
  out.append({"id":id+"/divider2","kind":"R","a":n[4],"b":ground,"value":10000.})
  driven[2]=state.get("q",false)
  out.append({"id":id+"/discharge","kind":"R","a":n[6],"b":ground,"value":10. if state.get("powered",false) and not state.get("q",false) else 1e12})
 elif kind=="flip74":
  driven={4:state.get("a",false),5:state.get("abar",true),8:state.get("b",false),7:state.get("bbar",true)}
 elif kind=="shift595":
  var order: Array=[14,0,1,2,3,4,5,6]
  for bit in 8:driven[order[bit]]=(int(state.get("latched",0))&(1<<bit))!=0
  driven[8]=(int(state.get("shift",0))&128)!=0
 for index in driven:
  out.append({"id":id+"/out"+str(index),"kind":"R","a":n[index],"b":supply if driven[index] else ground,"value":40. if state.get("powered",false) and (kind!="shift595" or index==8 or state.get("enabled",false)) else 1e12})
 for index in n.size():
  if n[index] in [ground,supply] or driven.has(index) or (kind=="timer555" and index in [4,6]):continue
  out.append({"id":id+"/input"+str(index),"kind":"R","a":n[index],"b":ground,"value":1e9})
 return out
