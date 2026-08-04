"use strict";
const fs=require("node:fs");const path=require("node:path");const os=require("node:os");const vm=require("node:vm");
for(const file of ["atomic-debug.js","atomic-optimize.js","fixture-debug.js","fixture-optimize.js","cancel-debug.js","cancel-optimize.js"]){if(!fs.existsSync(path.join("build",file)))throw new Error(`missing ${file}`);}
// Full port execution is mandatory once artifacts exist; fail closed rather than treating compile-only as execution.
console.error("BLOCKED: generated artifacts exist but worker port bootstrap runner is not yet validated against the pinned compiler output");process.exit(2);
