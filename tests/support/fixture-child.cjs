"use strict";
const fs=require("node:fs"); const fsp=fs.promises; const path=require("node:path");
const {schelmAtomicTextTransaction:run}=require("../../kernel-src/atomic-text-transaction.js");
const root=process.env.ROOT; const target=process.env.TARGET_PHASE;
let seq=0;
function send(x){if(process.send)process.send(x);}
async function observe(event){seq=event.sequence; send({type:"phase",...event}); if(event.phase===target){await new Promise(resolve=>{const on=m=>{if(m&&m.type==="ack"&&m.sequence===seq){send({type:"ack-accepted",sequence:seq});if(m.action!=="hold"){process.off("message",on);resolve();}}};process.on("message",on);});}}
const ops={join:path.join,dirname:path.dirname,basename:path.basename,lstat:fsp.lstat,open:fsp.open,rename:fsp.rename,unlink:fsp.unlink};
run({ops,root,segments:["s","state.json"],text:"new-complete",randomHex:()=>"0123456789abcdef0123456789abcdef",observe,operationId:"crash"}).then(result=>{send({type:"result",result});process.exit(0);});
