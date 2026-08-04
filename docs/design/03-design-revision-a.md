# 03 — Design revision A

Status: response to `02-adversarial-review-a.md`; design only. This revision
**supersedes conflicting claims and API in `01-design.md`**. No source
implementation is authorized yet.

## 1. Decisive narrowing

V1 now implements exactly one reusable primitive for one harness slice:
**cooperatively rooted, same-directory atomic UTF-8 file replacement**.

V1 does not include read, append, list, metadata, mkdir, streams, handles,
watchers, links, removal, or discovery. Removing bounded read/list avoids false
work bounds; removing append avoids promising ordering/durability before the
journal migration has a designed owner. Parent directories and the destination
may exist; V1 never creates directories.

The first harness slice remains `meta.json` replacement. The package receives a
complete serialized document; JSON patching, ordering, session policy, retries,
and per-session scheduling remain harness Elm.

## 2. Honest authority model

### Decision: cooperative root token in v1

V1 does **not** add compiler bootstrap machinery. Public acquisition is renamed
to make its limit explicit:

```elm
module Schelm.Node.FileSystem exposing
    ( CooperativeRoot, RootError, cooperativeRoot
    , ReplaceOutcome(..), Error, ErrorKind(..)
    , replaceUtf8Atomically
    )

type CooperativeRoot
type RootError

cooperativeRoot : String -> Result RootError CooperativeRoot
```

`CooperativeRoot` prevents accidental root mixing and centralizes lexical
rooting. It is not authorization and not a security boundary: any linked code
can construct a token for any absolute path. There is no JS caller inspection,
stack check, secret constructor, or claim that the registry authenticates the
caller. Harness bootstrap constructs one sessions token and passes it to the
single persistence owner by convention.

The package readme and API docs must say “cooperative” adjacent to the type and
constructor. A future secure capability requires compiler/runtime-supplied fixed
roots or a native host embedding boundary; it cannot be retrofitted by renaming
this token.

`RootMode` is removed: v1 has one write operation, so a mode parameter adds no
safety. Phantom modes are deferred until there are both read and write APIs.

### Pure relative paths

Design 01's opaque `RelativePath`/`Segment` remains, with one simplification:
v1 exposes `fromSegments`, `segment`, `child`, `segments`, and diagnostic
`toString`; string path parsing, append, and empty-as-operable-target are omitted.
A replace target must contain at least one segment. Components reject empty,
`.`, `..`, NUL, `/`, `\\`, and Windows-reserved/ambiguous forms when Windows is
not supported. The pure model is the validation authority; JS repeats only NUL,
separator, and non-empty checks as a constitutional backstop.

## 3. Containment claim

### Decision: non-security Node path containment

V1 uses Node path strings and does not ship a native `openat` addon. It therefore
makes **no claim of secure containment against concurrent mutation or malicious
linked code**. It provides:

- lexical joining of validated segments below one cooperative root;
- rejection if the destination's existing parent chain or destination is a
  symbolic link at check time;
- same-directory temp placement;
- documented susceptibility to TOCTOU between check and use.

The harness deployment has one cooperative daemon user and does not treat local
processes with write access to the sessions tree as adversaries. If that threat
model changes, v2 must use descriptor-relative native operations and platform-
specific review before “secure root” or “capability” language is allowed.

## 4. Revised API and outcomes

```elm
type ReplaceOutcome
    = CommittedAndDurable
    | CommittedDurabilityUnknown Error

type ErrorKind
    = NotFound
    | PermissionDenied
    | NotDirectory
    | IsDirectory
    | SymlinkRejected
    | InvalidInput
    | PathTooLong
    | TooManyOpenFiles
    | IoFailure
    | Unsupported
    | UnknownFailure

replaceUtf8Atomically :
    CooperativeRoot
    -> RelativePath
    -> String
    -> Task Error ReplaceOutcome
```

Task failure means **not committed as observed by this transaction**: rename did
not report success. Task success always means rename reported success.
`CommittedDurabilityUnknown error` means complete new content is installed in
the namespace but parent-directory durability could not be established; it is
not a rollback and must not be flattened into failure. The harness owns retry
policy and should normally accept this outcome, log it, and rely on journal-based
recovery after a crash rather than immediately rewriting.

There is intentionally no `Interrupted` `ErrorKind`. Interruption is not proof
that an in-flight filesystem effect did not commit.

## 5. Transaction, cancellation, and exactly-once notification

Internal states are explicit:

```text
Preparing
TempOpening
TempOpen(fd, temp)
Writing(fd, offset)
TempSyncing(fd)
TempClosing(fd)
Renaming(temp, destination)
ParentOpening(destination installed)
ParentSyncing(destination installed)
ParentClosing(destination installed)
CleaningBeforeRename(optional fd/temp)
SettledNotCommitted(error)
SettledCommittedDurable
SettledCommittedUnknown(error)
Abandoned(inFlightPhase, cancellationRequested)
```

Two orthogonal facts are tracked internally: **effect phase** and **consumer
interest**. Node callback settlement uses one notifier cell:

```text
Interested callback | Abandoned
```

Cancellation changes `Interested callback` to `Abandoned` and requests cleanup
where the current phase permits it. It does not claim to abort a dispatched
`open`, `write`, `fsync`, `close`, or `rename`. Later callbacks continue the
minimal state machine needed to close descriptors/remove pre-rename temps.
No callback is delivered after abandonment, and at most one terminal callback
is delivered while interested.

Physical outcomes are separate:

- cancellation before rename dispatch: cleanup converges to no temp and old
  destination;
- cancellation while rename is in flight: rename may fail or commit; the
  consumer receives no claim either way;
- cancellation after rename: new content is committed; remaining parent sync /
  close is best-effort and tracked for leak tests;
- no destination is unlinked as cleanup;
- cleanup calls are idempotent and tolerate “already closed/missing.”

Because a caller that abandons cannot receive an outcome, the harness session
persistence owner must not cancel an in-flight metadata replace during normal
shutdown. It drains the one current write before session closure, bounded by the
existing daemon shutdown supervision. Hard process death is tested as a crash,
not modeled as successful cancellation.

## 6. Exact concurrency ownership

The package is a primitive, not a scheduler. It accepts complete bytes and does
not perform read-modify-write. The harness owns this state per session:

```elm
type MetaWriter
    = Idle PersistedMeta
    | Writing
        { committed : PersistedMeta
        , attempted : PersistedMeta
        , queuedLatest : Maybe PersistedMeta
        }
```

Rules:

1. one `MetaWriter` exists per live session in the daemon TEA model;
2. only that owner may call replace for `<session>/meta.json`;
3. while writing, patches apply in Elm to `attempted`/`queuedLatest`; only the
   latest complete next document is retained;
4. success advances `committed`; if queued state differs, start one next write;
5. pre-commit failure keeps the prior committed model and surfaces recovery;
6. committed-durability-unknown advances content state and records a warning;
7. shutdown drains each session's current replace; it does not launch a second
   writer;
8. multiple daemon processes writing the same sessions root are unsupported and
   must remain excluded by the harness's one-daemon liveness invariant.

This makes lost-update prevention an Elm-owned state machine. The kernel has no
global/per-path queue and unrelated sessions run concurrently. On cold startup,
disk/journal recovery remains authoritative as it is today.

## 7. Atomic and durability mechanics

For destination `dir/name`:

1. validate cooperative root and target components;
2. `lstat` existing parent chain and reject symbolic links (cooperative check);
3. open `dir/.name.schelm-<random>` with `O_CREAT|O_EXCL|O_WRONLY`, mode chosen
   as below;
4. encode once and loop `write` until all bytes are written; zero-progress write
   is failure;
5. `fsync` temp file;
6. close temp file;
7. rename temp over destination in the same directory;
8. open parent directory read-only, `fsync`, close;
9. classify success as durable only after step 8 succeeds.

Before rename success, every failure closes and unlinks the temp best-effort and
returns task failure. After rename success, failures return
`CommittedDurabilityUnknown`. There is no copy/delete or non-atomic fallback.
Random collision retry is capped (proposed 16); exhaustion is a typed failure.

### File mode decision

Compatibility takes priority over preserving an arbitrary old inode mode. The
current harness creates `meta.json` through `writeFileSync` under process umask,
then rewrites the same inode. V1 temp creation uses requested mode `0o666`, hence
final mode is `0o666 & umask`. Integration asserts the deployed expected mode
(`0o600` under harness umask `0o077`). If the deployed service does not set
`0o077`, integration is blocked until it does. Preserving pre-existing custom
mode is out of v1 because it adds a metadata read/race and is not current product
policy. This behavioral change must be called out in release evidence.

Rename changes inode and updates destination ctime/mtime. Exact timestamps are
not compatibility promises; tests assert monotonic/new timestamps only where the
filesystem supplies sufficient resolution.

## 8. Text, filename, and support contract

### UTF-8

Elm 0.19.x strings reaching kernel JS are JavaScript strings. V1 validates input
before any file effect:

- reject any unpaired UTF-16 high or low surrogate;
- accept paired surrogates representing Unicode scalar values;
- encode with Node UTF-8 only after validation;
- NUL is valid document content and encodes as byte `00`; NUL remains forbidden
  only in path components;
- the package has no read/decode API, so malformed input bytes are out of scope.

This prevents Node's replacement-character behavior from silently changing
caller text. Golden tests cover BMP, supplementary scalars, combining marks,
NUL content, and lone surrogates.

### Filenames

Path segments reject NUL and both separators on all platforms. V1 does not
normalize Unicode, trim spaces, fold case, or rewrite names. The first slice uses
ASCII controlled segments (`ses_*`, `meta.json`); arbitrary user filenames are
not a v1 compatibility promise.

### Normative platform matrix

V1 normative production/test target is:

- Node.js **24.x** (matching agent-harness `engines.node >=24`; CI pins a 24.x
  release),
- Linux x86_64, ext4 in production and CI where available.

Linux arm64 is build/smoke-only until included in CI. macOS may work but is not a
release gate. Windows is unsupported in v1: rename-over-existing and directory
fsync semantics differ, and path validation deliberately fails closed rather
than claiming parity. Node 25+ is not automatically supported merely because
`>=24` permits it in harness; each major requires the package runtime matrix to
be updated. Integration should tighten the harness range to `>=24 <25` or pin
its deployed runtime.

## 9. Exact `meta.json` compatibility and cutover

The package never serializes JSON. Harness Elm must produce bytes matching the
current host writer for unchanged metadata:

- UTF-8 encoding;
- two-space indentation;
- key insertion order exactly as the current object construction/merge contract;
- no trailing newline;
- no BOM;
- values and omission/null behavior unchanged.

Before migration, capture golden bytes for create, normal patch, title patch,
reseed after missing metadata, and reseed after corrupt metadata. A JS fixture
using current `JSON.stringify(value, null, 2)` is the bounded migration oracle.
New Elm serialization must byte-match those fixtures. Since JSON object ordering
in an Elm `Dict` would differ, the harness encoder must be an explicit ordered
field encoder; dynamic retained fields need a deliberate compatibility design.
If byte equivalence cannot be achieved without reproducing arbitrary JS object
merge order, revision B must either narrow the compatibility claim to parsed
JSON or choose a different first slice. It may not silently declare equality.

Cutover checklist:

1. introduce the per-session Elm `MetaWriter` and differential fixture;
2. route every production meta mutation through it;
3. replace final write verb with this package;
4. delete `fs.writeFileSync(mp, ...)` from `patchMeta` and remove/retire the JS
   meta writer export;
5. repository grep gate permits no production writer to `meta.json` outside the
   package integration;
6. no fallback to old writer on package error;
7. preserve journal reseed and sticky-title policy in Elm;
8. verify file mode, bytes, no newline, and recovery behavior;
9. evidence branch `schelm/01-node-filesystem-integration` is never deployed.

The old and new writers coexist only in tests until cutover. The test oracle is
not imported by production code.

## 10. Revised DRY/MISI/MITI claims

### DRY

- one pure path validator;
- one transaction implementation;
- one harness per-session serialization owner;
- one ordered harness metadata encoder;
- one production writer after cutover;
- old JS serializer/writer only as a temporary test oracle, then deleted from
  production paths.

### MISI

- invalid lexical target cannot be constructed;
- replace has no public temp/fd state;
- task failure versus committed outcome cannot be confused by the return type;
- durable and durability-unknown commits cannot be confused;
- one session cannot have two Elm metadata writes in flight;
- kernel JS cannot select policy or a filesystem verb dynamically.

The design does **not** claim that unauthorized paths are unrepresentable or
that TOCTOU escape is impossible. Those are explicitly outside v1.

### MITI

- notifier interest and physical effect phase are separate;
- abandonment cannot notify twice and cannot be interpreted as non-commit;
- pre-rename cleanup is idempotent;
- post-rename cleanup never removes destination;
- parent-sync failure preserves committed-content knowledge;
- session shutdown drains rather than canceling ordinary writes.

## 11. Complexity, IOPS, and 200-session gates

For path depth `p` and encoded bytes `w`, replacement is O(p + w) time and O(w)
memory. It performs no history/session scan. At most 200 session owners may hold
one in-flight replace each; each owner stores at most current attempted and one
coalesced next metadata value.

Reference successful replace at fixed existing depth (excluding collision and
symlink-check policy details):

```text
p lstat calls + 1 temp open + k writes + 1 file fsync + 1 close
+ 1 rename + 1 parent open + 1 directory fsync + 1 close
```

`k` depends only on short writes and `w`, never history. Implementation must
instrument fake-fs call counts and assert this formula. No destination pre-read,
stat for size, global queue, or scan of roots/sessions is permitted.

Repeatable performance gates run on dedicated Linux CI or a recorded benchmark
host, Node 24, local ext4, fixed CPU governor where controllable:

1. compare package replace with a Node reference implementing the same
   open/write/file-fsync/rename/dir-fsync sequence; p50/p95 package wall time may
   not regress reference by more than 25% and 1 ms absolute after warmup;
2. 200 independent session directories, one 4 KiB metadata replace each, max 32
   concurrently scheduled by harness: complete with exactly 200 file fsyncs and
   200 directory fsyncs, no more than formula IOPS, and p95 event-loop delay
   below 50 ms;
3. repeat serially and at concurrency 1/8/32; report throughput rather than set a
   hardware-independent absolute latency beyond event-loop delay;
4. cold-cache and warm-cache runs are recorded separately (cold via fresh dirs,
   not privileged global cache dropping);
5. after 10,000 fake-fs fault traces and 1,000 real replacements, fd count and
   temp-file count return to baseline; heap after forced GC does not grow more
   than 5% or 2 MiB, whichever is larger;
6. fsync is never omitted in an “AndDurable” result. A no-fsync benchmark cannot
   serve as the semantic baseline.

If shared CI cannot provide stable ext4 timing, call-count/leak/event-loop gates
remain blocking and latency is a non-blocking trend until a dedicated runner is
available. The report must say which class ran; it must not fabricate precision.

## 12. Three-layer property/model test architecture

### Layer A — pure Elm model

Model path validation, outcome algebra, and `MetaWriter` transitions. Generate
Unicode strings and per-session command sequences:

```text
Patch sid delta | WriteResult sid physicalOutcome | Shutdown sid | Restart sid
```

Properties: one in-flight write/session, latest patch eventually represented,
no cross-session effect, committed-unknown advances content, pre-commit failure
does not, and shutdown never starts after closed. Custom shrinkers remove
unrelated sessions/commands, shrink to one field delta, and retain the command
that exposes duplicate/lost update.

### Layer B — fake filesystem transaction machine

A deterministic JS fake implements each required fs verb with scripted outcomes:
short write, zero write, delayed callback, throw, callback error, rename commit,
fsync failure, close/unlink failure, and cancellation between any two events.
Generate operation/event schedules and compare transaction states to a pure
reference automaton. Shrinkers preserve (a) first rename dispatch/success,
(b) cancellation position, and (c) first failing fs verb while deleting other
events. Assert one notification, accurate committed class, and eventual cleanup
when callbacks are released.

### Layer C — real Node/OS/fault tests

Compiled Elm workers in debug and `--optimize` operate on fresh ext4 directories.
Tests cover actual modes/umask, Unicode bytes, symlink rejection, temp collisions,
200-session concurrency, process kill at instrumented transition hooks, and disk
inspection after restart. Fault hooks exist only in test builds/fixtures and do
not expose a production stringly operation API. Real tests cannot deterministically
prove absence of TOCTOU; documentation and threat model remain the control.

All layers run generated sequences with recorded seeds. A regression prints the
smallest shrunk trace and physical phase. Cold/warm isolated Schelm compiler
cache builds and deterministic archive/hash checks remain mandatory.

## 13. Gren 6.1.3 comparison, corrected

The factual reference remains the embedded `gren-lang/node` 6.1.3 sources in the
Gren compiler checkout.

| Gren | Revised Schelm v1 |
|---|---|
| `Permission` is acquired in `Init.Task` | `CooperativeRoot` is publicly constructed and is not equivalent authority. Compiler bootstrap is deferred explicitly. |
| Cross-platform public `Path` record with POSIX/Win32 conversion | Opaque validated relative segments; Linux-only v1 operational contract. |
| Broad unbounded filesystem, streams, handles, watches | One complete-document replace primitive only. |
| File handles use phantom read/write permissions | No public handles or modes. Private fd lifecycle belongs to one transaction. |
| `writeFile` directly replaces bytes | Schelm adds same-directory temp, file fsync, rename, and parent fsync with typed durability outcome. This is Schelm-specific, not Gren equivalence. |
| Raw error code predicates | Schelm exposes a smaller stable classification plus bounded error facts. |

The package is Gren-inspired in Task-shaped effects, opaque effect data, and
minimal kernel verbs. It does not claim capability, platform, API, or durability
equivalence.

## 14. Initial questions resolved

1. **Bootstrap:** cooperative token for v1; secure bootstrap deferred and claims
   reduced.
2. **Phantom modes:** no; v1 has only replacement.
3. **Bytes/text:** strict validated UTF-8 text only for the meta slice.
4. **Platform/fsync:** Node 24 + Linux x86_64/ext4 normative; file and parent
   fsync required for durable success.
5. **Containment:** cooperative lexical/symlink check, explicitly non-security;
   no native addon in v1.
6. **Harness slice:** `meta.json` remains, conditional on ordered byte-compatible
   Elm encoding evidence; revision B must switch slices if this is infeasible.
7. **Append durability:** append removed from v1.
8. **Bounds:** read/list removed; metadata write maximum is harness policy. For
   the integration benchmark/initial gate, harness should reject encoded
   `meta.json` above 1 MiB before calling the package, while normal fixtures are
   approximately 4 KiB. The package writes the supplied complete string and does
   not claim a caller-independent byte bound.

## 15. Remaining questions for review B

1. Is `CommittedDurabilityUnknown Error` sufficient, or must it carry whether
   parent open, sync, or close failed as a typed stage?
2. Does current harness metadata include unknown/dynamic keys whose insertion
   order prevents a stable ordered Elm encoder? This must be answered from
   exhaustive call-site inspection before implementation.
3. Is production umask provably `0o077` across all deployment paths? If not,
   should v1 preserve existing mode or integration set/verify umask centrally?
4. Can Elm task cancellation reliably signal the kernel binding's canceler in
   both debug and optimize output, and how will abandoned callbacks be observed
   in tests without adding production policy?
5. Should the package API call the operation `replaceUtf8Atomically` when durable
   success includes parent fsync, or a more explicit `replaceUtf8Durably`?

No source is implemented in this revision.
