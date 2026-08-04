"use strict";
const fs = require("node:fs");
const path = require("node:path");
const crypto = require("node:crypto");
const root = path.resolve(__dirname, "..");
const canonicalPath = path.join(root, "kernel-src/atomic-text-transaction.js");
const canonical = fs.readFileSync(canonicalPath, "utf8");
const hash = crypto.createHash("sha256").update(canonical).digest("hex");
const functionStart = canonical.indexOf("async function schelmAtomicTextTransaction");
const exportStart = canonical.indexOf("\nmodule.exports =");
if (functionStart < 0 || exportStart < 0) throw new Error("canonical transaction markers missing");
const body = canonical.slice(functionStart, exportStart);
const fixtureMarker = /\/\* @fixture \*\/[^\n]*(?:\n|$)/g;
const productionBody = body.replace(fixtureMarker, "").replace(/[ \t]+$/gm, "");
if (productionBody.includes("@fixture")) throw new Error("unstripped fixture marker");
if (productionBody.includes("options.observe") || productionBody.includes("BeforeTempOpen") || productionBody.includes("AfterRenameAck")) throw new Error("fixture observation leaked into production body");
const header = (fixture) => `/*\nimport Elm.Kernel.List exposing (fromArray, toArray)\nimport Elm.Kernel.Scheduler exposing (binding, fail, succeed)\n*/\n/* generated; canonical-sha256 ${hash}; fixture=${fixture} */\nvar $fs = require("node:fs");\nvar $path = require("node:path");\nvar $crypto = require("node:crypto");\n`;
const ops = `\nfunction $schelmOps() { return {\n  join: $path.join, dirname: $path.dirname, basename: $path.basename,\n  lstat: function(p) { return $fs.promises.lstat(p); },\n  open: function(p, flags, mode) { return $fs.promises.open(p, flags, mode); },\n  rename: function(a, b) { return $fs.promises.rename(a, b); },\n  unlink: function(p) { return $fs.promises.unlink(p); }\n}; }\nfunction $schelmHex() { return $crypto.randomBytes(16).toString("hex"); }\n`;
const fixtureOps = `
var $schelmFixtureObserver = function(event) { return process["schelm" + "FixtureObserver"](event); };
function $schelmFixtureOps(base, observe, nextSequence, operationId) {
  function event(phase, facts) { return observe({ operationId: operationId, sequence: nextSequence(), phase: phase, facts: facts || {} }); }
  return Object.assign({}, base, {
    open: async function(p, flags, mode) { var handle = await base.open(p, flags, mode); if (flags !== "wx") return handle; var write = handle.write.bind(handle); handle.write = async function(buffer, offset, length, position) { await event("WriteDispatched", { offset: offset, length: length }); var result = await write(buffer, offset, length, position); await event("WritePhysicalComplete", { bytesWritten: result.bytesWritten }); await event("WriteCallbackDelivered", { bytesWritten: result.bytesWritten }); return result; }; return handle; },
    rename: async function(from, to) { await event("RenameDispatched", { from: from, to: to }); await base.rename(from, to); await event("RenamePhysicalComplete", { from: from, to: to }); await event("RenameCallbackDelivered", { from: from, to: to }); }
  });
}
`;
const elmAdapter = (fixture) => `\nfunction $schelmError(error) { return { __$kind: error.kind, __$code: error.code, __$message: error.message }; }\nfunction $schelmResult(result) { return { __$durability: result.durability, __$stage: result.stage, __$error: $schelmError(result.error), __$residue: __List_fromArray(result.residue) }; }\nfunction $schelmFailure(result) { return { __$phase: result.phase, __$error: $schelmError(result.error), __$residue: __List_fromArray(result.residue) }; }\nvar _${fixture ? "SchelmAtomicTextFixture" : "SchelmAtomicText"}_replace = F3(function(root, parts, text) {\n  return __Scheduler_binding(function(callback) {\n    var control = { abandoned: false };\n    ${fixture ? 'var nextSequence = (function() { var sequence = 0; return function() { return ++sequence; }; })(); var observe = $schelmFixtureObserver; ' : ''}schelmAtomicTextTransaction({ ops: ${fixture ? '$schelmFixtureOps($schelmOps(), observe, nextSequence, "fixture")' : '$schelmOps()'}, root: root, segments: __List_toArray(parts), text: text, randomHex: $schelmHex, control: control${fixture ? ', operationId: "fixture", nextSequence: nextSequence, observe: observe' : ''} })\n      .then(function(result) { if (!control.abandoned) callback(result.ok ? __Scheduler_succeed($schelmResult(result)) : __Scheduler_fail($schelmFailure(result))); })\n      .catch(function(error) { if (!control.abandoned) callback(__Scheduler_fail($schelmFailure({ phase: "validating", error: { kind: "unknown-failure", code: "", message: String(error).slice(0, 1024) }, residue: [] }))); });\n    return function() { control.abandoned = true; };\n  });\n});\n`;
function output(fixture) {
  const tx = fixture ? body : productionBody;
  return header(fixture) + tx + ops + (fixture ? fixtureOps : "") + elmAdapter(fixture);
}
const targets = [
  ["src/Elm/Kernel/SchelmAtomicText.js", output(false)],
  ["fixtures/package/src/Elm/Kernel/SchelmAtomicTextFixture.js", output(true)]
];
let bad = false;
for (const [rel, content] of targets) {
  const dest = path.join(root, rel);
  if (process.argv.includes("--check")) {
    if (!fs.existsSync(dest) || fs.readFileSync(dest, "utf8") !== content) { console.error(`stale generated kernel: ${rel}`); bad = true; }
  } else { fs.mkdirSync(path.dirname(dest), { recursive: true }); fs.writeFileSync(dest, content); }
}
if (bad) process.exit(1);
console.log(`${process.argv.includes("--check") ? "checked" : "assembled"} kernels ${hash}`);
