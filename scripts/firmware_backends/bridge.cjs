'use strict';
// Bounded host emulator or conservative group per owned process. Guest has no JS, filesystem or socket syscall API.
const {Worker,isMainThread,parentPort}=require('node:worker_threads');
if(!isMainThread){
  const {Machine}=require('./machine.cjs');const {NativeGroup}=require('../electronics_buses/native_group.cjs');let machine,upload=null,group=null,groupTickSequence=0;
  parentPort.on('message',req=>{try{let state;
    if(req.op==='group_begin'){group=new NativeGroup();groupTickSequence=0;state={status:'Native group configured'};}
    else if(req.op==='group_input'){if(!group)throw Error('Configure group first');group.input(req.id,req.epoch,req.input);state={status:'Group input accepted'};}
    else if(req.op==='group_tick'){if(!group)throw Error('Configure group first');if(req.tick_sequence!==undefined&&(!Number.isSafeInteger(req.tick_sequence)||req.tick_sequence!==groupTickSequence+1))throw Error('Native group request sequence mismatch');state=group.tick(req.dt);if(req.tick_sequence!==undefined){groupTickSequence=req.tick_sequence;state.tick_sequence=groupTickSequence;}}
    else if(req.op==='image_begin'){if(!req.spec||!['uno','nano','pico'].includes(req.spec.board))throw Error('Invalid image target');upload={...req.spec,image:''};state={status:'Receiving image'};}
    else if(req.op==='image_chunk'){if(!upload||typeof req.data!=='string'||req.data.length>2048||upload.image.length+req.data.length>2800000)throw Error('Image upload limit');upload.image+=req.data;state={status:'Receiving image'};}
    else if(req.op==='image_commit'){if(!upload)throw Error('No pending image');if(upload.device_id!==undefined){if(!group)throw Error('Configure group first');group.add(upload.device_id,upload.board_epoch,upload);state={status:'Group machine loaded'};}else{machine=new Machine(upload);state=machine.snapshot();}upload=null;}
    else if(req.op==='load'){if(req.device_id!==undefined){if(!group)throw Error('Configure group first');group.add(req.device_id,req.board_epoch,req);state={status:'Group machine loaded'};}else{machine=new Machine(req);state=machine.snapshot();}}
    else if(req.op==='tick'&&machine)state=machine.tick(req);
    else if(req.op==='reset'&&machine){machine.reset();state=machine.snapshot();}
    else throw Error('Load firmware before tick/reset');
    parentPort.postMessage({ok:true,state});
  }catch(e){parentPort.postMessage({ok:false,error:String(e.message).slice(0,512)});}});
}else{
  const worker=new Worker(__filename,{resourceLimits:{maxOldGenerationSizeMb:64,maxYoungGenerationSizeMb:16,stackSizeMb:4}});
  let pending=false,buffer='',timer;
  const reply=value=>process.stdout.write(JSON.stringify(value)+'\n');
  worker.on('message',res=>{clearTimeout(timer);pending=false;reply(res);});
  worker.on('error',e=>{reply({ok:false,error:'Emulator worker: '+e.message});process.exitCode=1;});
  worker.on('exit',()=>process.exit());
  process.stdin.setEncoding('utf8');
  process.stdin.on('data',data=>{
    buffer+=data;if(buffer.length>3000000){reply({ok:false,error:'Protocol size limit'});worker.terminate();return;}
    let end;
    while((end=buffer.indexOf('\n'))>=0){const line=buffer.slice(0,end);buffer=buffer.slice(end+1);
      try{const req=JSON.parse(line);if(req.op==='close'){worker.terminate();return;}if(pending)throw Error('One request at a time');pending=true;worker.postMessage(req);timer=setTimeout(()=>{reply({ok:false,error:'Emulator wall time limit'});worker.terminate();},2000);}
      catch(e){reply({ok:false,error:e.message});}
    }
  });
  process.stdin.on('end',()=>worker.terminate());
}
