'use strict';
const fs=require('node:fs');const assert=require('node:assert/strict');
const {Machine}=require('../../../scripts/firmware_backends/machine.cjs');
const m=new Machine({board:'uno',image:fs.readFileSync(process.argv[2],'utf8')});
let edges=[],dropped=0;
for(let i=0;i<300;i++){
 const s=m.tick({vcc:5,dt:.0005});dropped+=s.dropped_events;
 edges.push(...s.events.filter(e=>e.type==='gpio'&&e.pin==='D13'&&e.state<2));
}
assert.equal(dropped,0,'no lost transitions');
assert.ok(edges.some(e=>e.state===1)&&edges.some(e=>e.state===0),'Arduino sketch toggles LED');
const periods=edges.slice(2).map((e,i)=>e.cycle-edges[i+1].cycle);
for(const p of periods)assert.ok(Math.abs(p/16e6-.01)<.0002,'Arduino delay(10) matches hardware timer clock');
console.log('PASS real Arduino C++ sketch: '+edges.length+' GPIO edges; 10 ms delays within 0.2 ms; no dropped events');
