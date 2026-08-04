"use strict";
const cp=require("node:child_process");const fs=require("node:fs");const path=require("node:path");
const root=path.resolve(__dirname,"..");const compiler=process.env.SCHELM_ELM || "/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author/result/bin/elm";
const expected="76bbe44424106c96f915cb24cd7f50d69f5cee0e";
if(!fs.existsSync(compiler)){console.error(`BLOCKED: Schelm Elm compiler binary missing: ${compiler}\nRequired commit: ${expected}`);process.exit(2);}
const repo="/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author";
try{const actual=cp.execFileSync("git",["-C",repo,"rev-parse","HEAD"],{encoding:"utf8"}).trim();if(actual!==expected)throw new Error(`compiler checkout ${actual}, expected ${expected}`);}catch(error){console.error(`BLOCKED: cannot verify compiler commit: ${error.message}`);process.exit(2);}
fs.mkdirSync(path.join(root,"build"),{recursive:true});
const jobs=[
  {cwd:root,entry:"tests/workers/AtomicTextWorker.elm",stem:"atomic"},
  {cwd:path.join(root,"fixtures/package"),entry:"../../tests/workers/CancelWorker.elm",stem:"cancel"},
  {cwd:path.join(root,"fixtures/package"),entry:"../../AtomicTextFixtureWorker.elm",stem:"fixture"}
];
for(const job of jobs)for(const mode of ["debug","optimize"]){const out=path.join(root,"build",`${job.stem}-${mode}.js`);const args=["make",job.entry,"--output",out];if(mode==="optimize")args.push("--optimize");cp.execFileSync(compiler,args,{cwd:job.cwd,stdio:"inherit",env:{...process.env,ELM_HOME:process.env.SCHELM_ELM_HOME||path.join(root,"build/elm-home")}});}
cp.execFileSync(process.execPath,["tests/run-generated-workers.cjs"],{cwd:root,stdio:"inherit"});
cp.execFileSync(process.execPath,["tests/perf/generated-worker-gate.cjs"],{cwd:root,stdio:"inherit"});
