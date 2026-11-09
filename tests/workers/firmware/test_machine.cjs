'use strict';
const assert=require('node:assert/strict');
const fs=require('node:fs');const path=require('node:path');
const {Machine,hexImage}=require('../../../scripts/firmware_backends/machine.cjs');
let checks=0;function check(ok,label){assert.ok(ok,label);checks++;console.log('PASS '+label);}
function hex(words){const data=Buffer.alloc(words.length*2);words.forEach((w,i)=>data.writeUInt16LE(w,i*2));let text='';for(let i=0;i<data.length;i+=16){const b=[Math.min(16,data.length-i),i>>8,i&255,0,...data.subarray(i,i+16)];text+=':'+Buffer.from([...b,(-b.reduce((a,v)=>a+v,0))&255]).toString('hex').toUpperCase()+'\n';}return text+':00000001FF';}
const unoImage=hex([0x9a25,0x9a2d,0x982d,0xcffd]); // sbi DDRB,5; sbi PORTB,5; cbi PORTB,5; rjmp -3
const uno=new Machine({board:'uno',image:unoImage});
let s=uno.tick({vcc:5,dt:.00001});
check(s.events.some(e=>e.pin==='D13'&&e.state===1)&&s.events.some(e=>e.pin==='D13'&&e.state===0),'Uno executes actual AVR instructions and toggles D13');
check(uno.cpu.data.length===2304,'Uno has 2 KiB SRAM plus register/I/O space');
const before=s.cycles;s=uno.tick({vcc:5,dt:0,run:false});check(s.cycles===before&&Object.keys(s.outputs).length===0,'stop yields and tri-states outputs');
s=uno.tick({vcc:0,dt:.001});check(!s.powered&&s.cycles===0&&Object.keys(s.outputs).length===0,'power loss clears CPU and GPIO');
s=uno.tick({vcc:5,dt:.001,breakpoints:[2]});check(s.status==='Breakpoint'&&s.pc===2,'AVR PC breakpoint before PORT write');
s=uno.tick({vcc:5,dt:.001,step:true});check(s.instructions===1&&s.outputs.D13===1,'AVR single step executes one instruction');
check(uno.tick({vcc:5,dt:.001,reset:true,breakpoints:[]}).cycles===0,'asserted reset holds CPU at reset vector');
check(uno.tick({vcc:5,dt:.001,breakpoints:[]}).cycles>0,'release reset restarts actual image');
const input=new Machine({board:'uno',image:hex([0xb109,0xcffe])}); // in r16,PIND; rjmp -2
input.tick({vcc:5,pins:{D2:5},dt:.000001});check((input.cpu.data[16]&4)!==0,'AVR reads electrical GPIO high');
input.tick({vcc:5,pins:{D2:0},dt:.000001});check((input.cpu.data[16]&4)===0,'AVR reads electrical GPIO low');
const button=new Machine({board:'uno',image:hex([0x9a25,0x982d,0x994a,0x9a2d,0xcffc])});
s=button.tick({vcc:5,pins:{D2:5},dt:.001,breakpoints:[8]});check(s.outputs.D13===1,'real AVR button program drives D13 high');
s=button.tick({vcc:5,pins:{D2:0},dt:.001,resume:true});check(s.outputs.D13===0,'real AVR button program drives D13 low after electrical input changes');
input.tick({vcc:5,pins:{A0:2.5},dt:0});input.cpu.writeData(0x7c,0x40);input.cpu.writeData(0x7a,0xc7);
input.tick({vcc:5,pins:{A0:2.5},dt:.001});check(Math.abs((input.cpu.data[0x78]+input.cpu.data[0x79]*256)-512)<=1,'Uno ADC converts input voltage with AVCC reference');
// Timer0 OC0A drives D6 with hardware fast PWM, not duty-cycle text parsing.
input.cpu.writeData(0x2a,0x40);input.cpu.writeData(0x44,0x83);input.cpu.writeData(0x45,1);input.cpu.writeData(0x47,128);
s=input.tick({vcc:5,dt:.001});check(s.events.some(e=>e.pin==='D6'&&e.state===1)&&s.events.some(e=>e.pin==='D6'&&e.state===0),'AVR hardware timer PWM transitions are observed');
// Pico raw flash fixture: vectors, ldr GPIO control; SIO output-enable + output.
const picoBytes=Buffer.alloc(56);picoBytes.writeUInt32LE(0x20041000,0);picoBytes.writeUInt32LE(0x10000009,4);
const thumb=[0x4807,0x2105,0x6001,0x4807,0x2101,0x6201,0x6101,0x2100,0x6101,0xe7fa];
thumb.forEach((w,i)=>picoBytes.writeUInt16LE(w,8+i*2));
picoBytes.writeUInt32LE(0x40014004,40);picoBytes.writeUInt32LE(0xd0000000,44);
const picoSpec={board:'pico',image:picoBytes.toString('base64'),vector_offset:0};const pico=new Machine(picoSpec);
s=pico.tick({vcc:3.3,dt:.00001});
check(s.events.some(e=>e.pin==='GP0'&&e.state===1)&&s.events.some(e=>e.pin==='GP0'&&e.state===0),'Pico executes genuine Thumb instructions and toggles GP0');
s=pico.tick({vcc:5,dt:.001});check(!s.powered&&Object.keys(s.outputs).length===0,'Pico rejects 5V on 3V3 logic supply');
pico.tick({vcc:3.3,dt:0,pins:{GP26:1.65}});pico.mcu.adc.writeUint32(0,5);
pico.tick({vcc:3.3,dt:.0001});check(Math.abs(pico.mcu.adc.result-2048)<=1,'Pico ADC converts 3V3-relative input to 12 bits');
s=pico.tick({vcc:3.3,dt:.005});check(s.instructions<=100000,'Pico infinite guest loop bounded by instruction budget');
check(s.dropped_events>=0&&s.events.length<=256,'event buffers are bounded with explicit loss count');
// Peripheral register-level checks complement the instruction-executing fixtures.
input.cpu.writeData(0xc4,103);input.cpu.writeData(0xc1,0x18);input.cpu.writeData(0xc6,65);
s=input.tick({vcc:5,dt:.002});check(s.serial.some(b=>b.value===65),'AVR USART transmit reaches serial monitor');
input.tick({vcc:5,dt:.002,uart_rx:[{port:0,value:66}]});check(input.cpu.readData(0xc6)===66,'AVR USART receives host serial byte');
input.cpu.writeData(0x4c,0x50);input.cpu.writeData(0x4e,0x42);s=input.tick({vcc:5,dt:.001});
check(s.events.some(e=>e.type==='spi'&&e.value===0x42)&&input.cpu.readData(0x4e)===255,'AVR SPI open bus returns 0xff rather than invented peripheral');
pico.mcu.uart[0].writeUint32(0x30,0x301);pico.mcu.uart[0].writeUint32(0,67);
s=pico.tick({vcc:3.3,dt:.0001});check(s.serial.some(b=>b.value===67),'Pico UART transmit reaches serial monitor');
pico.tick({vcc:3.3,dt:0,uart_rx:[{port:0,value:68}]});check(pico.mcu.uart[0].readUint32(0)===68,'Pico UART receives host serial byte');
pico.mcu.writeUint32(0x40014014,4); // GP2 mux PWM slice 1 channel A
pico.mcu.pwm.writeUint32(0x18,16);pico.mcu.pwm.writeUint32(0x24,255);pico.mcu.pwm.writeUint32(0x20,128);pico.mcu.pwm.writeUint32(0x14,1);
s=pico.tick({vcc:3.3,dt:.00001});check(s.events.some(e=>e.pin==='GP2'&&e.state===1)&&s.events.some(e=>e.pin==='GP2'&&e.state===0),'Pico hardware PWM produces GPIO transitions');
input.cpu.writeData(0xbc,0xa4);input.tick({vcc:5,dt:.0001});
input.cpu.writeData(0xbb,0x78);input.cpu.writeData(0xbc,0x84);s=input.tick({vcc:5,dt:.0001});
check(s.events.some(e=>e.type==='i2c'&&e.address===0x3c&&e.nack)&&((input.cpu.data[0xb9]&0xf8)===0x20),'AVR I2C reports address NACK with no attached peripheral');
pico.mcu.i2c[0].writeUint32(0,0x63);pico.mcu.i2c[0].writeUint32(4,0x3c);pico.mcu.i2c[0].writeUint32(0x6c,1);pico.mcu.i2c[0].writeUint32(0x10,42);
s=pico.tick({vcc:3.3,dt:.00001});check(s.events.some(e=>e.type==='i2c'&&e.address===0x3c&&e.nack),'Pico I2C reports address NACK with no attached peripheral');
check(JSON.parse(JSON.stringify(s)).board==='pico','host snapshot is JSON serializable');
assert.throws(()=>hexImage(':0000000100',32768));checks++;console.log('PASS invalid HEX checksum rejected');
assert.throws(()=>new Machine({board:'pico',image:Buffer.alloc(8).toString('base64'),vector_offset:0}));checks++;console.log('PASS invalid Pico vectors rejected');
assert.throws(()=>pico.tick({vcc:3.3,dt:Infinity}));checks++;console.log('PASS nonfinite guest scheduling rejected');
if(process.argv.includes('--write-fixtures')){
 const root=path.resolve(__dirname,'../../../assets/workers/firmware');
 fs.writeFileSync(path.join(root,'uno-toggle.hex'),unoImage+'\n');fs.writeFileSync(path.join(root,'pico-toggle.json'),JSON.stringify(picoSpec,null,2));
}
console.log('MACHINE CHECKS: '+checks);
module.exports={unoImage,picoSpec};

