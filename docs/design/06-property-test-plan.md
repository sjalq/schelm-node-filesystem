# 06 — Executable property and model test plan

This plan tests the final contract in `05-design-revision-b.md`. It names the
source layout and commands to create during implementation; none exist in this
design-only commit.

## 1. Pinned matrix

Every blocking correctness fixture runs with:

- Schelm compiler commit
  `76bbe44424106c96f915cb24cd7f50d69f5cee0e`;
- Node `24.4.1`;
- isolated cold and warm `ELM_HOME` package caches;
- Linux x86_64; real durability/crash suite requires ext4 and otherwise reports
  an explicit skip (the fake/state suites remain blocking);
- both Elm debug and `--optimize` artifacts unless marked performance-only.

CI entry command:

```text
npm ci
npm run test:all
```

Planned scripts:

```text
test:pure          elm-test tests/elm
test:assemble      node tests/assembly.test.mjs
test:fixture       node --test tests/node/fake-transaction.test.mjs
test:worker        node --test tests/node/worker-runtime.test.mjs
test:cancel        node --test tests/node/cancellation.test.mjs
test:crash         node --test tests/node/crash.test.mjs
test:artifact      node tests/artifact-gate.mjs
test:archive       node tests/archive-repro.mjs
test:perf          node tests/perf/atomic-replace-bench.mjs --gate
test:all           build all matrices, then the above in that order
```

Failures print seed, artifact mode, filesystem facts, original trace, and shrunk
trace. Default deterministic root seed is committed; CI adds a seed derived from
commit SHA and uploads it.

## 2. Planned source/test layout

```text
src/Schelm/Node/FileSystem/AtomicText.elm
src/Schelm/Node/FileSystem/Path.elm
kernel-src/atomic-text-transaction.js
src/Elm/Kernel/SchelmAtomicText.js              generated production kernel
fixtures/package/elm.json
fixtures/package/src/.../AtomicTextFixture.elm
fixtures/package/src/Elm/Kernel/SchelmAtomicTextFixture.js
fixtures/AtomicTextFixtureWorker.elm
tests/workers/AtomicTextWorker.elm
tests/workers/CancelWorker.elm
tests/elm/PathTest.elm
tests/elm/WriterModelTest.elm
tests/node/fake-transaction.test.mjs
tests/node/worker-runtime.test.mjs
tests/node/cancellation.test.mjs
tests/node/crash.test.mjs
tests/perf/atomic-replace-bench.mjs
tests/support/model.mjs
tests/support/generators.mjs
tests/support/shrinkers.mjs
tests/support/fixture-parent.mjs
```

Assembly hashes the canonical transaction into both generated kernels. The
assembly test regenerates to a temporary directory and byte-compares outputs.
Only wrappers differ; transaction body hash must match.

## 3. Layer A: pure Elm properties

Use `elm-explorations/test` fuzzers. Run 1,000 cases/property locally and 10,000
for nightly/release; CI uses 2,000 plus fixed regression seeds.

### Path generators

`validSegment` generates non-empty Unicode scalar strings excluding NUL, `/`,
`\\`, `.`, and `..`; production v1 test paths additionally use portable ASCII.
`hostileSegment` weights empty, dot, dotdot, NUL, separators, drive/UNC forms,
unpaired surrogate fixtures injected through flags, very long components, and
combining/supplementary characters. `relativeFile` generates 1–16 segments.

Properties:

1. accepted segments contain none of the forbidden forms;
2. `relativeFile -> segments -> relativeFile` round-trips;
3. diagnostic rendering is never absolute and never introduces a component;
4. no accepted target is empty;
5. append/normalization is absent, so invalid input cannot be silently repaired;
6. valid BMP/supplementary text encodes to golden UTF-8; lone surrogates fail
   before an effect request (worker flag fixtures provide values Elm literals
   cannot safely express).

Shrinker removes components, shrinks one component by Unicode scalar, and
preserves at least one component/forbidden witness.

### Daemon owner model

Pure types:

```elm
type Owner = Absent | WritingNotReady Req | NotReady State
           | WritingReady Req | Ready State | Closing CloseState
type Command = ListenerBound State | HelloServable | ReplaceReply Req Outcome
             | RestoreReady | BeginClose | CloseDeadline | UnlinkAck
type Effect = StartReplace Req State | Unlink | CloseListener | Exit Int
```

Generate 1–200 owners' command interleavings, duplicate/late replies, close at
every phase, restore requests, and exit 78/79 requests. Properties:

- at most one replace effect in flight;
- `ready:true` never starts before `HelloServable`;
- callback with stale request id starts no write;
- after `Closing`, no write effect is emitted;
- unlink is the final namespace effect before close/exit;
- coalesced restore/ready converges to latest state;
- reexec exit occurs only after close ack or deadline unlink.

Shrinker drops unrelated owners/commands, then adjacent commands, retaining the
first invariant-breaking reply/close. A custom validity repair preserves the
`ListenerBound` predecessor when needed.

## 4. Layer B: fake filesystem transaction model

The JS reference model state is:

```text
phase, consumer(Interested|Abandoned), renameAck, fileSyncAck, dirSyncAck,
tempFd(Open|CloseRequested|CloseAck|Unknown), tempName(Present|Absent|Unknown),
parentFd(...), notification(None|One)
```

Commands/events:

```text
Start, AckSuccess, AckError(code), Throw(value), ShortWrite(n), ZeroWrite,
Cancel, ReleaseHeld, NeverCallback
```

Generator creates payloads 0–64 KiB and schedules of 1–80 events, weighted to
cancel/error before and after each stable fixture phase. It never invents a
callback for an undispatched operation. CI: 10,000 traces debug-wrapper and
10,000 optimize-wrapper-equivalent runs; release: 100,000.

Assertions after each command and at quiescence:

1. notification count <= 1;
2. rename acknowledgment only after `AfterRenameAck`;
3. durable only after file-sync and parent-sync acknowledgments;
4. parent close failure affects cleanup, not acknowledged durability;
5. pre-rename error never requests destination unlink;
6. cleanup calls at most once/resource and reports every unacknowledged residue;
7. after abandonment, notification remains zero while physical callbacks may
   advance phase;
8. write offsets increase exactly by acknowledged bytes; zero write fails;
9. successful content is complete UTF-8, never prefix/mix;
10. syscall count matches phase formula and unrelated roots/sessions are absent.

The shrinker removes event ranges, reduces payload, changes errors to one fixed
`EIO`, and shortens writes while retaining three witnesses: first failing or
held operation, cancellation position, and rename acknowledgment if relevant.
It reruns candidates against the model to reject invalid schedules.

## 5. Generated production/fixture identity tests

`tests/assembly.test.mjs`:

- regenerates both kernel wrappers;
- verifies embedded transaction SHA-256 equals canonical source SHA-256;
- extracts/normalizes wrapper regions and byte-compares transaction bodies;
- ensures fixture imports only fixture package;
- ensures production `elm.json` has no fixture dependency.

`tests/artifact-gate.mjs` compiles production worker and harness integration
entry debug/optimize, then fails on any occurrence of:

```text
SCHELM_FS_TEST_HOOK | beforeTempOpen | afterRenameAck | fixtureAck |
faultPlan | SchelmAtomicTextFixture | AtomicTextFixtureWorker
```

It also rejects `process.env`, dynamic `import(`, and global fixture lookup in
the production kernel section. Positive control asserts these tags exist in
fixture artifacts so a misspelled grep cannot pass vacuously.

## 6. Real generated worker runtime tests

`AtomicTextWorker.elm` receives flags `{ root, segments, text }`, runs public
`replace`, and reports encoded typed outcome. Node bootstrap loads each generated
artifact, initializes the Elm worker, and enforces a 10-second timeout.

Debug and optimize cases:

- empty, ASCII, NUL-content, BMP, combining, supplementary-scalar text;
- lone high/low surrogate flags rejected with no temp/destination change;
- existing/missing destination, stable existing parent;
- symlink destination/parent rejected at check time (without security claim);
- temp collisions through fixture only;
- permissions, ENAMETOOLONG, ENOENT, parent-is-file;
- exact result encoding for every commit/durability/cleanup stage;
- mode under `umask 077`, complete bytes, trailing LF behavior supplied by caller;
- 1,000 sequential operations leave fd count and matching temp count at baseline.

Old-host/new-package compatibility means Node 24.4.1 loads both debug/optimize
artifacts using the checked-in bootstrap. No compatibility is claimed for Node
23, 25, or stock Elm compiler.

## 7. Real `Process.spawn`/`Process.kill` cancellation suite

The fixture protocol pauses at exact phases. `CancelWorker.elm`:

1. `Process.spawn` fixture replace;
2. receives phase through fixture subscription;
3. sends parent `ReachedPhase`;
4. on parent command, executes `Process.kill`;
5. waits through multiple scheduler turns/timer ticks;
6. reports any forbidden completion.

Parent then acknowledges/releases the held fs callback and queries fixture state.
Run debug and optimize at:

| Cancel point | Allowed physical fact after release |
|---|---|
| BeforeWrite | temp may exist; no data write dispatched |
| held write callback | write may acknowledge; cleanup follows if callback arrives |
| BeforeRename | old destination; temp may remain until cleanup ack |
| held rename callback | old or complete new depending callback result; never infer failure from cancel |
| AfterRenameAck | complete new destination; no task completion after kill |

Assertions: Elm task emits no result after kill; notifier is abandoned once;
callbacks may continue; cleanup/residue matches observed acknowledgments. A
control run without kill must emit exactly one result. This verifies actual Elm
Scheduler canceler behavior, not only transaction internals.

## 8. Crash phase/ack suite

`fixture-parent.mjs` uses `child_process.spawn` and line-delimited JSON IPC.
Protocol event fields are `{ operationId, sequence, phase, facts }`. Parent sends
`Ack`; child emits `AckAccepted` after installing the requested continuation and
before proceeding. Parent SIGKILLs only after matching `AckAccepted`.

Run 100 repetitions/debug and optimize for:

- BeforeTempOpen;
- AfterTempOpenAck;
- AfterWriteAck at random partial offset;
- AfterFileSyncAck;
- BeforeRename;
- AfterRenameAck;
- AfterParentSyncAck.

Inspect destination bytes and exact matching temp residue. Expected sets follow
05 section 8; no test asserts cleanup after SIGKILL. OS closes descriptors; test
uses `/proc/<pid>/fd` before kill for ownership evidence and filesystem state
after `close` event. Separate SIGTERM integration tests exercise harness unlink
sequencing; they do not pretend SIGTERM cancels arbitrary Node fs calls.

## 9. Harness daemon-state migration tests

On evidence branch only, compile full harness debug/optimize and test the actual
call graph:

1. absent before listener bind;
2. canonical `ready:false` bytes after first replace ack;
3. `ready:true` only after Hello-servability fact and replace ack;
4. exact endpoint-first key order, two spaces, trailing LF;
5. startedAt stable across not-ready/ready/restore;
6. TCP and Unix-socket schemas;
7. write failure fails startup closed with absent file;
8. durability-unknown logs and remains probe-verifiable;
9. unhandled-rejection restore routes through owner and is suppressed in Closing;
10. normal close, SIGTERM, SIGINT, SIGHUP, uncaught exception, stale recycle,
    exit 78 apply, and exit 79 rollback all leave state absent before successor
    advertisement;
11. late callback after close cannot recreate file; second unlink is final;
12. grep proves no production direct writer/fallback remains.

A supervisor test spawns real `bin/agent`, observes phase timestamps, signals it,
and starts/reexecs successor. It asserts generations never overlap as ready files
and readers never parse partial JSON. Run 50 cycles per shutdown class where
cost permits; exit 78/79 use existing fake upgrade fixtures rather than applying
a real upgrade.

## 10. Scavenger tests

Pure policy tests generate names/ages/counts; host integration uses fresh dirs.
Only exact `.daemon.json.schelm-<32 lowercase hex>` entries older than 10 minutes
are selected, direct children only. At >256 entries, fail closed and advertise
nothing. Never select destination, fresh temp, uppercase/malformed suffix,
directory, symlink, or nested file. Generated sequences interleave crash residue
and boot; shrinker preserves the selected/non-selected counterexample.

## 11. Performance and resource gates

Implement exactly the benchmark in 05 section 10. The direct Node A baseline and
Elm/package B use identical payload bytes, destination set, concurrency, fsync
sequence, and interleaved round order. JSON records hardware/filesystem facts.

Blocking algorithm:

1. execute a complete A/B benchmark twice;
2. each invocation independently computes median throughput, p95 latency, and
   monitorEventLoopDelay p95;
3. fail only when the same threshold is exceeded in both invocations;
4. always fail exact syscall/fsync/leak violations immediately;
5. upload both raw files.

At 200 sessions/concurrency 32, assert exactly 200 rename acknowledgments, 200
file-fsync acknowledgments, 200 parent-fsync acknowledgments, no lost
operations, no per-session/global scan, fd baseline restored, and no matching
temp. Heap gate after forced GC: growth <= max(5%, 2 MiB) over 1,000 replacements.
The benchmark times optimize only; debug executes a 20-operation smoke.

## 12. Archive/compiler reproducibility and negative authorization

Build the private package archive twice from clean exported trees with normalized
timestamps/order; compare file list and SHA-256. Scan for credentials, absolute
workspace paths, fixture packages/hooks, and generated fault protocols. Test
cold-cache install then warm-cache rebuild in isolated `ELM_HOME`.

Negative fixtures compile with stock Elm and non-`sjalq` package identity and
must reject kernel source. Applications directly importing `Elm.Kernel.*` must
fail. The authorized package builds only with the pinned fork. These are compiler
boundary tests, not claims that `CooperativeRoot` is secure.

## 13. Release evidence checklist

A v1 candidate is blocked unless:

- all three layers pass debug/optimize with printed seeds;
- real cancellation and crash matrices pass;
- artifact absence positive/negative controls pass;
- exact daemon schema and all shutdown/reexec tests pass;
- sole old writer is removed and grep gate is green;
- 200-session relative performance/resource gates pass;
- cold/warm cache and deterministic archive checks pass;
- unsupported OS tests fail closed or skip explicitly without claiming support;
- package and evidence integration commits are pushed privately;
- integration branch is not deployed.

Deferred APIs get no placeholder kernel verbs. They require new reviewed designs.
