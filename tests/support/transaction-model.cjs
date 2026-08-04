"use strict";

const phases = ["open", "write", "fileSync", "tempClose", "rename", "parentOpen", "dirSync", "dirClose"];
function expected(command) {
  const fail = command.fail;
  const renameAck = !fail || phases.indexOf(fail) > phases.indexOf("rename");
  const content = renameAck ? "new" : "old";
  if (!fail) return { ok: true, durability: "durable", content };
  if (fail === "parentOpen") return { ok: true, durability: "unknown", stage: "opening-parent", content };
  if (fail === "dirSync") return { ok: true, durability: "unknown", stage: "syncing-parent", content };
  if (fail === "dirClose") return { ok: true, durability: "durable", content, parentResidue: true };
  return { ok: false, content };
}
function shrink(command) {
  const candidates = [];
  if (command.payload.length > 1) candidates.push({ ...command, payload: command.payload.slice(0, Math.ceil(command.payload.length / 2)) });
  if (command.shortWrite && command.shortWrite > 1) candidates.push({ ...command, shortWrite: 1 });
  if (command.fail) candidates.push({ ...command, payload: "x" });
  return candidates;
}
module.exports = { expected, shrink, phases };
