'use strict';
const {NativeGroup}=require('../../../scripts/electronics_buses/native_group.cjs');const fs=require('node:fs'),path=require('node:path'),assert=require('node:assert/strict');
const root=process.argv[2];const g=new NativeGroup();
for(const [id,file] of [['a','uart-sender'],['b','uart-receiver']])g.add(id,7,{board:'uno',image:fs.readFileSync(path.join(root,file+'.hex'),'utf8')});
let states={a:{outputs:{}},b:{outputs:{}}},serial={a:[],b:[]},total=0,barriers=0,zero=0;
for(let i=0;i<10000&&total<.003-1e-14;i++){
 for(const id of ['a','b'])g.input(id,7,{vcc:5,pins:{D0:(states[id==='a'?'b':'a'].outputs.D1??1)*5}});
 const s=g.tick(Math.min(.0005,.003-total));total+=s.elapsed;states=s.devices;
 if(s.bus_barrier)barriers++;if(s.elapsed===0)zero++;
 for(const id of ['a','b'])serial[id].push(...s.devices[id].serial.map(x=>x.value));
}
assert.deepEqual(serial,{a:[0x3c,0xc3],b:[0xc3]});assert.ok(Math.abs(total-.003)<1e-14);assert.ok(barriers>10);
assert.throws(()=>g.input('a',8,{vcc:5,pins:{}}),/epoch/);
g.input('a',7,{vcc:0,pins:{}});g.input('b',7,{vcc:5,pins:{D0:5}});let s=g.tick(.0005);assert.equal(s.elapsed,0);assert.equal(s.devices.a.powered,false);assert.deepEqual(s.devices.a.outputs,{});
// Reapplying a static powered-off input must not create an endless zero-time barrier.
g.input('a',7,{vcc:0,pins:{}});s=g.tick(.0005);assert.ok(s.elapsed>0);
console.log('PASS two real AVR CPUs exchange different UART bytes through shared electrical pin levels');console.log('PASS exact 3ms total dt, '+barriers+' barriers, '+zero+' zero-time edges');console.log('PASS epoch rejection, power loss and stable inactive progress');
// Cross-architecture clock frontiers: actual AVR sender and Thumb UART firmware.
const mixed=new NativeGroup();mixed.add('avr',1,{board:'uno',image:fs.readFileSync(path.join(root,'uart-sender.hex'),'utf8')});mixed.add('pico',2,JSON.parse(fs.readFileSync(path.join(root,'pico-uart.json'),'utf8')));
let ms={avr:{outputs:{}},pico:{outputs:{}}},bytes={avr:[],pico:[]},mt=0;
for(let i=0;i<10000&&mt<.004-1e-14;i++){
 mixed.input('avr',1,{vcc:5,pins:{D0:(ms.pico.outputs.GP0??1)*3.3}});
 mixed.input('pico',2,{vcc:3.3,pins:{GP1:(ms.avr.outputs.D1??1)*5*2/3}});
 const r=mixed.tick(Math.min(.0005,.004-mt));mt+=r.elapsed;ms=r.devices;for(const id of ['avr','pico'])bytes[id].push(...r.devices[id].serial.map(x=>x.value));
}
assert.deepEqual(bytes,{avr:[0x3c,0x55],pico:[0x55,0x3c]});assert.ok(Math.abs(mt-.004)<1e-14);console.log('PASS mixed16MHz AVR/125MHz Pico UART frontier and exact4ms time (test divider voltage reference)');
const eight=new NativeGroup();for(let i=0;i<8;i++){eight.add('m'+i,i,{board:'uno',image:':02000000FFCF30\n:00000001FF'});eight.input('m'+i,i,{vcc:5,pins:{D0:5}});}const initial=eight.tick(0);assert.equal(initial.elapsed,0);assert.ok(initial.bus_barrier);const end=eight.tick(.0005);assert.equal(Object.keys(end.devices).length,8);assert.equal(end.elapsed,.0005);assert.throws(()=>eight.add('ninth',9,{board:'uno',image:':02000000FFCF30\n:00000001FF'}));console.log('PASS bounded eight-engine group and exact0.5ms horizon');

const resetAt=g.time;g.input('b',7,{vcc:5,pins:{D0:5},reset:true});s=g.tick(.0005);assert.equal(s.elapsed,0);assert.equal(s.devices.b.cycles,0);assert.deepEqual(s.devices.b.outputs,{});g.input('b',7,{vcc:5,pins:{D0:5},reset:false});let used=0;for(let i=0;i<100&&used<.0005-1e-14;i++){s=g.tick(.0005-used);used+=s.elapsed;}assert.ok(Math.abs(g.time-resetAt-.0005)<1e-14);console.log('PASS one CPU reset/release preserves group global clock and exact remaining dt');

const paused=new NativeGroup();paused.add('debug',1,{board:'uno',image:':02000000FFCF30\n:00000001FF'});paused.input('debug',1,{vcc:5,pins:{},breakpoints:[0]});paused.tick(0);const bp=paused.tick(.0001);assert.equal(bp.devices.debug.status,'Breakpoint');paused.input('debug',1,{vcc:5,pins:{},breakpoints:[0]});const stopped=paused.tick(.0001);assert.ok(stopped.elapsed>0);console.log('PASS debug-paused CPU does not create endless zero-time activation barriers');
