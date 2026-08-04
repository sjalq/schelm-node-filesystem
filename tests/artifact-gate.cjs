"use strict";
const fs=require("node:fs");
const production=["src/Elm/Kernel/SchelmAtomicText.js","build/atomic-debug.js","build/atomic-optimize.js"];
const forbidden=["@fixture","observe(","BeforeTempOpen","AfterParentCloseAck","AfterRenameAck","WritePhysicalComplete","RenamePhysicalComplete","schelmFixtureObserver","SCHELM_FS_TEST_HOOK","fixtureAck","faultPlan","SchelmAtomicTextFixture","process.env"];
for(const file of production){if(!fs.existsSync(file)){console.error(`production artifact missing: ${file}`);process.exit(1);}const body=fs.readFileSync(file,"utf8");for(const token of forbidden)if(body.includes(token)){console.error(`${file} contains forbidden fixture token ${token}`);process.exit(1);}}
const fixture=fs.readFileSync("fixtures/package/src/Elm/Kernel/SchelmAtomicTextFixture.js","utf8");for(const token of ["BeforeTempOpen","AfterParentCloseAck","AfterRenameAck","WritePhysicalComplete","RenamePhysicalComplete"])if(!fixture.includes(token)){console.error(`fixture positive control missing ${token}`);process.exit(1);}
console.log("artifact gate passed for source, debug, and optimize production artifacts");
