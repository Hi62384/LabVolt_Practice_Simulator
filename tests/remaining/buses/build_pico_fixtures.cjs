'use strict';
const fs=require('node:fs'),path=require('node:path');
const a=require('../../../scripts/firmware_backends/vendor/rp2040js/cjs/utils/assembler.js');
function build(kind){const words=[],literals=[];const emit=x=>words.push(x);const lit=(r,value)=>{literals.push({at:8+words.length*2,r,value});emit(0);};
 const write=(address,value)=>{lit(0,address);lit(1,value);emit(a.opcodeSTR(1,0,0));};
 const wait=(address,mask)=>{lit(0,address);const target=words.length;emit(a.opcodeLDRimm(1,0,0));emit(a.opcodeMOVS(2,mask));emit(a.opcodeANDS(1,2));emit(a.opcodeCMPimm(1,0));const branch=words.length;emit(a.opcodeBT1(1,(target-branch)*2-4));};
 const mux=(pin,func)=>write(0x40014004+pin*8,func);
 if(kind==='pico-display'){
  mux(0,1);mux(2,1);mux(3,1);mux(5,5);write(0xd0000024,32);write(0xd0000014,32);
  write(0x4003c000,7);write(0x4003c010,250);write(0x4003c004,2);write(0xd0000018,32);
  for(const value of [0,72,105]){write(0x4003c008,value);wait(0x4003c00c,16);}
  write(0xd0000014,32);
 }else if(kind==='pico-uart'){
  mux(0,2);mux(1,2);write(0x40034024,813);write(0x40034028,52);write(0x4003402c,0x60);write(0x40034030,0x301);write(0x40034000,0x55);wait(0x40034018,16);lit(0,0x40034000);emit(a.opcodeLDRimm(7,0,0));emit(a.opcodeSTR(7,0,0));
 }else{
  mux(0,3);mux(1,3);write(0x40044000,0x63);write(0x40044004,0x20);write(0x40044014,625);write(0x40044018,625);write(0x4004406c,1);write(0x40044010,0x2a5);wait(0x40044070,1);
 }
 emit(a.opcodeMOVS(6,0x77));emit(a.opcodeBT2(-4));
 while((8+words.length*2)%4)emit(a.opcodeNOP());
 const start=8+words.length*2;const image=Buffer.alloc(start+literals.length*4);image.writeUInt32LE(0x20041000,0);image.writeUInt32LE(0x10000009,4);
 literals.forEach((x,i)=>{const at=start+i*4;const delta=at-((x.at+4)&~3);if(delta>1020)throw Error('literal out of range');words[(x.at-8)/2]=a.opcodeLDRlit(x.r,delta);image.writeUInt32LE(x.value>>>0,at);});words.forEach((w,i)=>image.writeUInt16LE(w,8+i*2));return {board:'pico',image:image.toString('base64'),vector_offset:0};}
if(require.main===module){fs.mkdirSync(process.argv[2],{recursive:true});for(const kind of ['pico-display','pico-i2c','pico-uart'])fs.writeFileSync(path.join(process.argv[2],kind+'.json'),JSON.stringify(build(kind)));}
module.exports={build};
