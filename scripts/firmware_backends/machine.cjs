'use strict';
// Trusted adapter only: guest bytes are instruction data, never JS/eval/modules.
const {ElectricalBuses}=require('../electronics_buses/native_bus.cjs');
const avr = require('./vendor/avr8js/cjs/index.js');
const { RP2040 } = require('./vendor/rp2040js/cjs/rp2040.js');
const { SimulationClock } = require('./vendor/rp2040js/cjs/clock/simulation-clock.js');
function integer(n, min, max, label) {
  if (!Number.isInteger(n) || n < min || n > max) throw Error('Invalid ' + label);
  return n;
}
function hexImage(text, size) {
  if (typeof text !== 'string' || text.length > size * 4) throw Error('HEX size limit');
  const image = new Uint8Array(size).fill(255); let base = 0, ended = false;
  for (const line of text.trim().split(/\r?\n/)) {
    if (ended || !/^:([0-9a-f]{2})+$/i.test(line)) throw Error('Invalid HEX record');
    const b = Buffer.from(line.slice(1), 'hex');
    if (b.length !== b[0] + 5 || b.reduce((a,v)=>a+v,0) % 256) throw Error('HEX checksum/length');
    const addr = b[1]*256+b[2], type = b[3];
    if (type === 0) {
      if (base+addr+b[0] > size) throw Error('HEX address outside flash');
      image.set(b.subarray(4,4+b[0]),base+addr);
    } else if (type === 1 && b[0] === 0) ended = true;
    else if (type === 4 && b[0] === 2) base = (b[4]*256+b[5])*65536;
    else throw Error('Unsupported HEX record');
  }
  if (!ended) throw Error('Missing HEX EOF');
  return image;
}
class Machine {
  constructor(spec) {
    this.spec=spec; this.events=[]; this.dropped=0; this.serial=[]; this.breakpoints=[];
    this.paused=false; this.powered=false; this.status='No power'; this.inputs={};this.electrical=false;this.supply=0;
    if (!['uno','nano','pico'].includes(spec.board)) throw Error('Supported boards: uno, nano, pico');
    this.board=spec.board;this.avr=['uno','nano'].includes(this.board); this.hz=this.avr?16000000:125000000;
    if (this.avr) this.image=hexImage(spec.image,32768);
    else {
      if (typeof spec.image!=='string' || !/^[A-Za-z0-9+/]*={0,2}$/.test(spec.image) || spec.image.length>2796204) throw Error('Invalid Pico base64 image');
      this.image=Buffer.from(spec.image,'base64');
      if (this.image.length<8 || this.image.length>2097152) throw Error('Pico image size');
      this.vector=integer(spec.vector_offset ?? 256,0,this.image.length-8,'vector offset');
      const sp=this.image.readUInt32LE(this.vector), pc=this.image.readUInt32LE(this.vector+4);
      if (sp<0x20000000 || sp>0x20042000 || !(pc&1) || pc<0x10000000 || pc>=0x10000000+this.image.length) throw Error('Invalid Pico vector table');
    }
    this.reset();
  }
  event(type,data) { if(this.events.length<256)this.events.push({type,...data});else this.dropped++; }
  byte(port,value) { this.serial.push({port,value}); if(this.serial.length>256)this.serial.shift(); }
  reset() {
    this.events=[];this.dropped=0;this.serial=[];this.paused=false;
    if(this.avr) {
      this.cpu=new avr.CPU(new Uint16Array(this.image.slice().buffer),2048);
      this.ports={B:new avr.AVRIOPort(this.cpu,avr.portBConfig),C:new avr.AVRIOPort(this.cpu,avr.portCConfig),D:new avr.AVRIOPort(this.cpu,avr.portDConfig)};
      this.pins={};
      for(let i=0;i<(this.board==='nano'?22:20);i++)this.pins[i<14?'D'+i:'A'+(i-14)]={port:this.ports[i<8?'D':i<14?'B':'C'],bit:i<8?i:i<14?i-8:i-14,analogOnly:i>=20};
      for(const [name,p] of Object.entries(this.pins)){if(p.analogOnly)continue;let last=p.port.pinState(p.bit);p.port.addListener(()=>{const state=p.port.pinState(p.bit);if(state!==last){last=state;this.event('gpio',{pin:name,state,cycle:this.cpu.cycles});}});}
      this.timers=[avr.timer0Config,avr.timer1Config,avr.timer2Config].map(c=>new avr.AVRTimer(this.cpu,c));
      this.adc=new avr.AVRADC(this.cpu,avr.adcConfig);
      this.uart=[new avr.AVRUSART(this.cpu,avr.usart0Config,this.hz)];
      this.uart[0].onByteTransmit=v=>{this.byte(0,v);if(this.electrical){const u=this.uart[0];this.bus.uartTx('uart0tx','D1',v,u.baudRate,u.bitsPerChar,u.stopBits,u.parityEnabled,u.parityOdd);}};
      this.spi=new avr.AVRSPI(this.cpu,avr.spiConfig,this.hz);
      this.spi.onByte=value=>{if(this.electrical){if(!this.spi.isMaster){this.bus.error('spi0','SPI slave mode not implemented');this.spi.completeTransfer(255);return;}this.bus.spi('spi0',['D13','D11','D12'],value,8,this.spi.spiFrequency,this.spi.spiMode&1,this.spi.spiMode>>1,this.spi.dataOrder==='lsbFirst',v=>this.spi.completeTransfer(v));return;}this.event('spi',{port:0,value});this.cpu.addClockEvent(()=>this.spi.completeTransfer(255),this.spi.transferCycles);};
      this.twi=new avr.AVRTWI(this.cpu,avr.twiConfig,this.hz);
      this.twi.eventHandler={
       start:()=>this.electrical?this.bus.start('i2c0',['A5','A4'],this.twi.sclFrequency,()=>this.twi.completeStart()):this.twi.completeStart(),
       stop:()=>this.electrical?this.bus.stop('i2c0',['A5','A4'],this.twi.sclFrequency,()=>this.twi.completeStop()):this.twi.completeStop(),
       connectToSlave:(address,write)=>{if(this.electrical)this.bus.write('i2c0',['A5','A4'],(address<<1)|(write?0:1),this.twi.sclFrequency,ack=>this.twi.completeConnect(ack));else{this.event('i2c',{address,write,nack:true});this.twi.completeConnect(false);}},
       writeByte:value=>this.electrical?this.bus.write('i2c0',['A5','A4'],value,this.twi.sclFrequency,ack=>this.twi.completeWrite(ack)):this.twi.completeWrite(false),
       readByte:ack=>this.electrical?this.bus.read('i2c0',['A5','A4'],ack,this.twi.sclFrequency,v=>this.twi.completeRead(v)):this.twi.completeRead(255)};
    } else {
      this.clock=new SimulationClock();this.mcu=new RP2040(this.clock);
      this.mcu.logger={debug(){},info(){},warn(){},error(){}};
      this.mcu.flash.set(this.image);this.cpu=this.mcu.core;
      this.cpu.SP=this.image.readUInt32LE(this.vector);this.cpu.PC=this.image.readUInt32LE(this.vector+4)&~1;this.cpu.VTOR=0x10000000+this.vector;
      this.mcu.onBreak=()=>{this.paused=true;this.status='Breakpoint';};
      for(let i=0;i<30;i++)this.mcu.gpio[i].addListener(state=>this.event('gpio',{pin:'GP'+i,state,cycle:this.cpu.cycles}));
      this.uart=this.mcu.uart;this.uart.forEach((u,i)=>u.onByte=v=>{this.byte(i,v);if(this.electrical)this.bus.uartTx('uart'+i+'tx',this.rpPin('uart',i,'tx'),v,u.baudRate,u.wordLength,(u.lineCtrlRegister&8)?2:1,!!(u.lineCtrlRegister&2),!(u.lineCtrlRegister&4));});
      this.mcu.spi.forEach((s,i)=>s.onTransmit=value=>{if(this.electrical){if((s.control1&4)||(s.control0&0x30)){this.bus.error('spi'+i,'Only Motorola SPI master framing implemented');s.completeTransmit(255);return;}this.bus.spi('spi'+i,[this.rpPin('spi',i,'sck'),this.rpPin('spi',i,'tx'),this.rpPin('spi',i,'rx')],value,s.dataBits,s.clockFrequency,(s.control0>>6)&1,(s.control0>>7)&1,false,v=>s.completeTransmit(v));return;}this.event('spi',{port:i,value});this.clock.createAlarm(()=>s.completeTransmit((1<<s.dataBits)-1)).schedule(1e9*s.dataBits/s.clockFrequency);});
      this.mcu.i2c.forEach((i,p)=>{
       const pins=()=>[this.rpPin('i2c',p,'scl'),this.rpPin('i2c',p,'sda')];const hz=()=>this.mcu.clkPeri/Math.max(2,i.sclHighPeriod+i.sclLowPeriod);
       i.onStart=()=>this.electrical?this.bus.start('i2c'+p,pins(),hz(),()=>i.completeStart()):i.completeStart();
       i.onStop=()=>this.electrical?this.bus.stop('i2c'+p,pins(),hz(),()=>i.completeStop()):i.completeStop();
       i.onConnect=(address,mode)=>{if(this.electrical&&address>127){this.bus.error('i2c'+p,'10-bit I2C addressing not implemented');i.completeConnect(false);}else if(this.electrical)this.bus.write('i2c'+p,pins(),(address<<1)|(mode===0?0:1),hz(),ack=>i.completeConnect(ack));else{this.event('i2c',{port:p,address,write:mode===0,nack:true});i.completeConnect(false);}};
       i.onWriteByte=value=>this.electrical?this.bus.write('i2c'+p,pins(),value,hz(),ack=>i.completeWrite(ack)):i.completeWrite(false);
       i.onReadByte=ack=>this.electrical?this.bus.read('i2c'+p,pins(),ack,hz(),v=>i.completeRead(v)):i.completeRead(255);
      });
    }
    this.bus=new ElectricalBuses(this);this.status=this.powered?'Ready':'No power';
  }
  rpPin(kind,port,role){
    const func={spi:1,uart:2,i2c:3}[kind];
    const matches=n=>kind==='spi'?Math.floor(n/8)%2===port&&n%4==={rx:0,sck:2,tx:3}[role]:kind==='i2c'?Math.floor(n/2)%2===port&&n%2===(role==='sda'?0:1):(port?[4,8,20,24]:[0,12,16,28]).map(x=>x+(role==='rx'?1:0)).includes(n);
    const pins=this.mcu.gpio.filter((g,n)=>n<30&&g.functionSelect===func&&matches(n));return pins.length===1?'GP'+pins[0].index:null;
  }
  busFault(key,message){
    if(!key.startsWith('i2c'))return;
    if(this.avr){this.twi.busy=false;this.twi.updateStatus(message.includes('arbitration')?0x38:0x00);}
    else {const port=Number(key.match(/(\d+)$/)?.[1]||0);const i=this.mcu.i2c[port];if(message.includes('arbitration'))i.arbitrationLost();else{i.abort(1<<16);i.busy=false;}}
  }
  syncBuses(){
    for(const [pin,key] of Object.entries(this.bus.claims)){
      const port=Number(key.match(/(\d+)(?:tx|rx)?$/)?.[1]||0);let enabled=false;
      if(this.avr)enabled=key.startsWith('spi')?!!(this.cpu.data[0x4c]&64):key.startsWith('i2c')?!!(this.cpu.data[0xbc]&4):!!(this.cpu.data[0xc1]&8);
      else enabled=key.startsWith('spi')?!!(this.mcu.spi[port].control1&2)&&this.mcu.gpio[+pin.slice(2)].functionSelect===1:key.startsWith('i2c')?!!this.mcu.i2c[port].enable&&this.mcu.gpio[+pin.slice(2)].functionSelect===3:this.mcu.uart[port].enabled&&this.mcu.uart[port].txEnabled&&this.mcu.gpio[+pin.slice(2)].functionSelect===2;
      if(!enabled){this.bus.cancel(key);delete this.bus.drives[pin];delete this.bus.claims[pin];const p=this.avr?this.pins[pin]:null;const state=p?(p.analogOnly?2:p.port.pinState(p.bit)):this.mcu.gpio[+pin.slice(2)].value;this.event('gpio',{pin,state,cycle:this.cycles,peripheral:true});}
    }
  }
  observeUart(){
    this.uart.forEach((u,i)=>{const avr=this.avr;const tx=avr?'D1':this.rpPin('uart',i,'tx');const txEnabled=avr?!!(this.cpu.data[0xc1]&8):u.enabled&&u.txEnabled;if(txEnabled&&tx&&this.bus.drives[tx]===undefined)this.bus.set(tx,1,'uart'+i+'tx');const enabled=avr?!!(this.cpu.data[0xc1]&16):u.enabled&&u.rxEnabled;
      if(!enabled)return;
      this.bus.observeRx('uart'+i+'rx',avr?'D0':this.rpPin('uart',i,'rx'),this.inputs,u.baudRate,avr?u.bitsPerChar:u.wordLength,avr?u.stopBits:(u.lineCtrlRegister&8?2:1),avr?u.parityEnabled:!!(u.lineCtrlRegister&2),avr?u.parityOdd:!(u.lineCtrlRegister&4),(v,error={})=>{if(avr){if(!u.rxBusy){u.writeByte(v,true);this.cpu.data[0xc0]=(this.cpu.data[0xc0]&~0x14)|(error.framing?0x10:0)|(error.parity?4:0);}}else u.feedByte(v|(error.framing?0x100:0)|(error.parity?0x200:0));});
    });
  }
  get cycles(){return this.cpu.cycles;}
  get pc(){return this.avr?this.cpu.pc*2:this.cpu.PC;}
  tick(req) {
    const v=Number(req.vcc), dt=Number(req.dt);const started=this.cycles;this.supply=v;
    if(req.electrical_bus!==undefined)this.electrical=req.electrical_bus===true;
    if(!Number.isFinite(v)||!Number.isFinite(dt)||dt<0||dt>.005)throw Error('tick needs finite vcc and dt 0..0.005 s');
    const valid=this.avr?v>=4.5&&v<=5.5:v>=3.0&&v<=3.6;
    if(!valid || req.reset) {this.powered=valid;this.reset();if(!valid){this.status='No power / supply outside supported logic rail';return this.snapshot();}this.status='Reset held';return this.snapshot(false);}
    this.powered=true;
    if(req.run===false){this.status='Stopped';return this.snapshot(false);}
    this.inputs=req.pins||{};
    for(const [name,voltage] of Object.entries(this.inputs)) {
      if(!Number.isFinite(voltage))throw Error('Nonfinite pin voltage');
      if(this.avr) {
        const p=this.pins[name];if(!p)throw Error('Unknown Uno pin '+name);
        // Datasheet thresholds; retain previous state in undefined band.
        if(!p.analogOnly&&(voltage<=.3*v || voltage>=.6*v))p.port.setPin(p.bit,voltage>=.6*v);
        if(name[0]==='A')this.adc.channelValues[+name.slice(1)]=Math.max(0,Math.min(v,voltage));
      } else {
        const n=+name.slice(2);if(!/^GP\d+$/.test(name)||n>29)throw Error('Unknown Pico pin '+name);
        if(voltage<=.8 || voltage>=2)this.mcu.gpio[n].setInputValue(voltage>=2);
        if(n>=26)this.mcu.adc.channelValues[n-26]=Math.round(Math.max(0,Math.min(1,voltage/(Number.isFinite(req.aref)&&req.aref>0?Math.min(v,req.aref):v)))*4095);
      }
    }
    if(this.avr){this.adc.avcc=v;this.adc.aref=Number.isFinite(req.aref)?Math.max(0,Math.min(v,req.aref)):v;}
    for(const entry of (req.uart_rx||[]).slice(0,16)){
      const u=this.uart[integer(entry.port,0,this.uart.length-1,'UART port')];
      const value=integer(entry.value,0,255,'UART byte');
      if(this.avr){if(!u.rxBusy)u.writeByte(value);}else u.feedByte(value);
    }
    if(req.breakpoints!==undefined)this.breakpoints=req.breakpoints.slice(0,32).map(n=>integer(n,0,0xffffffff,'breakpoint'));
    if(this.paused&&!req.resume&&!req.step)return this.snapshot();
    if(req.resume || req.step)this.paused=false;
    const target=this.cycles+(req.instruction_step?1:Math.ceil(dt*this.hz));let count=0;let barrier=false;
    if(this.electrical){this.syncBuses();this.observeUart();barrier=this.bus.pump(this.inputs);}
    const limit=(req.step||req.instruction_step)?1:100000;
    this.status='Running';
    while(this.cycles<target && count<limit && !this.paused && !barrier){
      if(!req.step&&!(req.resume&&count===0)&&this.breakpoints.includes(this.pc)){this.paused=true;this.status='Breakpoint';break;}
      if(this.avr){avr.avrInstruction(this.cpu);this.cpu.tick();}
      else if(this.cpu.waiting){const n=Math.min(this.clock.nanosToNextAlarm,(target-this.cycles)*8,this.electrical?Math.max(1,this.bus.next()-this.cycles)*8:Infinity);this.clock.tick(n);this.cpu.cycles+=Math.max(1,Math.ceil(n/8));}
      else {const cycles=this.cpu.executeInstruction();this.clock.tick(cycles*8);}
      count++;
      if(this.electrical&&!req.defer_bus)barrier=this.bus.pump(this.inputs);
    }
    if(req.step){this.paused=true;this.status='Paused';}
    else if(!req.instruction_step&&count===limit && this.cycles<target)this.status='Instruction budget reached';
    const result=this.snapshot();result.instructions=count;result.requested_cycles=Math.ceil(dt*this.hz);result.elapsed_cycles=this.cycles-started;result.bus_barrier=barrier;return result;
  }
  snapshot(driving=true) {
    const outputs={},modes={},pulls={};
    if(this.powered&&driving) {
      const pins=this.avr?Object.keys(this.pins):Array.from({length:30},(_,i)=>'GP'+i);
      for(const name of pins){const p=this.avr?this.pins[name]:null;const s=p?(p.analogOnly?2:p.port.pinState(p.bit)):this.mcu.gpio[+name.slice(2)].value;modes[name]=s<2?'out':'in';if(s<2)outputs[name]=s;else if(s===3)pulls[name]='up';else if(s===4)pulls[name]='down';}
    }
    if(this.electrical&&this.powered&&driving)for(const [pin,state] of Object.entries(this.bus.drives)){delete outputs[pin];delete pulls[pin];modes[pin]=state<2?'out':'in';if(state<2)outputs[pin]=state;}
    const result={bus_next_cycle:this.electrical&&Number.isFinite(this.bus.next())?this.bus.next():null,bus_errors:this.electrical?this.bus.errors.slice():[],capabilities:{gpio:true,adc:true,pwm:true,uart:this.electrical?'electrical-cooperative':'byte-endpoint',spi:this.electrical?'electrical-cooperative':'disconnected-open-bus',i2c:this.electrical?'electrical-open-drain-cooperative':'disconnected-open-bus',usb:false,boot_rom:false,micropython:false},backend:this.avr?'avr8js-0.21.0':'rp2040js-1.3.3',board:this.board,outputs,modes,pulls,status:this.status,powered:this.powered,time:this.cycles/this.hz,cycles:this.cycles,pc:this.pc,line:0,serial:this.serial.splice(0),events:this.events.splice(0),dropped_events:this.dropped,registers:Array.from(this.avr?this.cpu.data.slice(0,32):this.cpu.registers)};
    this.dropped=0;return result;
  }
}
module.exports={Machine,hexImage};

