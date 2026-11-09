'use strict';
// Conservative instruction-time scheduler over the existing Machine engines.
// No CPU starts an instruction beyond the earliest uncommitted electrical event.
const {Machine}=require('../firmware_backends/machine.cjs');
class NativeGroup {
 constructor(){this.devices=new Map();this.time=0;this.events=[];this.order=0;this.dirty=false;}
 add(id,epoch,spec){if(this.time!==0||this.devices.size>=8||this.devices.has(id)||typeof id!=='string'||!id||id.length>256||!Number.isSafeInteger(epoch)||epoch<0)throw Error('Invalid native group identity/epoch');const m=new Machine(spec);m.electrical=true;this.devices.set(id,{m,epoch,input:null,base:0,ready:0,last:m.snapshot(),outputs:{},pulls:{},serial:[]});}
 input(id,epoch,input){const e=this.devices.get(id);if(!e||e.epoch!==epoch)throw Error('Native group board epoch changed');
  for(const key of Object.keys(input))if(!['vcc','pins','run','reset','resume','step','breakpoints','uart_rx','aref'].includes(key))throw Error('Invalid group input field');
  if(!Number.isFinite(input.vcc)||!input.pins||typeof input.pins!=='object'||Array.isArray(input.pins)||Object.keys(input.pins).length>40)throw Error('Invalid group electrical input');
  for(const v of Object.values(input.pins))if(!Number.isFinite(v))throw Error('Nonfinite group pin');
  const active=Number(input.vcc)>=(e.m.avr?4.5:3)&&Number(input.vcc)<=(e.m.avr?5.5:3.6)&&input.run!==false&&!input.reset;
  const wasActive=e.active;const oldInput=e.input;e.input=structuredClone(input);e.active=active&&(!e.m.paused||input.resume||input.step);
  if(!active&&(!oldInput||wasActive||oldInput.vcc!==input.vcc||oldInput.reset!==input.reset||oldInput.run!==input.run)){e.last=e.m.tick({...input,dt:0,electrical_bus:true});e.outputs={};e.pulls={};e.ready=Infinity;e.base=this.time-e.m.cycles/e.m.hz;this.events=this.events.filter(x=>x.id!==id);this.dirty=true;}
  else if(e.active&&!wasActive){e.last=e.m.tick({vcc:input.vcc,pins:input.pins,aref:input.aref,run:true,dt:0,electrical_bus:true});e.outputs={...e.last.outputs};e.pulls={...e.last.pulls};e.base=this.time-e.m.cycles/e.m.hz;e.ready=this.time;this.dirty=true;}
 }
 snapshot(elapsed,barrier){const devices={};for(const [id,e] of this.devices){devices[id]={...e.last,outputs:{...e.outputs},pulls:{...e.pulls},serial:e.serial.splice(0),events:[],group_epoch:e.epoch};}return {schema:1,time:this.time,elapsed,bus_barrier:barrier,devices,instruction_resolution:true};}
 tick(dt){if(!Number.isFinite(dt)||dt<0||dt>.0005)throw Error('Group slice must be finite 0..0.5ms');for(const e of this.devices.values())if(!e.input)throw Error('Set every native group electrical input before stepping');
  const start=this.time,horizon=start+dt;if(this.dirty){this.dirty=false;return this.snapshot(0,true);}
  let instructions=0;
  while(instructions<1000000){
   this.events.sort((a,b)=>a.at-b.at||a.order-b.order);
   let chosen=null,ready=Infinity;for(const [id,e] of this.devices)if(e.active&&e.ready<ready){chosen=id;ready=e.ready;}
   const edge=this.events[0];
   if(edge&&edge.at<=ready+1e-15&&edge.at<=horizon+1e-15){this.time=Math.max(this.time,Math.min(horizon,edge.at));
    do{const x=this.events.shift(),e=this.devices.get(x.id);if(x.pin){delete e.outputs[x.pin];delete e.pulls[x.pin];if(x.state<2)e.outputs[x.pin]=x.state;else if(x.state===3||x.state===4)e.pulls[x.pin]=x.state===3?'up':'down';}}while(this.events[0]&&this.events[0].at<=this.time+1e-15);
    return this.snapshot(this.time-start,true);
   }
   if(chosen===null||ready>=horizon-1e-15){this.time=horizon;return this.snapshot(this.time-start,false);}
   this.time=Math.max(this.time,ready);const e=this.devices.get(chosen),m=e.m;
   const state=m.tick({...e.input,dt:0,instruction_step:true,electrical_bus:true,defer_bus:true});
   // One-shot debugger/serial controls are consumed once, never on every instruction.
   delete e.input.uart_rx;if(state.instructions>0){delete e.input.step;delete e.input.resume;}
   if(state.dropped_events>0)throw Error('Native group GPIO event budget reached');
   if(this.events.length>2048)throw Error('Native group pending edge budget reached');
   e.last=state;e.serial.push(...state.serial);if(e.serial.length>256)e.serial.splice(0,e.serial.length-256);
   for(const event of state.events)if(event.type==='gpio')this.events.push({id:chosen,pin:event.pin,state:event.state,at:e.base+event.cycle/m.hz,order:this.order++});
   if(state.bus_barrier)this.events.push({id:chosen,at:this.time,order:this.order++});
   e.ready=e.base+m.cycles/m.hz;
   if(m.paused)e.active=false;
   instructions++;
  }
  throw Error('Native group instruction budget reached');
 }
}
module.exports={NativeGroup};
