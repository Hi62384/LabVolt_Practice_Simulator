'use strict';
const assert=require('node:assert/strict'),path=require('node:path'),{Worker}=require('node:worker_threads');
(async()=>{
 // Exercise the production bounded protocol worker without spawning another OS process.
 const worker=new Worker(path.resolve(__dirname,'../../../scripts/firmware_backends/bridge.cjs'),{resourceLimits:{maxOldGenerationSizeMb:64,maxYoungGenerationSizeMb:16,stackSizeMb:4}});
 const request=data=>new Promise((resolve,reject)=>{const timer=setTimeout(()=>reject(Error('owned worker timeout')),5000);worker.once('message',reply=>{clearTimeout(timer);resolve(reply);});worker.postMessage(data);});
 try{
  assert.ok((await request({op:'group_begin'})).ok);
  assert.ok((await request({op:'load',board:'uno',image:':02000000FFCF30\n:00000001FF',device_id:'cpu',board_epoch:7})).ok);
  assert.ok((await request({op:'group_input',id:'cpu',epoch:7,input:{vcc:5,pins:{D0:5}}})).ok);
  const first=await request({op:'group_tick',dt:.0005,tick_sequence:1});assert.ok(first.ok);assert.equal(first.state.tick_sequence,1);
  for(const tick_sequence of [1,3,1.5]){const rejected=await request({op:'group_tick',dt:.0005,tick_sequence});assert.equal(rejected.ok,false);assert.match(rejected.error,/sequence/);}
  const second=await request({op:'group_tick',dt:0,tick_sequence:2});assert.ok(second.ok);assert.equal(second.state.time,first.state.time);assert.equal(second.state.elapsed,0);
  const third=await request({op:'group_tick',dt:.0005,tick_sequence:3});assert.ok(third.ok);assert.equal(third.state.elapsed,.0005);
  console.log('PASS backend rejects duplicate, skipped and fractional tick requests before advancing group time');
  console.log('PASS accepted replies echo exact request sequence and preserve time after rejected requests');
 }finally{await worker.terminate();}
})().catch(e=>{console.error(e);process.exitCode=1;});
