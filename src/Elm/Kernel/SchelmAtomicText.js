/* generated; canonical-sha256 e2c9ae5f4f345d836df90dfc2fc02757df5305efb10e179f53521cab358ebe04; fixture=false */
/*
import Elm.Kernel.List exposing (fromArray, toArray)
import Elm.Kernel.Scheduler exposing (binding, fail, succeed)
*/
var $fs = require("node:fs");
var $path = require("node:path");
var $crypto = require("node:crypto");
async function schelmAtomicTextTransaction(options) {
  const { ops, root, segments, text, randomHex } = options;
  const control = options.control || { abandoned: false };
  const residue = new Set();
  let tempHandle = null;
  let parentHandle = null;
  let tempPath = null;
  let renameAcknowledged = false;
  let phase = "validating";

  const errorFact = (value) => {
    const source = value && typeof value === "object" ? value : {};
    const code = typeof source.code === "string" ? source.code : "";
    const message = typeof source.message === "string" ? source.message.slice(0, 1024) : String(value).slice(0, 1024);
    const kinds = {
      ENOENT: "not-found", EACCES: "permission-denied", EPERM: "permission-denied",
      ENOTDIR: "not-directory", EISDIR: "is-directory", ELOOP: "symlink-rejected",
      EINVAL: "invalid-input", ENAMETOOLONG: "path-too-long", EMFILE: "too-many-open-files",
      ENFILE: "too-many-open-files", EIO: "io-failure", ENOSYS: "unsupported", ENOTSUP: "unsupported"
    };
    return { kind: kinds[code] || "unknown-failure", code, message };
  };

  const validate = () => {
    if (typeof root !== "string" || !root.startsWith("/") || root.includes("\0")) throw Object.assign(new Error("invalid cooperative root"), { code: "EINVAL" });
    if (!Array.isArray(segments) || segments.length === 0) throw Object.assign(new Error("empty relative file"), { code: "EINVAL" });
    for (const part of segments) {
      if (typeof part !== "string" || !part || part === "." || part === ".." || part.includes("\0") || part.includes("/") || part.includes("\\")) {
        throw Object.assign(new Error("invalid relative file segment"), { code: "EINVAL" });
      }
    }
    if (typeof text !== "string") throw Object.assign(new Error("text must be a string"), { code: "EINVAL" });
    for (let i = 0; i < text.length; i += 1) {
      const c = text.charCodeAt(i);
      if (c >= 0xd800 && c <= 0xdbff) {
        const next = text.charCodeAt(i + 1);
        if (!(next >= 0xdc00 && next <= 0xdfff)) throw Object.assign(new Error("unpaired UTF-16 high surrogate"), { code: "EINVAL" });
        i += 1;
      } else if (c >= 0xdc00 && c <= 0xdfff) {
        throw Object.assign(new Error("unpaired UTF-16 low surrogate"), { code: "EINVAL" });
      }
    }
  };

  const cleanupBeforeRename = async () => {
    if (tempHandle) {
      residue.add("temp-fd");
      try { await tempHandle.close(); residue.delete("temp-fd"); } catch (_) {}
      tempHandle = null;
    }
    if (tempPath && residue.has("temp")) {
      try {
        await ops.unlink(tempPath); residue.delete("temp");
      } catch (_) {}
    }
  };

  try {
    validate();
    const destination = ops.join(root, ...segments);
    const parent = ops.dirname(destination);
    phase = "checking-parent";
    let cursor = root;
    for (const part of segments.slice(0, -1)) {
      cursor = ops.join(cursor, part);
      const stat = await ops.lstat(cursor);
      if (stat.isSymbolicLink()) throw Object.assign(new Error("symbolic-link parent rejected"), { code: "ELOOP" });
      if (!stat.isDirectory()) throw Object.assign(new Error("parent is not a directory"), { code: "ENOTDIR" });
    }
    try {
      const destStat = await ops.lstat(destination);
      if (destStat.isSymbolicLink()) throw Object.assign(new Error("symbolic-link destination rejected"), { code: "ELOOP" });
      if (destStat.isDirectory()) throw Object.assign(new Error("destination is a directory"), { code: "EISDIR" });
    } catch (error) {
      if (!error || error.code !== "ENOENT") throw error;
    }

    const bytes = Buffer.from(text, "utf8");
    phase = "opening-temp";
    for (let attempt = 0; attempt < 16; attempt += 1) {
      tempPath = ops.join(parent, `.${ops.basename(destination)}.schelm-${randomHex()}`);
      residue.add("temp");
      try {
        tempHandle = await ops.open(tempPath, "wx", 0o666);
        residue.add("temp-fd");
        break;
      } catch (error) {
        if (error && error.code === "EEXIST") {
          residue.delete("temp");
          tempPath = null;
          if (attempt < 15) continue;
        }
        throw error;
      }
    }
    if (!tempHandle) throw Object.assign(new Error("temporary-name collision limit reached"), { code: "EEXIST" });

    phase = "writing-temp";
    let offset = 0;
    while (offset < bytes.length) {
      const result = await tempHandle.write(bytes, offset, bytes.length - offset, offset);
      const written = result && Number(result.bytesWritten);
      if (!Number.isInteger(written) || written <= 0) throw Object.assign(new Error("write made no progress"), { code: "EIO" });
      offset += written;
    }

    phase = "syncing-temp";
    await tempHandle.sync();
    phase = "closing-temp";
    await tempHandle.close(); tempHandle = null; residue.delete("temp-fd");

    phase = "renaming";
    await ops.rename(tempPath, destination);
    renameAcknowledged = true; residue.delete("temp");

    phase = "opening-parent";
    try {
      parentHandle = await ops.open(parent, "r"); residue.add("parent-fd");
    } catch (error) {
      return { ok: true, durability: "unknown", stage: "opening-parent", error: errorFact(error), residue: Array.from(residue) };
    }

    phase = "syncing-parent";
    try {
      await parentHandle.sync();
    } catch (error) {
      try { await parentHandle.close(); residue.delete("parent-fd"); } catch (_) {}
      return { ok: true, durability: "unknown", stage: "syncing-parent", error: errorFact(error), residue: Array.from(residue) };
    }

    phase = "closing-parent";
    try {
      await parentHandle.close(); residue.delete("parent-fd");
    } catch (_) {
      return { ok: true, durability: "durable", stage: "", error: errorFact(null), residue: Array.from(residue) };
    }
    return { ok: true, durability: "durable", stage: "", error: errorFact(null), residue: [] };
  } catch (error) {
    if (!renameAcknowledged) await cleanupBeforeRename();
    return { ok: false, phase, error: errorFact(error), residue: Array.from(residue) };
  }
}

function $schelmOps() { return {
  join: $path.join, dirname: $path.dirname, basename: $path.basename,
  lstat: function(p) { return $fs.promises.lstat(p); },
  open: function(p, flags, mode) { return $fs.promises.open(p, flags, mode); },
  rename: function(a, b) { return $fs.promises.rename(a, b); },
  unlink: function(p) { return $fs.promises.unlink(p); }
}; }
function $schelmHex() { return $crypto.randomBytes(16).toString("hex"); }

function $schelmError(error) { return { __$kind: error.kind, __$code: error.code, __$message: error.message }; }
function $schelmResult(result) { return { __$durability: result.durability, __$stage: result.stage, __$error: $schelmError(result.error), __$residue: __List_fromArray(result.residue) }; }
function $schelmFailure(result) { return { __$phase: result.phase, __$error: $schelmError(result.error), __$residue: __List_fromArray(result.residue) }; }
var _SchelmAtomicText_replace = F3(function(root, parts, text) {
  return __Scheduler_binding(function(callback) {
    var control = { abandoned: false };
    schelmAtomicTextTransaction({ ops: $schelmOps(), root: root, segments: __List_toArray(parts), text: text, randomHex: $schelmHex, control: control })
      .then(function(result) { if (!control.abandoned) callback(result.ok ? __Scheduler_succeed($schelmResult(result)) : __Scheduler_fail($schelmFailure(result))); })
      .catch(function(error) { if (!control.abandoned) callback(__Scheduler_fail($schelmFailure({ phase: "validating", error: { kind: "unknown-failure", code: "", message: String(error).slice(0, 1024) }, residue: [] }))); });
    return function() { control.abandoned = true; };
  });
});
