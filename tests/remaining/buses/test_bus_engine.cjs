'use strict';
const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const {Machine}=require('../../../scripts/firmware_backends/machine.cjs');
const {build}=require('./build_pico_fixtures.cjs');
let checks=0;function check(ok,label){assert.ok(ok,label);console.log('PASS '+label);checks++;}
const idle=':02000000FFCF30\n:00000001FF';
for(let mode=0;mode<4;mode++)for(const lsb of [false,true]){
 const m=new Machine({board:'uno',image:idle});m.tick({vcc:5,dt:0,electrical_bus:true});m.cpu.writeData(0x24,0x2c);
 const control=0x53|((mode&1)?4:0)|((mode&2)?8:0)|(lsb?32:0);m.cpu.writeData(0x4c,control);m.cpu.writeData(0x4e,0x96);
 let pins={D12:0,D0:5};let count=0,s;
 do{s=m.tick({vcc:5,dt:.000005,pins});pins={D12:(s.outputs.D11||0)*5,D0:5};assert.equal(s.dropped_events,0);assert.ok(s.elapsed_cycles<=82);count++;}while(m.spi.transmissionActive&&count<200);
 check(!m.spi.transmissionActive&&m.cpu.readData(0x4e)===0x96,'AVR SPI solved-wire loopback mode '+mode+' '+(lsb?'LSB':'MSB'));
}
const missing=new Machine({board:'uno',image:idle});missing.tick({vcc:5,dt:0,electrical_bus:true});missing.cpu.writeData(0xb8,72);missing.cpu.writeData(0xbc,0xa4);
let s;for(let i=0;i<5000;i++){s=missing.tick({vcc:5,dt:.0005,pins:{A5:0,A4:0,D0:5}});if(s.bus_errors.length)break;}
check(s.bus_errors.some(e=>e.error.includes('stretch')),'I2C missing pullup/stuck-low clock fails with a bounded error');
check(!Object.values(missing.bus.drives).some(v=>v===1),'I2C never drives a push-pull high');
s=missing.tick({vcc:0,dt:.0001});check(!s.powered&&Object.keys(s.outputs).length===0&&Object.keys(missing.bus.drives).length===0,'power loss clears queued transfers and all bus drivers');
const nano=new Machine({board:'nano',image:idle});nano.tick({vcc:5,dt:0,pins:{A6:2.5,A7:5}});nano.cpu.writeData(0x7c,0x46);nano.cpu.writeData(0x7a,0xc7);nano.tick({vcc:5,dt:.001,pins:{A6:2.5,A7:5}});
check(Math.abs((nano.cpu.data[0x78]+256*nano.cpu.data[0x79])-512)<=1,'classic Nano ADC6 executes actual ATmega328P ADC');
check(!nano.snapshot().outputs.A6&&!nano.snapshot().outputs.A7&&nano.pins.A6.analogOnly,'Nano A6/A7 are analog-only inputs, not fabricated GPIO');
const pico=new Machine(build('pico-display'));pico.tick({vcc:3.3,dt:.000005,electrical_bus:true,pins:{GP0:3.3}});
check(pico.rpPin('spi',0,'sck')==='GP2'&&pico.rpPin('spi',0,'tx')==='GP3','Pico SPI follows actual IO_BANK0 mux');
const mismatch=new Machine(build('pico-display'));mismatch.tick({vcc:3.3,dt:0,electrical_bus:true});mismatch.mcu.spi[0].writeUint32(0x10,2);mismatch.mcu.spi[0].writeUint32(0,7);mismatch.mcu.spi[0].writeUint32(8,0x44);
check(mismatch.bus.errors.some(e=>e.error.includes('mux')),'unconfigured Pico peripheral mux reports unavailable pins rather than delivering bytes');
assert.throws(()=>new Machine({board:'esp32',image:idle}));checks++;console.log('PASS incompatible board architecture rejected');


const arbitration=new Machine({board:'uno',image:idle});arbitration.tick({vcc:5,dt:0,electrical_bus:true});arbitration.cpu.writeData(0xbc,4);let completed=false;arbitration.bus.write('i2c0',['A5','A4'],0x80,100000,()=>completed=true);
for(let i=0;i<100;i++){const drives=arbitration.bus.drives;arbitration.tick({vcc:5,dt:.000005,pins:{A5:drives.A5===0?0:5,A4:0}});if(arbitration.bus.errors.length)break;}
check(arbitration.twi.status===0x38&&!completed&&arbitration.bus.drives.A4===2,'I2C wired-low contention releases SDA immediately and raises AVR arbitration-lost status');
for(const parity of [false,true]){
 const rx=new Machine({board:'uno',image:idle});rx.tick({vcc:5,dt:0,electrical_bus:true,pins:{D0:5}});rx.cpu.writeData(0xc4,103);rx.cpu.writeData(0xc2,parity?0x26:6);rx.cpu.writeData(0xc1,16);
 for(let i=0;i<1000;i++){const position=rx.cycles/1664;const level=parity?(position>=9?5:0):0;rx.tick({vcc:5,dt:.000005,pins:{D0:level}});if(rx.cpu.data[0xc0]&128)break;}
 check(!!(rx.cpu.data[0xc0]&(parity?4:16))&&!!(rx.cpu.data[0xc0]&128),'electrical UART '+(parity?'parity':'framing')+' error sets real AVR receive status with received byte');
}

console.log('BUS ENGINE CHECKS: '+checks);
