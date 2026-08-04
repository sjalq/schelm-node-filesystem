"use strict";
const fs=require("node:fs");
const prod=fs.readFileSync("src/Elm/Kernel/SchelmAtomicText.js","utf8");
const forbidden=["SCHELM_FS_TEST_HOOK","BeforeTempOpen","AfterRenameAck","fixtureAck","faultPlan","SchelmAtomicTextFixture","process.env","globalThis.__SCHELM"];
for(const token of forbidden){if(prod.includes(token)){console.error(`production artifact contains ${token}`);process.exit(1);}}
const fixture=fs.readFileSync("fixtures/package/src/Elm/Kernel/SchelmAtomicTextFixture.js","utf8");
if(!fixture.includes("BeforeTempOpen")||!fixture.includes("AfterRenameAck")){console.error("fixture positive control missing");process.exit(1);}
console.log("artifact gate passed");
