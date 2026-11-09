'use strict';
const assert=require('node:assert/strict');
const {Machine}=require('../../../scripts/firmware_backends/machine.cjs');
const fs=require('node:fs');
const uno=new Machine({board:'uno',image:':02000000FFCF30\n:00000001FF'});
const picoSpec=JSON.parse(fs.readFileSync(require('node:path').join(__dirname,'../../../assets/workers/firmware/pico-toggle.json'),'utf8'));
const pico=new Machine(picoSpec);
let checks=0;function check(value,label){assert.ok(value,label);checks++;console.log('PASS '+label);}
// Hold the AVR at a stable loop while hardware timer 0 runs fast PWM on OC0A/D6.
uno.tick({vcc:5,dt:0});
uno.cpu.writeData(0x2a,0x40);uno.cpu.writeData(0x44,0x83);uno.cpu.writeData(0x45,1);uno.cpu.writeData(0x47,128);
let s=uno.tick({vcc:5,dt:.0001});
const edges=s.events.filter(e=>e.pin==='D6'&&e.state===1).map(e=>e.cycle);
check(edges.length>=4&&edges.slice(1).every((c,i)=>Math.abs(c-edges[i]-256)<=2),'AVR PWM period is 256 CPU cycles within instruction boundary resolution');
check(s.events.filter(e=>e.pin==='D6').every(e=>e.cycle>=0&&e.cycle<=s.cycles),'GPIO edges carry bounded execution-cycle timestamps');
pico.tick({vcc:3.3,dt:0,pins:{GP26:.825},aref:1.65});pico.mcu.adc.writeUint32(0,5);
pico.tick({vcc:3.3,dt:.0001,pins:{GP26:.825},aref:1.65});
check(Math.abs(pico.mcu.adc.result-2048)<=1,'Pico ADC uses actual external ADC_VREF rather than hard-coded logic supply');
pico.mcu.writeUint32(0x40014014,4);
pico.mcu.pwm.writeUint32(0x18,16);pico.mcu.pwm.writeUint32(0x24,255);pico.mcu.pwm.writeUint32(0x20,128);pico.mcu.pwm.writeUint32(0x14,1);
s=pico.tick({vcc:3.3,dt:.00001});
const pEdges=s.events.filter(e=>e.pin==='GP2'&&e.state===1).map(e=>e.cycle);
check(pEdges.length>=3&&pEdges.slice(1).every((c,i)=>Math.abs(c-pEdges[i]-256)<=4),'Pico PWM period remains 256 CPU cycles at divider 1');
check(s.capabilities.spi==='disconnected-open-bus'&&s.capabilities.i2c==='disconnected-open-bus'&&!s.capabilities.boot_rom,'runtime capability report does not advertise missing physical buses or bootROM');
console.log('TIMING CHECKS: '+checks);
