"use strict";
const cp=require("node:child_process");const fs=require("node:fs");
function run(n){cp.execFileSync(process.execPath,["tests/perf/generated-worker-bench.cjs"],{stdio:["ignore","ignore","inherit"]});const out=JSON.parse(fs.readFileSync("build/generated-worker-perf.json","utf8"));fs.copyFileSync("build/generated-worker-perf.json",`build/generated-worker-perf-${n}.json`);return out;}
const first=run(1),second=run(2);function bad(report){return report.evidence.some(x=>!Number.isFinite(x.medianMs)||x.medianMs<=0||x.rounds.length!==9);}
if(bad(first)&&bad(second))throw new Error("generated worker performance gate failed twice");console.log("generated optimized worker performance matrix passed twice");
