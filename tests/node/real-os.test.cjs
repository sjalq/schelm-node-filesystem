"use strict";
const test = require("node:test");
const assert = require("node:assert/strict");
const fs = require("node:fs");
const fsp = fs.promises;
const os = require("node:os");
const path = require("node:path");
const crypto = require("node:crypto");
const { schelmAtomicTextTransaction: run } = require("../../kernel-src/atomic-text-transaction.js");
const ops = { join:path.join, dirname:path.dirname, basename:path.basename, lstat:fsp.lstat, open:fsp.open, rename:fsp.rename, unlink:fsp.unlink };
const hex = () => crypto.randomBytes(16).toString("hex");
test("real Node 24 filesystem replacement is complete", async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), "schelm-fs-"));
  try { await fsp.mkdir(path.join(root,"s")); await fsp.writeFile(path.join(root,"s","x"),"old");
    const out = await run({ ops, root, segments:["s","x"], text:"hello 🌍\0", randomHex:hex, observe:async()=>{} });
    assert.equal(out.ok,true); assert.equal(out.durability,"durable"); assert.equal(await fsp.readFile(path.join(root,"s","x"),"utf8"),"hello 🌍\0");
    assert.deepEqual((await fsp.readdir(path.join(root,"s"))).sort(),["x"]);
  } finally { await fsp.rm(root,{recursive:true,force:true}); }
});
test("symlink parent is rejected at check time", async () => {
  const root = await fsp.mkdtemp(path.join(os.tmpdir(), "schelm-fs-"));
  try { await fsp.mkdir(path.join(root,"real")); await fsp.symlink(path.join(root,"real"),path.join(root,"link"));
    const out = await run({ ops, root, segments:["link","x"], text:"x", randomHex:hex, observe:async()=>{} });
    assert.equal(out.ok,false); assert.equal(out.error.kind,"symlink-rejected");
  } finally { await fsp.rm(root,{recursive:true,force:true}); }
});
