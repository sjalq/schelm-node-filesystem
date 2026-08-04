"use strict";
const cp=require("node:child_process");const fs=require("node:fs");const path=require("node:path");
const root=path.resolve(__dirname,"..");const compiler=process.env.SCHELM_ELM || "/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author/result/bin/elm";
if(!fs.existsSync(compiler)){console.error(`BLOCKED: Schelm Elm compiler binary missing: ${compiler}\nRequired commit: 76bbe44424106c96f915cb24cd7f50d69f5cee0e`);process.exit(2);}
for(const mode of ["debug","optimize"]){const args=["make","tests/workers/AtomicTextWorker.elm","--output",`build/atomic-${mode}.js`];if(mode==="optimize")args.push("--optimize");cp.execFileSync(compiler,args,{cwd:root,stdio:"inherit"});}
