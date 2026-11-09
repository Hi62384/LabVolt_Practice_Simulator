'use strict';
// Cooperative peripheral pin engine. No slave IDs, memory writes or invented ACKs.
// Every action returns to the authoritative circuit solver before sampling pins.
class ElectricalBuses {
 constructor(machine){this.m=machine;this.channels=new Map();this.drives={};this.claims={};this.pending=[];this.errors=[];this.rx={};}
 channel(key){if(!this.channels.has(key))this.channels.set(key,{queue:[],tail:this.m.cycles});return this.channels.get(key);}
 add(key,delay,drive={},sample=null,done=null){const c=this.channel(key);if(c.queue.length>=1024)throw Error('Electrical bus action limit');const at=Math.max(c.tail,this.m.cycles)+Math.max(0,Math.round(delay));c.tail=at;c.queue.push({at,drive,sample,done});}
 level(pin,pins){const v=pins[pin];return Number.isFinite(v)?v:null;}
 high(pin,pins){const v=this.level(pin,pins);return v!==null&&v>=(this.m.avr?.6*this.m.supply:2);}
 low(pin,pins){const v=this.level(pin,pins);return v!==null&&v<=(this.m.avr?.3*this.m.supply:.8);}
 set(pin,state,key=null){if(!pin)return;if(key)this.claims[pin]=key;if(this.drives[pin]!==state){this.drives[pin]=state;this.m.event('gpio',{pin,state,cycle:this.m.cycles,peripheral:true});}}
 pump(pins){
  // Values here belong to the circuit solution AFTER the last returned edge.
  const waiting=this.pending.splice(0);for(const item of waiting){if(item.sample)item.sample(pins);if(item.done)item.done();}
  let barrier=false;
  for(const [key,c] of this.channels){const a=c.queue[0];if(!a||a.at>this.m.cycles)continue;c.queue.shift();for(const [p,s] of Object.entries(a.drive))this.set(p,s,key);a.key=key;this.pending.push(a);barrier=true;}
  return barrier;
 }
 cancel(key){const c=this.channel(key);c.queue=[];c.tail=this.m.cycles;this.pending=this.pending.filter(a=>a.key!==key);}
 next(){let at=Infinity;for(const c of this.channels.values())if(c.queue.length)at=Math.min(at,c.queue[0].at);return at;}
 error(key,message,pins=[]){this.errors.push({bus:key,error:message,cycle:this.m.cycles});if(this.errors.length>32)this.errors.shift();this.channel(key).queue=[];this.channel(key).tail=this.m.cycles;for(const [pin,owner] of Object.entries(this.claims))if(owner===key&&!pins.includes(pin))pins.push(pin);for(const p of pins)this.set(p,2);this.m.event('bus_error',{bus:key,error:message,cycle:this.m.cycles});if(this.m.busFault)this.m.busFault(key,message);}
 spi(key,pins,value,bits,hz,cpol,cpha,lsb,complete){
  const [clk,mosi,miso]=pins;if(!clk||!mosi||!miso||!Number.isFinite(hz)||hz<=0){this.error(key,'SPI pin mux/clock unavailable');complete((2**bits)-1);return;}
  if(this.channel(key).queue.length){this.error(key,'SPI collision');return;}
  const half=Math.max(1,Math.round(this.m.hz/hz/2));let result=0;
  const bitAt=i=>(value>>(lsb?i:bits-1-i))&1;
  const sample=i=>p=>{if(this.high(miso,p))result|=1<<(lsb?i:bits-1-i);};
  this.add(key,0,{[clk]:cpol,[mosi]:bitAt(0)});
  for(let i=0;i<bits;i++){
   this.add(key,half,{[clk]:1-cpol,...(cpha?{[mosi]:bitAt(i)}:{})},cpha?null:sample(i));
   this.add(key,half,{[clk]:cpol,...(!cpha&&i+1<bits?{[mosi]:bitAt(i+1)}:{})},cpha?sample(i):null);
  }
  this.add(key,0,{},null,()=>complete(result));
 }
 i2cTiming(hz){return Math.max(1,Math.round(this.m.hz/Math.max(1,hz)/2));}
 // Clock stretch checks use the solved SCL; release never drives a logic high.
 clockHigh(key,scl,half,sample){let waited=0;const check=p=>{
  if(this.high(scl,p)){if(sample)sample(p);return;}
  waited+=half;if(waited>this.m.hz*.01){this.error(key,'I2C clock stretch/bus stuck timeout',[scl]);return;}
  const c=this.channel(key);c.queue.unshift({at:this.m.cycles+half,drive:{},sample:check});
  for(let i=1;i<c.queue.length;i++)c.queue[i].at+=half;c.tail+=half;
 };return check;}
 start(key,pins,hz,complete){const [scl,sda]=pins;if(!scl||!sda){this.error(key,'I2C pin mux unavailable');return;}
  const h=this.i2cTiming(hz);this.add(key,0,{[scl]:0,[sda]:2});this.add(key,h,{[scl]:2},this.clockHigh(key,scl,h,null));this.add(key,h,{[sda]:0});this.add(key,h,{[scl]:0},null,complete);
 }
 stop(key,pins,hz,complete){const [scl,sda]=pins;const h=this.i2cTiming(hz);this.add(key,0,{[scl]:0,[sda]:0});this.add(key,h,{[scl]:2},this.clockHigh(key,scl,h,null));this.add(key,h,{[sda]:2},null,complete);}
 write(key,pins,value,hz,complete){const [scl,sda]=pins;const h=this.i2cTiming(hz);let arbitration=false,ack=false;
  for(let i=7;i>=0;i--){const one=!!(value&(1<<i));this.add(key,0,{[scl]:0,[sda]:one?2:0});this.add(key,h,{[scl]:2},this.clockHigh(key,scl,h,p=>{if(one&&!this.high(sda,p)){arbitration=true;this.error(key,'I2C arbitration lost or SDA short',[scl,sda]);}}));this.add(key,h,{[scl]:0});}
  this.add(key,0,{[sda]:2});this.add(key,h,{[scl]:2},this.clockHigh(key,scl,h,p=>{ack=this.low(sda,p);}));this.add(key,h,{[scl]:0},null,()=>{if(!arbitration)complete(ack);});
 }
 read(key,pins,ack,hz,complete){const [scl,sda]=pins;const h=this.i2cTiming(hz);let value=0;
  for(let i=0;i<8;i++){this.add(key,0,{[scl]:0,[sda]:2});this.add(key,h,{[scl]:2},this.clockHigh(key,scl,h,p=>{value=(value<<1)|(this.high(sda,p)?1:0);}));this.add(key,h,{[scl]:0});}
  this.add(key,0,{[sda]:ack?0:2});this.add(key,h,{[scl]:2},this.clockHigh(key,scl,h,null));this.add(key,h,{[scl]:0});this.add(key,0,{[sda]:2},null,()=>complete(value));
 }
 uartTx(key,pin,value,baud,bits,stops,parity,odd){if(!pin||!Number.isFinite(baud)||baud<=0){this.error(key,'UART pin mux/baud unavailable');return;}
  const bit=Math.max(1,Math.round(this.m.hz/baud));let ones=0;this.add(key,0,{[pin]:0});
  for(let i=0;i<bits;i++){const b=(value>>i)&1;ones+=b;this.add(key,bit,{[pin]:b});}
  if(parity)this.add(key,bit,{[pin]:(ones+(odd?1:0))&1});
  this.add(key,bit,{[pin]:1});this.add(key,bit*stops,{});
 }
 observeRx(key,pin,pins,baud,bits,stops,parity,odd,complete){if(!pin||!Number.isFinite(baud)||baud<=0)return;
  let r=this.rx[key];if(!r)r=this.rx[key]={last:true,active:false};const high=this.high(pin,pins);
  if(r.last&&!high&&!r.active){r.active=true;let value=0,ones=0,framing=false,parityError=false;const bit=Math.max(1,Math.round(this.m.hz/baud));
   this.add(key,bit/2,{},p=>{if(!this.low(pin,p))framing=true;});
   for(let i=0;i<bits;i++)this.add(key,bit,{},p=>{if(this.high(pin,p)){value|=1<<i;ones++;}});
   if(parity)this.add(key,bit,{},p=>{if(this.high(pin,p)!==!!((ones+(odd?1:0))&1))parityError=true;});
   this.add(key,bit,{},p=>{if(!this.high(pin,p))framing=true;},()=>{r.active=false;if(framing||parityError)this.error(key,'UART framing/parity error');complete(value,{framing,parity:parityError});});
  }
  r.last=high;
 }
}
module.exports={ElectricalBuses};
