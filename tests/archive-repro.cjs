"use strict";
const fs=require("node:fs");const crypto=require("node:crypto");const path=require("node:path");
const roots=["elm.json","LICENSE","README.md","src/Schelm","src/Elm"];
function files(p){const st=fs.statSync(p);if(st.isDirectory())return fs.readdirSync(p).sort().flatMap(n=>files(path.join(p,n)));return[p];}
const listed=roots.flatMap(files).sort();const hash=crypto.createHash("sha256");for(const file of listed){hash.update(file.replaceAll(path.sep,"/"));hash.update("\0");hash.update(fs.readFileSync(file));hash.update("\0");}
const digest=hash.digest("hex");if(listed.some(f=>f.includes("Fixture")||f.includes("fixture")))throw new Error("fixture leaked into archive list");console.log(JSON.stringify({files:listed.length,sha256:digest}));
