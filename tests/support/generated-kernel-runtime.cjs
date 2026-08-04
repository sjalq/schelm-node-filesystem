"use strict";
const fs=require("node:fs");const vm=require("node:vm");
function loadKernel(file, symbol, observe){
  const source=fs.readFileSync(file,"utf8")+`\nmodule.exports.__entry=${symbol};`;
  const module={exports:{}};
  const context={module,exports:module.exports,require,Buffer,console,setImmediate,clearImmediate,globalThis:{}};
  context.globalThis=context;
  if(observe)context.__SCHELM_ATOMIC_TEXT_FIXTURE_OBSERVE=observe;
  context.F3=fn=>function(a){return function(b){return function(c){return fn(a,b,c);};};};
  context.__List_toArray=list=>list;
  context.__List_fromArray=array=>array;
  context.__Scheduler_succeed=value=>({ok:true,value});
  context.__Scheduler_fail=value=>({ok:false,value});
  context.__Scheduler_binding=callback=>({__callback:callback});
  vm.runInNewContext(`(function(require,module,exports){${source}\n})(require,module,exports);`,context,{filename:file});
  return module.exports.__entry;
}
function start(entry,root,segments,text){
  const task=entry(root)(segments)(text);let notifications=[];
  const kill=task.__callback(result=>notifications.push(result));
  return{kill,notifications,settled:async()=>{for(let i=0;i<200&&notifications.length===0;i++)await new Promise(r=>setTimeout(r,5));return notifications;}};
}
module.exports={loadKernel,start};
