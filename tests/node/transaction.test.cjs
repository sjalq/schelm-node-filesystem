"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const crypto = require("node:crypto");
const { schelmAtomicTextTransaction: run } = require("../../kernel-src/atomic-text-transaction.js");
const { makeFakeFs } = require("../support/fake-fs.cjs");
const fixed = () => "0123456789abcdef0123456789abcdef";
function opts(fake, text = "new") { return { ops: fake.ops, root: "/root", segments: ["session", "state.json"], text, randomHex: fixed, observe: async () => {} }; }

test("durable replacement has exact syscall shape", async () => {
  const fake = makeFakeFs({ files: [["/root/session/state.json", Buffer.from("old")]] });
  const out = await run(opts(fake));
  assert.equal(out.ok, true); assert.equal(out.durability, "durable");
  assert.equal(fake.files.get("/root/session/state.json").toString(), "new");
  assert.deepEqual(fake.calls.map(x => x.name), ["lstat","lstat","open","write","fileSync","tempClose","rename","open","dirSync","dirClose"]);
});

test("short writes loop without losing bytes", async () => {
  const fake = makeFakeFs({ write: () => ({ short: 1 }) });
  const out = await run(opts(fake, "abcd"));
  assert.equal(out.ok, true); assert.equal(fake.files.get("/root/session/state.json").toString(), "abcd");
  assert.equal(fake.calls.filter(x => x.name === "write").length, 4);
});

test("parent sync failure reports acknowledged commit with unknown durability", async () => {
  const fake = makeFakeFs({ dirSync: { error: "EIO" } });
  const out = await run(opts(fake));
  assert.equal(out.ok, true); assert.equal(out.durability, "unknown"); assert.equal(out.stage, "syncing-parent");
  assert.equal(fake.files.get("/root/session/state.json").toString(), "new");
});

test("pre-rename failures keep old destination and clean temp", async () => {
  for (const point of ["write", "fileSync", "tempClose", "rename"]) {
    const fake = makeFakeFs({ files: [["/root/session/state.json", Buffer.from("old")]], [point]: { error: "EIO" } });
    const out = await run(opts(fake));
    assert.equal(out.ok, false, point); assert.equal(fake.files.get("/root/session/state.json").toString(), "old", point);
    assert.equal([...fake.files.keys()].some(p => p.includes(".schelm-")), false, point);
  }
});

test("invalid surrogates fail before filesystem calls", async () => {
  for (const text of ["\ud800", "\udc00", "x\ud800y"]) {
    const fake = makeFakeFs(); const out = await run(opts(fake, text));
    assert.equal(out.ok, false); assert.equal(out.phase, "validating"); assert.equal(fake.calls.length, 0);
  }
});

test("generated command traces preserve old-or-complete-new", async () => {
  let seed = 0x5c43e1;
  const next = () => (seed = (seed * 1664525 + 1013904223) >>> 0);
  const points = [null,"open","write","fileSync","tempClose","rename","dirSync","dirClose"];
  for (let i = 0; i < 2000; i++) {
    const point = points[next() % points.length];
    const payload = crypto.createHash("sha256").update(String(next())).digest("hex").slice(0, 1 + next() % 64);
    const plan = { files: [["/root/session/state.json", Buffer.from("old")]] };
    if (point) plan[point] = { error: "EIO" };
    if (next() % 4 === 0) plan.write = () => ({ short: 1 + next() % Math.max(1, Math.min(8, payload.length)) });
    const fake = makeFakeFs(plan); const out = await run(opts(fake, payload));
    const actual = fake.files.get("/root/session/state.json").toString();
    assert.ok(actual === "old" || actual === payload, `seed trace ${i} ${point}: ${actual}`);
    if (out.ok && out.durability === "durable") assert.equal(actual, payload);
  }
});
