# 05 — Final design revision B

Status: final pre-implementation design. This document supersedes conflicting
parts of 01 and 03. Implementation may begin only after 04, 05, and 06 are
committed. Review B's blockers are resolved below.

## 1. Honest v1 product

Repository/package identity remains `sjalq/schelm-node-filesystem`, because it
is the first increment of that package family. The v1 exposed module is named
honestly:

```elm
Schelm.Node.FileSystem.AtomicText
```

V1 is **not a general filesystem API and not a Gren FileSystem equivalent**. It
contains one Linux/Node primitive: cooperatively rooted, stable-parent,
same-directory atomic replacement of a complete validated UTF-8 text file.

Deferred: reads, appends, directories, metadata, arbitrary binary data, streams,
handles, secure containment, Windows/macOS support, multi-process coordination,
and compiler-minted authority. These require later design/review artifacts.

## 2. Final public contract

```elm
module Schelm.Node.FileSystem.AtomicText exposing
    ( CooperativeRoot, RootError, cooperativeRoot
    , RelativeFile, PathError, relativeFile
    , ReplaceResult(..), ReplaceFailure
    , CommitAcknowledgement(..), Durability(..), DurabilityStage(..)
    , Cleanup(..), Residue(..), Error, ErrorKind(..)
    , replace
    )

type CooperativeRoot
type RelativeFile

cooperativeRoot : String -> Result RootError CooperativeRoot
relativeFile : List String -> Result PathError RelativeFile

replace :
    CooperativeRoot
    -> RelativeFile
    -> String
    -> Task ReplaceFailure ReplaceResult

type ReplaceResult
    = RenameAcknowledged
        { durability : Durability
        , cleanup : Cleanup
        }

type CommitAcknowledgement
    = NoRenameAcknowledgement
    | RenameWasAcknowledged

type Durability
    = FileAndDirectorySyncAcknowledged
    | DurabilityUnconfirmed DurabilityStage Error

type DurabilityStage
    = OpeningParent
    | SyncingParent
    | ClosingParent

type Cleanup
    = CleanupAcknowledged
    | CleanupIncomplete (List Residue)

type Residue
    = TempMayRemain
    | TempDescriptorMayRemain
    | ParentDescriptorMayRemain

type ReplaceFailure
    = ReplaceFailure
        { commit : CommitAcknowledgement -- always NoRenameAcknowledgement in v1 failure
        , phase : FailurePhase
        , error : Error
        , cleanup : Cleanup
        }
```

`RenameWasAcknowledged` only means Node invoked the rename callback without an
error. `NoRenameAcknowledgement` means no such callback was observed; it does
**not** prove the rename did not physically occur. `FileAndDirectorySyncAcknowledged`
means temp-file fsync, rename acknowledgment, and parent-directory fsync
acknowledgment were observed. `ClosingParent` after successful directory fsync
leaves durability acknowledged but cleanup incomplete; therefore an actual
implementation should represent close failure as
`FileAndDirectorySyncAcknowledged` plus `ParentDescriptorMayRemain`, not
`DurabilityUnconfirmed ClosingParent`. `ClosingParent` remains a stage only for
hosts where close is required to surface delayed sync failure; on normative
Node/Linux it is not emitted. This rule is tested.

Errors are bounded data with stable `ErrorKind` plus optional Node code, phase,
and diagnostic message. No `Interrupted` or `NotCommitted` constructor exists.
Task abandonment has no public result.

### Preconditions, adjacent and explicit

- The root token is cooperative, publicly mintable, and not security.
- Callers supply validated relative components; lexical/symlink checks are
  TOCTOU-prone and not containment against a hostile local process.
- One owner must keep the destination parent directory present and at the same
  pathname for the whole operation. The harness daemon-home owner satisfies
  this; tools must not rename/remove `~/.elm-harness` while the daemon runs.
- Exactly one process writes the destination. No package queue or file lock
  exists.
- Text with unpaired UTF-16 surrogates is rejected before filesystem effects.
- Node 24.4.1, Linux x86_64, ext4 is normative. Windows/macOS are unsupported.

## 3. Selected first slice: `daemon.json`

The uncertain dynamic `meta.json` migration is abandoned for v1. `daemon.json`
is closed-schema, small, already has one JS module as sole writer, and atomicity
directly strengthens liveness. Its canonical Elm record is:

```elm
type alias DaemonState =
    { endpoint : Endpoint        -- Tcp Int | UnixSocket String
    , pid : Int
    , generation : Int
    , ready : Bool
    , startedAt : String
    , ui : String
    }
```

One ordered Elm encoder emits exactly the current shape: endpoint field first
(`port` or `socket`), then `pid`, `gen`, `ready`, `startedAt`, `ui`; two-space
indent; one trailing LF; UTF-8; no BOM. Existing golden fixtures define exact
bytes. `startedAt` is captured once at listener initialization and reused when
`ready` changes or state is restored; this intentionally removes today's
accidental timestamp reset on every write. The schema remains externally
compatible.

## 4. Actual migration call graph

Current production facts inspected at harness commit
`6bbcbfe12e01db14707e9db0ec873068c83ff3ab`:

```text
host/serve.js runDaemon
  -> Elm.ServerMain.init
  -> initPkgJs
     -> elm-pkg-js/wire.js initialization
        -> HTTP/WS listen acknowledgment
        -> writeDaemonState(..., ready=False)
        -> markReady()
           -> writeDaemonState(..., ready=True)
        -> cleanup()/signals/close
           -> removeDaemonState()
  -> unhandledRejection listener
     -> restoreDaemonLivenessIfMissing()
        -> writeDaemonState(..., ready=True)

elm-pkg-js/daemon-state.js
  writeDaemonState: sole current writer
  removeDaemonState: ordinary remover
  readDaemonState: reader

bin/agent
  ensureDaemon/readDaemonState: reader
  killStaleDaemon: SIGTERM, SIGKILL, direct unlink of daemon.json

bin/agent upgrade supervisor
  host process exits 78/79 and re-execs/rolls back; daemon signal/exit cleanup
  removes rendezvous state before replacement boot advertises a new generation.
```

Tests also write fixtures directly; they are not production writers.

### Final call graph and bootstrap

A new Elm-owned `DaemonRendezvous` state machine in `ServerMain` is the sole
writer decision owner. `wire.js` still owns listener facts and unlink verb:

```text
wire listen callback
  -> daemonStateIn ListenerBound(endpoint,pid,generation,startedAt,ui)
Elm DaemonRendezvous Absent -> WritingNotReady
  -> AtomicText.replace daemon.json canonical not-ready bytes
  -> daemonStateOut NotReadyStored(requestId,result)
wire waits for this ack before allowing readiness transition
wire proves listener can serve Hello
  -> daemonStateIn MarkReady
Elm serial owner writes canonical ready bytes
  -> daemonStateOut ReadyStored(requestId,result)
wire may now report successful initialization
```

This preserves the stronger invariant: file absent before listen; not-ready only
after listen; `ready:true` only after the listener can serve Hello and the atomic
write is acknowledged. If either write has no rename acknowledgment, startup
fails closed and unlinks the file. `DurabilityUnconfirmed` is logged but accepted
because liveness is immediately probe-verified; this is explicit harness policy.

`restoreDaemonLivenessIfMissing` no longer calls a writer. It sends
`RestoreReady` to the same Elm owner only when `wire.isReady()` and listener
probe facts are true. Writes are serialized; `MarkReady` or restore coalesces to
one latest ready document.

Production writer removal is exact:

- delete `writeDaemonState` and its `fs.writeFileSync` body from
  `elm-pkg-js/daemon-state.js`;
- retain closed-schema readers/path facts and `removeDaemonState` unlink verb;
- repository gate rejects production `writeFile*`/`appendFile*`/rename targets
  for `daemon.json` outside generated package kernel output;
- no JS fallback writer on package failure.

### Shutdown, signal, stale recycle, and re-exec sequence

The owner has `Absent | WritingNotReady | NotReady | WritingReady | Ready | Closing`.
Every request carries monotonically increasing `requestId`; callbacks for a
non-current id are observation-only and cannot schedule another write.

1. Normal `wire.close`: transition owner to `Closing`, stop accepting write
   requests, await current replace callback up to 2 seconds, unlink daemon.json,
   close listener, then finish. Unlink is last and wins.
2. SIGTERM/SIGINT: synchronously set host `closing=true`, stop forwarding
   daemon-state outputs, unlink, then exit as today. In-flight callbacks cannot
   recreate the file because kernel replacement has no follow-up write and the
   process exits. No drain is promised on a signal path.
3. SIGHUP: current behavior merely unlinks while continuing, which violates one
   liveness fact. Final behavior enters the same graceful close path and exits
   after listener close; it does not continue serving without state.
4. Uncaught exception: set closing, unlink, exit. Unhandled rejection remains
   keep-alive only if listener is healthy; restoration goes through the Elm
   owner and is suppressed when closing.
5. Stale recycle in `bin/agent`: SIGTERM then SIGKILL remains an external
   supervisor path; direct unlink after kill remains a remover, not a writer.
6. Upgrade exit 78/79: request reexec first enters graceful close; stop writes,
   close/unlink rendezvous, then emit exit code to `bin/agent`. The replacement
   process writes a new generation only after its listener binds. The existing
   50 ms raw exit timer must be replaced by “close ack or 2 s deadline, then
   exit”; deadline path unlinks synchronously.
7. Late callback after `Closing` may be logged but cannot restore/write again.
   If rename itself races unlink, the close path performs a second unlink after
   drain/deadline immediately before exit. Under the stable-parent/single-process
   precondition this is the final namespace action.

## 5. Exact generated artifact and bootstrap model

Toolchain is frozen for v1 evidence:

- compiler: `/home/s.dormehl/git/elm-compiler/.worktrees/schelm-kernel-author`,
  commit `76bbe44424106c96f915cb24cd7f50d69f5cee0e` (Elm 0.19.2 fork based on
  `48befde1`);
- runtime: Node `24.4.1`;
- private package installed from immutable archive in an isolated
  `ELM_HOME`, pinned by package version, package commit, and SHA-256;
- production entry: harness `src/ServerMain.elm` -> `dist/server.js`, compiled
  once debug and once `--optimize` for evidence;
- package worker entry: `tests/workers/AtomicTextWorker.elm` ->
  `build/test/atomic-debug.js` and `atomic-optimize.js`;
- cancellation fixture entry: `tests/workers/CancelWorker.elm` -> debug/optimize;
- fixture package worker entry: `fixtures/AtomicTextFixtureWorker.elm` ->
  debug/optimize fixture artifacts.

Node bootstrap loads the generated CommonJS-shaped Elm output in a controlled
`vm`/wrapper, calls `Elm.<Worker>.init({ flags })`, subscribes to result/phase
ports, and sends fixture acknowledgments through ports. Harness production does
not call kernel JS directly: `ServerMain` calls `AtomicText.replace` as an Elm
Task after receiving listener facts through a hand-written JS<->Elm port. The
host receives only typed completion encoded by the existing port boundary.

## 6. One implementation, separate fixture package/source tree

Canonical transaction code lives once at:

```text
kernel-src/atomic-text-transaction.js
```

It is a parameterized JavaScript function over an `FsOps` record. Fixture
observations are single-line calls enclosed by assembler markers adjacent to the
real transitions. A deterministic assembler validates every marker, strips
those lines entirely for production, and substitutes the fixture IPC adapter in
the fixture output. Thus transition/control code has one implementation while
production contains neither an observer branch nor phase strings. It produces:

```text
src/Elm/Kernel/SchelmAtomicText.js       production: observe = no-op erased
fixtures/package/src/Elm/Kernel/SchelmAtomicTextFixture.js
                                         fixture: observe = phase IPC adapter
```

The fixture is a separate private test package/source tree with a distinct Elm
module/package identity; production never depends on it. Both generated kernels
contain the same SHA-256-stamped canonical transaction body. CI reruns assembly
and fails on diff, proving no copied second implementation has drifted.

Production artifact absence gates run on source and both generated harness
artifacts:

```text
rg -n 'SCHELM_FS_TEST_HOOK|beforeTempOpen|afterRenameAck|fixtureAck|faultPlan'
  src dist/server-debug.js dist/server-optimize.js
```

Any hit fails. CI additionally asserts fixture package/module names and fixture
port tags are absent from production JS. There is no environment-variable,
global, dynamic import, or runtime branch enabling hooks in production.

## 7. Descriptor lifecycle and honest cleanup residue

Owned resources:

| Phase | Temp fd | Temp pathname | Parent fd |
|---|---|---|---|
| before temp open ack | none | maybe created if callback lost | none |
| writing/syncing temp | open | exists | none |
| after temp close ack, before rename ack | closed | exists/maybe renamed | none |
| after rename ack | closed | destination installed, no temp name | none |
| parent open/sync/close | closed | none | open until close ack |

Each acknowledged fd is closed at most once by state construction. Pre-rename
error requests close then unlink; cleanup reports acknowledgment or residue.
A callback that never arrives can leave an fd/temp until process exit. Task
cancellation marks consumer abandoned and requests only cleanup made possible by
later callbacks. SIGKILL runs no cleanup; the OS closes descriptors, while a
pre-rename temp file may remain. A temp whose rename callback was lost may be
either absent (renamed) or remain.

Next boot performs a bounded scavenger **outside the package primitive**, after
acquiring single-daemon ownership and before advertising liveness: list only the
daemon home's direct children; unlink names matching the exact
`.daemon.json.schelm-<32 lowercase hex>` pattern older than 10 minutes; cap scan
at 256 entries and fail closed above it. This policy belongs in harness Elm with
minimal list/unlink host facts until later filesystem package APIs exist. It
never removes destination or fresh temps. Scavenger design is part of integration,
not a hidden promise of `replace`.

Observable guarantees stop at callbacks. There is no “eventual cleanup” promise
when callbacks never arrive or the process dies.

## 8. Transaction and fixture phase protocol

Stable phases are part of the fixture protocol, not the public package API:

```text
BeforeTempOpen, AfterTempOpenAck,
BeforeWrite, AfterWriteAck,
BeforeFileSync, AfterFileSyncAck,
BeforeTempClose, AfterTempCloseAck,
BeforeRename, AfterRenameAck,
BeforeParentOpen, AfterParentOpenAck,
BeforeParentSync, AfterParentSyncAck,
BeforeParentClose, AfterParentCloseAck,
BeforeTempUnlink, AfterTempUnlinkAck,
BeforeNotify, AfterNotify
```

`BeforeX` is emitted immediately before dispatch and includes operation id,
phase sequence, destination/temp identities, write offset/length, and known
acknowledgments. `AfterXAck` is emitted only from a successful Node callback.
Callback errors emit `XError` with the same sequence. Every emitted event pauses
the fixture before the next transition until parent sends
`Ack { operationId, sequence, action }`, where action is `Continue`,
`ReturnError code`, `ShortWrite n`, or `NeverCallback` where applicable.

Crash tests use `child_process.spawn` with IPC/stdout JSON lines. Parent waits for
an exact event, sends Ack when testing post-ack state, waits for `AckAccepted`,
then sends SIGKILL. Expectations:

- killed at `BeforeRename`: old destination and possibly temp;
- killed after `AfterRenameAck` plus `AckAccepted`: complete new destination;
- after `AfterFileSyncAck` but before rename: old destination plus temp;
- after `AfterParentSyncAck`: complete new destination with durability syscall
  acknowledged before kill.

The acknowledgment proves the child consumed the control message, not that a
future syscall happened. Tests inspect all allowed residue explicitly.

## 9. Real Elm cancellation fixture

`CancelWorker.elm` starts fixture `replace` with `Process.spawn`, waits for a
fixture phase message delivered through a subscription port, calls
`Process.kill pid`, and reports that the Elm task produced no completion after a
bounded observation window. The Node parent then releases/forces the held fs
callback and inspects phase events, descriptors, temp, and destination.

The matrix runs generated `CancelWorker` in debug and `--optimize` at:

- `BeforeWrite` (no write dispatched);
- held write callback after dispatch;
- `BeforeRename`;
- held rename callback after dispatch;
- `AfterRenameAck` before parent open.

This is the evidence for Elm Scheduler canceler behavior. Separately, Node
`child_process.spawn`/SIGKILL fixtures test crash facts; they make no cleanup or
notification assertion after death.

## 10. Performance gate that can run

Checked-in command (to implement) is:

```text
node tests/perf/atomic-replace-bench.mjs --json build/perf.json
```

It records Node/OS/kernel/filesystem (from `statfs`), CPU model/count, memory,
compiler/package commits, run seed, and artifact mode. In one process and fresh
local temp root it runs interleaved A/B rounds after warmup:

- A: direct Node reference with exactly the semantic syscall sequence;
- B: compiled Elm/package worker;
- payloads 256 B, 4 KiB, 1 MiB;
- serial and 200 destinations with scheduler concurrency 32;
- 9 rounds x 200 operations after 2 warmup rounds.

Blocking on ordinary `ubuntu-24.04` GitHub CI:

- fake-fs exact syscall formula and exactly one file/parent fsync per durable op;
- zero fd/temp leaks;
- B median throughput no worse than 35% below same-job A for 4 KiB/200-session;
- B p95 latency no more than 50% + 2 ms above same-job A;
- event-loop p95 delay under 75 ms and no worse than A + 25 ms;
- Mann-Whitney-style comparison is unnecessary for gate simplicity: fail only
  if threshold is exceeded in two complete consecutive benchmark invocations.

The relative same-job baseline handles variable hardware. Nightly/dedicated
results may trend stricter thresholds but are not required to merge. Raw JSON is
uploaded on failure. Debug runs for correctness only; optimize is performance
blocking.

## 11. Corrected Gren comparison

Gren 6.1.3 remains provenance for Task-shaped filesystem effects and private
kernel mechanisms. Its `Permission` via `Init.Task`, cross-platform `Path`, broad
filesystem API, handles, streams, and watches are not provided here.
`CooperativeRoot` is not equivalent authority. Gren's direct `writeFile` does not
specify this file+directory fsync transaction. V1 is a Schelm-specific atomic
text primitive informed by Gren, with no API/security/platform equivalence claim.

## 12. Final decisions and deferred work

- cooperative token, no fake security;
- Node path operations, non-security TOCTOU claim;
- stable parent + single writer are required preconditions;
- typed rename acknowledgment, durability stage, and cleanup residue;
- cancellation promises only observable callback/namespace facts;
- one canonical transaction assembled into distinct production/fixture packages;
- artifact grep proves hooks absent;
- daemon-state closed-schema slice chosen; meta migration deferred;
- daemon call graph and close/reexec sequencing fixed;
- Node 24.4.1/compiler commit/toolchain pinned;
- Linux x86_64/ext4 only;
- read/list/append/general filesystem remain deferred;
- executable tests and relative performance gates are specified in 06.

No source implementation is present in this design commit.
