# 01 — `schelm-node-filesystem` v1 design

Status: first-turn design only; no implementation is authorized by this artifact.

## 1. Goal and boundary

V1 is a small Node-only Elm kernel package for **bounded persistence**, not a general
filesystem binding. It provides pure path construction, explicitly acquired and
scoped root capabilities, bounded whole-file reads, durable append, directory
creation, metadata needed for recovery, and same-directory atomic replacement.
The first consumer is one agent-harness persistence slice.

Non-goals for v1: streams, watchers, links, ownership/mode changes, recursive
remove/copy, current/home/temp directory discovery, open file handles, arbitrary
absolute-path operations, JSON policy, retries, session naming, title/GC rules,
and deciding whether an error is recoverable.

Target runtime is Node.js on the compiler fork based on Elm 0.19.2 commit
`48befde1`; the fork commit `76bbe444` only authorizes packages owned by `sjalq`
as kernel packages. Applications still cannot contain/import `Elm.Kernel.*`.

## 2. Proposed public modules and API

Names may be refined by the two adversarial reviews, but semantic authority must
not move.

```elm
module Schelm.Node.FileSystem.Path exposing
    ( RelativePath, Segment, PathError(..)
    , empty, segment, fromSegments, fromString
    , child, append, segments, toString
    )

type RelativePath                 -- opaque, canonical, never absolute
type Segment                      -- opaque, exactly one non-special component
type PathError
    = EmptySegment | DotSegment | ParentSegment | ContainsSeparator
    | AbsolutePath | ContainsNul | InvalidPlatformPath

empty : RelativePath
segment : String -> Result PathError Segment
fromSegments : List String -> Result PathError RelativePath
fromString : String -> Result PathError RelativePath
child : Segment -> RelativePath -> RelativePath
append : RelativePath -> RelativePath -> RelativePath
segments : RelativePath -> List String
toString : RelativePath -> String -- `/`-separated diagnostic/serialization form
```

`fromString` accepts `/` as the package wire separator on every platform. It
rejects empty interior components, `.`, `..`, NUL, leading `/`, Windows drive or
UNC roots, and both `/` and `\\` inside a component. It does not normalize bad
input into good input. `empty` denotes the root itself. Kernel JS receives a
list of validated components, not a caller-supplied host path string.

```elm
module Schelm.Node.FileSystem exposing
    ( Root, RootSpec, RootMode(..), authorize
    , Error, ErrorKind(..), errorKind, errorPath, errorCode, errorMessage
    , EntryKind(..), Metadata
    , ReadLimit, readLimit, ReadLimitError(..)
    , readUtf8, appendUtf8, replaceUtf8Atomically
    , ensureDirectory, metadata, listDirectory
    )

type Root                       -- opaque scoped capability
type alias RootSpec = { absolutePath : String, mode : RootMode }
type RootMode = ReadOnly | ReadWrite

authorize : RootSpec -> Task Error Root

type Error                      -- opaque; no raw JS exception escapes
type ErrorKind
    = NotFound | AlreadyExists | PermissionDenied | NotDirectory | IsDirectory
    | DirectoryNotEmpty | TooManyOpenFiles | PathTooLong | InvalidInput
    | SymlinkRejected | OutsideRoot | LimitExceeded | Interrupted
    | IoFailure | Unsupported | UnknownFailure

errorKind : Error -> ErrorKind
errorPath : Error -> RelativePath
errorCode : Error -> Maybe String
errorMessage : Error -> String

type ReadLimit                  -- positive opaque byte count
readLimit : Int -> Result ReadLimitError ReadLimit
type ReadLimitError = NonPositiveLimit

type EntryKind = File | Directory | SymbolicLink | Other
type alias Metadata = { kind : EntryKind, byteSize : Int }

readUtf8 : Root -> ReadLimit -> RelativePath -> Task Error String
appendUtf8 : Root -> RelativePath -> String -> Task Error ()
replaceUtf8Atomically : Root -> RelativePath -> String -> Task Error ()
ensureDirectory : Root -> RelativePath -> Task Error ()
metadata : Root -> RelativePath -> Task Error Metadata
listDirectory : Root -> ReadLimit -> RelativePath -> Task Error (List { name : Segment, kind : EntryKind })
```

`ReadOnly` has no write effect at runtime. Elm cannot index a capability's mode
at the type level without complicating bootstrap and storage; therefore mode is
an invariant checked in the sole kernel dispatcher. A later review should decide
whether phantom `Root read write` repays that complexity. All reads and listings
require caller-provided limits. `listDirectory`'s limit is maximum entry count;
results beyond it fail, rather than silently truncate. UTF-8 decoding is strict:
malformed bytes fail with `InvalidInput`. Binary and streaming APIs wait for a
real consumer.

### Capability minting caveat

`authorize` is explicit rather than ambient, and all operations require its
opaque result, so authority can be passed narrowly and roots cannot be confused.
However, ordinary Elm package APIs cannot distinguish a trusted bootstrap module
from another module in the same application. Any application code can call
`authorize` if it imports this module. V1 capabilities therefore prevent
accidental authority propagation and root confusion; they are **not a security
sandbox against malicious code already linked into the Elm application**. The
harness must call `authorize` only in its composition root and pass distinct
`sessionsRoot`/`artRoot` values to owners. Solving mint authority would require a
compiler/runtime bootstrap facility analogous to Gren `Init.Task`; that is an
unresolved program-level decision, not something kernel JS should fake.

## 3. MISI design

1. **No ambient operation:** every effect requires `Root`; no operation accepts
   an absolute path.
2. **Bad relative paths are unrepresentable:** `RelativePath` and `Segment` are
   opaque. Traversal, absolute roots, separators, dot components, and NUL fail at
   construction.
3. **Roots do not alias by type accidentally:** `Root` contains an unforgeable
   kernel registry id plus mode; JS never trusts a root path sent on each call.
4. **Bounded input:** reading and listing without a positive explicit limit is
   unrepresentable. The kernel checks size/count while doing work, not afterward.
5. **Write permission is a fact on the capability:** every write enters one
   shared permission gate before filesystem access.
6. **Atomic replacement has one terminal result:** success means rename
   completed; failure means the old destination remains or, after rename, the
   new destination is installed and the result reports the durability failure.
   The latter must be represented distinctly in implementation (likely
   `IoFailure` with operation detail), never reported as “unchanged.”
7. **Settled temporary resources are absent:** temp file descriptor/name are
   held only by an internal live transaction. Completion/cancellation consumes
   the transaction; no public handle exists.
8. **Errors are data:** all Node throws/callback errors are caught and mapped;
   no JavaScript exception is encoded as success.
9. **No policy in JS:** JSON encoding, retries, recovery, filename conventions,
   and session behavior remain Elm.

A `Root` registry is necessary because an Elm value cannot safely contain an OS
capability. Registry entries are `{ canonicalRoot, mode }`, keyed by a generated
integer. Unknown ids fail closed. Registry creation and lookup are the only
stateful authority mechanism.

## 4. MITI state machines and ownership

### Root authorization

```text
Requested absolute string + mode
  -> validate absolute/no-NUL
  -> realpath existing directory
  -> open/inspect as directory
  -> Registered(id, canonicalRoot, mode)
  -> Root value
```

Any failure produces no registry entry. V1 roots live for the Elm process;
there is no public revoke operation because the first slice has process-lifetime
roots and adding a fake lifecycle would add invalid states. If short-lived roots
appear, v2 must add explicit `ActiveRoot -> Revoked` semantics and registry GC.

### Ordinary operation

```text
Root id + validated segments
  -> registry lookup
  -> mode gate
  -> containment walk
  -> exactly one fs verb
  -> Succeeded | Failed typed Error
```

Containment walk starts at the registered canonical root and rejects symbolic
links in every existing component (`lstat`). For a create target, its existing
parent chain is checked. This prevents traversal and ordinary symlink escape.
Node's portable API has no `openat`/`O_NOFOLLOW` walk, so a hostile local process
can race `lstat` and the subsequent operation (TOCTOU). V1 explicitly does not
claim protection from a concurrent hostile OS user; claiming otherwise would be
false security. Tests still exercise symlink rejection and root containment.

### Atomic replacement

```text
Absent
  -> TempAllocated(same directory, exclusive random name, fd)
  -> Writing(offset increases; partial writes loop)
  -> SyncingTemp
  -> ClosingTemp
  -> Renaming(temp, destination)
  -> SyncingParent (where platform supports it)
  -> Absent + Success
```

At every pre-rename failure/cancellation: close once if open, unlink temp once,
then fail. At/after rename: never unlink destination; attempt parent-directory
sync and report its failure accurately. Callback settlement is guarded by the
state constructor, not a loose boolean. Cancellation is idempotent and cannot
settle the Elm task twice. Temp files are same-directory to preserve rename
atomicity. No overwrite fallback (copy/delete) is permitted. Windows unsupported
parent-directory sync is recorded as a documented platform durability level,
not silently emulated.

### Append

One package call maps to one Node append request with UTF-8 bytes. This gives
process-local call atomicity but does not promise crash durability or arbitrary
multi-process record atomicity. The harness journal continues to append one
already-serialized JSONL envelope per call. A future `appendDurably` may add
open/write/fsync only if measured need justifies it.

## 5. DRY authorities

- Pure Elm `Path` constructors are the sole lexical path-validation authority.
  JS receives components and only rechecks constitutional invariants as a
  security backstop; it does not normalize.
- One Elm `ErrorKind` mapping table is the product-facing classification. Kernel
  JS returns bounded facts `{ code, syscall, message, path }`; an unavoidable JS
  backstop maps non-error throws to a stable unknown fact, not product policy.
- One kernel helper owns registry lookup, mode check, containment walk, error
  capture, and callback settlement for every verb.
- One atomic-replace implementation serves all consumers; callers do not compose
  temp/write/rename themselves.
- Harness `SessionLog` remains the sole journal wire-format authority and
  session policy remains in harness Elm. This package handles bytes only.
- During integration the old JS and new package coexist only in differential
  tests. After cutover of the selected slice, its old write implementation is
  removed rather than retained as fallback.

## 6. Exact comparison with Gren 6.1.3

Reference inspected: embedded `gren-lang/node` 6.1.3 sources in
`/home/s.dormehl/git/gren-compiler/gren_packages/gren_lang_node__6_1_3.pkg.gz`,
modules `FileSystem`, `FileSystem.Path`, `FileSystem.FileHandle`,
`Gren.Kernel.FileSystem`, and `Gren.Kernel.FilePath`.

| Gren 6.1.3 | Schelm v1 decision |
|---|---|
| `Permission`, obtained by `initialize : Init.Task Permission` | Keep explicit authority, but scope it to opaque `Root` + mode. Elm lacks Gren's `Init.Task`; `authorize` caveat is documented. |
| Public `Path` is a record `{ root, directory : Array String, filename, extension }` | Opaque relative path made of validated segments. No public root/filename-extension decomposition and no representable traversal. |
| POSIX and Win32 parse/render; `append`, `prepend`, `join`, `parentPath` | One platform-neutral `/` wire parser and segment operations. Host rendering stays kernel-private. |
| Full unbounded FS: metadata/access/chown/times/move/realPath/read/append/write/truncate/remove/list/mkdir/temp/links/watch/special paths | Deliberately only bounded read/list, append, atomic replace, mkdir, and minimal metadata. No ambient special paths or destructive/link APIs. |
| `readFile : Permission -> Path -> Task Error Bytes` and `listDirectory` unbounded | Explicit positive limits; v1 UTF-8 only, based on harness need. |
| `writeFile` overwrites directly | Add same-directory durable atomic replacement as the persistence primitive. |
| `Error` exposes path, raw code, message plus code predicates | Opaque error exposes stable `ErrorKind`, optional raw code, safe message, and relative path. Classification remains Elm-owned. |
| `FileHandle readAccess writeAccess` phantom permissions; close returns `{}` but stale handles remain representable | Exclude public handles in v1. Atomic transaction owns private fd and consumes it internally, so use-after-close is absent from public API. |
| Streams and watch subscriptions | Excluded until an actual harness streaming/watch slice exists. |
| Kernel generally passes parsed path to Node `fs` callbacks | Registry-rooted component walk adds scoped authority and symlink rejection. |

Thus this is “close to Gren” in typed permission, typed errors, Tasks, and pure
paths, but intentionally narrower and stricter where the program constitution
requires bounded work, scoped authority, atomic persistence, and MISI lifecycle.

## 7. Minimal kernel JavaScript boundary

Planned kernel files are only `Elm/Kernel/SchelmFileSystem.js` (effectful verbs,
registry, Node error facts, transaction cleanup) and, only if profiling proves
necessary, a tiny path-render helper in the same file. Pure path parsing and all
policy stay in normal Elm.

The JS verbs should be approximately:

```text
authorizeRoot(absolute, mode)
readUtf8(rootId, segments, maxBytes)
appendUtf8(rootId, segments, text)
replaceUtf8Atomically(rootId, segments, text)
ensureDirectory(rootId, segments)
metadata(rootId, segments)
listDirectory(rootId, segments, maxEntries)
```

No generic stringly RPC, arbitrary operation name, retry loop, JSON parser,
session concept, recursive delete, cwd lookup, or “run any fs method” escape
hatch is allowed. Every exported kernel value gets an explicit Elm annotation.
The generated package must execute in debug and `--optimize` builds.

## 8. First harness vertical slice

The first slice is **atomic `meta.json` replacement**, not journal append.
Current `elm-pkg-js/sessions-store.js` has a sole `patchMeta` host write path but
uses direct `fs.writeFileSync`, so a crash can leave corrupt/partial metadata;
recovery then reseeds from `events.jsonl`. Keep all patch/title/reseed decisions
where they are in harness Elm during the integration refactor, but execute the
final encoded bytes through:

```elm
FileSystem.replaceUtf8Atomically sessionsRoot
    (Path.fromSegments [ sessionId, "meta.json" ])
    encodedMeta
```

Acceptance:

1. harness composition root authorizes the sessions directory once and passes
   only `sessionsRoot` to session persistence;
2. no package API knows `ses_`, `meta.json`, JSON, sticky titles, or reseeding;
3. the chosen `meta.json` write has one new authority and old direct-write code
   is removed after differential tests;
4. failure injection before rename preserves old valid metadata and leaves no
   temp file; after rename yields complete new metadata;
5. cold attach and catalog recovery behavior is unchanged;
6. full harness Elm/GUI/host/format suites pass on the evidence-only branch
   `schelm/01-node-filesystem-integration`; it is not deployed.

If harness architecture makes moving `patchMeta` policy into Elm too large for a
first slice, the bounded fallback slice is daemon-state atomic replacement,
provided it still crosses Elm -> package -> kernel in production. A JS wrapper
calling another JS wrapper is not an integration and does not count.

## 9. Complexity budgets

Let `p` be path segment count, `n` file bytes, `e` directory entries, and `w`
bytes appended/replaced.

| Operation | Time | Extra memory | Bound/invariant |
|---|---:|---:|---|
| path construction | O(p + input chars) | O(p + chars) | cold, explicit input |
| capability lookup | O(log r) with Elm-facing id / O(1) JS `Map` | O(1) | `r` roots, normally <10 |
| containment walk | O(p) syscalls | O(p) | independent of session/history count |
| read UTF-8 | O(n) | O(n) | fails above `ReadLimit`; no repeated accumulation |
| append | O(w) | O(w) encoding | one delta only; never rereads journal |
| atomic replace | O(w) | O(w) due to Elm/JS string plus bounded Node buffer | same-directory temp; no historical scan |
| list | O(e) | O(e) | fails at explicit entry limit |
| metadata/mkdir | O(p) containment + OS verb | O(p) | no recursive tree walk |

At item 1,000, session 200, and stream chunk 10,000, an append costs only the new
serialized line plus its path depth. Atomic metadata replacement costs only the
current metadata document. No operation scans sessions or accumulated journal
bytes. Implementation review must grep its diff for `++ [`, accumulator
`List.member`, repeated full-buffer sends, and per-operation root-list scans.

A future binary streaming API is required before files whose legitimate size
makes O(n) memory unacceptable; v1's explicit limits make that unsupported state
visible rather than accidental.

## 10. Proposed non-trivial property/model tests

These are candidates for the later mandatory `06-property-test-plan.md`; they
are not satisfied by examples alone.

### Pure path properties

- Generate hostile Unicode/component strings (NUL, both separators, dot/dotdot,
  drive prefixes, UNC, repeated separators). Accepted paths round-trip
  `segments -> fromSegments`, contain no forbidden component, and rendering can
  never become absolute.
- `append` is associative and `empty` is its identity for generated valid paths.
- Joining a valid child cannot alter/drop the root prefix in the reference model.
- Differential valid-path rendering against Node `path.resolve(root, ...parts)`
  always remains under `root + separator`; include case and separator fixtures
  for POSIX and Windows CI where available.

### Capability/authorization model

Use a pure model `{ roots : Dict Id { mode, tree } }` and generate sequences of
`authorize/read/append/replace/mkdir/stat/list`, invalid ids, wrong modes,
missing parents, symlinks, and limit changes. Runtime results and model outcomes
must agree on authorization and terminal tree state. Negative fixtures prove a
sessions capability cannot address an art-root file and read-only cannot write.

### Atomic replacement state-machine properties

Inject failure/cancellation after every transition and after arbitrary partial
write lengths, including zero-byte writes. Assert:

- exactly one callback result;
- no live fd and no temp entry after settlement;
- before rename, destination equals old bytes;
- after rename, destination equals all new bytes, never a prefix/mix;
- cancellation repeated at every state is idempotent;
- generated colliding temp names retry within a fixed bound then fail cleanly;
- parent-sync failure is distinguishable from pre-rename failure.

Run the same generated command trace against an in-memory reference transaction
and real temp directories. Kill a child Node process at transition hooks and
inspect disk state from the parent to test crash boundaries.

### Bounded I/O and errors

- Generate files around every limit (`limit-1`, `limit`, `limit+1`) and mutate
  size between stat/read; the implementation must never return over-limit data.
- Inject short reads/writes and callback errors; returned bytes/string or final
  file exactly match the model.
- Malformed UTF-8 never becomes replacement-character success.
- Generated Node error shapes, non-`Error` throws, and overlong messages always
  map to a finite Elm `Error`; debug and optimize classifications agree.
- Directory listings over limit fail independent of enumeration order.

### Compatibility and differential tests

- Run every fixture as a real Elm worker in debug and `--optimize`, cold and warm
  isolated Schelm caches.
- Compare old harness direct `meta.json` outcomes with new package outcomes for
  successful traces; for injected crashes, require the new stronger invariant
  (old-or-new complete JSON).
- Old host/new package compatibility: run package-generated JS with the oldest
  supported Node host/runtime and protocol glue. New host/old package is not a
  wire promise unless integration introduces a versioned boundary.
- Deterministically build the private package archive twice and compare file
  list and SHA-256; verify no credentials/absolute build paths are present.

## 11. Unresolved design questions for hostile review

1. Should the compiler/runtime gain a Gren-like one-shot bootstrap facility so
   `Root` minting is genuinely restricted, or is composition-root discipline an
   accepted v1 limit?
2. Do phantom mode parameters (`Root ReadOnly`, `Root ReadWrite`) improve MISI
   enough to justify API complexity, especially for storing heterogeneous roots?
3. Is strict UTF-8 sufficient for the first package, or should v1 use `Bytes`
   despite the first harness slice being text-only?
4. Which Node/OS matrix is normative, and is parent-directory `fsync` required
   for “durable” success on each supported platform?
5. Is symlink rejection (with documented local-process TOCTOU) acceptable, or
   must the package use a native `openat` helper before claiming scoped roots?
6. Can `patchMeta` policy be moved cleanly to harness Elm for the first slice,
   or should daemon state be selected to avoid expanding the migration?
7. Must append be crash-durable (`fsync`) for journal semantics, or does current
   process-level append parity remain the v1 contract?
8. What exact maximums should harness choose for metadata bytes, journal reads,
   and directory entry counts? The package supplies bounds but must not own them.

## 12. Evidence inspected

- package constitution: parent `CLAUDE.md` and `docs/PROGRAM.md`;
- Gren compiler checkout and embedded `gren-lang/node` 6.1.3 package sources;
- Elm fork `SCHELM.md`, `NOTICE`, and commit `76bbe444` diff;
- agent-harness `elm-pkg-js/sessions-store.js`, especially `ensureSession`,
  `appendEvent`, `patchMeta`, and catalog recovery paths.

No source implementation is included in this commit.
