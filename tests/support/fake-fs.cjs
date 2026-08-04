"use strict";
const path = require("node:path");
function error(code, message = code) { return Object.assign(new Error(message), { code }); }
function makeFakeFs(plan = {}) {
  const calls = [];
  const files = new Map(plan.files || []);
  const dirs = new Set(plan.dirs || ["/root", "/root/session"]);
  const symlinks = new Set(plan.symlinks || []);
  let fd = 0;
  const hit = async (name, facts = {}) => {
    calls.push({ name, ...facts });
    const action = plan[name];
    if (typeof action === "function") return action(facts, calls.length);
    if (action && action.error) throw error(action.error);
    return action;
  };
  const stat = (p) => ({ isSymbolicLink: () => symlinks.has(p), isDirectory: () => dirs.has(p) });
  return {
    calls, files, dirs, symlinks,
    ops: {
      join: path.posix.join, dirname: path.posix.dirname, basename: path.posix.basename,
      async lstat(p) { await hit("lstat", { path: p }); if (symlinks.has(p) || dirs.has(p) || files.has(p)) return stat(p); throw error("ENOENT"); },
      async open(p, flags) {
        await hit("open", { path: p, flags });
        if (flags === "wx" && files.has(p)) throw error("EEXIST");
        if (flags === "r" && !dirs.has(p)) throw error("ENOENT");
        if (flags === "wx") files.set(p, Buffer.alloc(0));
        const id = ++fd;
        return {
          async write(buffer, offset, length, position) {
            const chosen = await hit("write", { path: p, offset, length, position, id });
            const n = chosen && Number.isInteger(chosen.short) ? chosen.short : length;
            const old = files.get(p) || Buffer.alloc(0);
            const size = Math.max(old.length, position + n);
            const next = Buffer.alloc(size); old.copy(next); buffer.copy(next, position, offset, offset + n); files.set(p, next);
            return { bytesWritten: n };
          },
          async sync() { await hit(flags === "r" ? "dirSync" : "fileSync", { path: p, id }); },
          async close() { await hit(flags === "r" ? "dirClose" : "tempClose", { path: p, id }); }
        };
      },
      async rename(a, b) { await hit("rename", { from: a, to: b }); const value = files.get(a); if (!value) throw error("ENOENT"); files.set(b, value); files.delete(a); },
      async unlink(p) { await hit("unlink", { path: p }); if (!files.delete(p)) throw error("ENOENT"); }
    }
  };
}
module.exports = { makeFakeFs, error };
