# 04 — Adversarial review B

Verdict: **block implementation**. Revision A is substantially more honest, but
it still leaves the executable architecture and first integration slice
conditional. A final design must make those choices now.

## 1. The fault seam is not executable as described

“Test builds/fixtures” is not a build plan. Elm kernel JavaScript is copied into
generated output by the compiler; a production branch hidden behind an
environment variable would still ship test powers. Conversely, duplicating the
transaction in a fake package makes differential tests weak because the tested
code is not the shipped code.

Define separate production and fixture source trees that share exactly one
transaction implementation. State how each generated artifact is compiled,
how fixture hooks are injected without runtime production switches, and how CI
greps the final optimized production JavaScript to prove hook names/protocols
are absent.

## 2. Compiler/runtime bootstrap remains vague

Name the compiler commit, Node version, package cache/overlay, application entry
modules, generated artifacts, and initialization sequence. Kernel packages are
not callable directly from arbitrary host JS. The design must explain how the
harness requests the operation from Elm and receives completion without adding
a second writer.

## 3. Cancellation must be tested through Elm Scheduler semantics

A fake callback test is not evidence that an Elm task canceler runs. Build a real
worker that calls `Process.spawn` on the package task and `Process.kill` while a
fixture hook holds a filesystem callback. Run it under both debug and optimized
Elm output. Also distinguish this task cancellation fixture from hard
`child_process.spawn`/`SIGKILL` crash tests; process death cannot execute Elm
cleanup.

## 4. Crash hooks need phase and acknowledgment semantics

“Kill at transition hooks” is ambiguous. A parent must know whether a syscall was
merely about to dispatch or its callback acknowledged success. Define stable
phase names and an IPC handshake. Otherwise a test at “rename” cannot tell
whether old or new content is expected.

## 5. `meta.json` remains an unresolved first slice

Revision A says switch slices if dynamic key order is infeasible. That is still a
blocked decision. Choose a closed-schema file with one writer. `daemon.json` is
a better candidate if its actual call graph and liveness sequencing are migrated
without violating “written only after listen; removed on every exit; ready only
when service can answer.” If retaining `meta.json`, enumerate every caller and
commit to a canonical migration now.

## 6. Migration call graph and shutdown/re-exec are absent

For the chosen file, enumerate production writers, callers, restorers, removers,
signal handlers, upgrade exit 78/79, stale-daemon recycling, and process-exit
ordering. Explain which owner drains writes, when readiness may be advertised,
and when removal wins over an in-flight write. A late callback must never
recreate a rendezvous file after shutdown.

## 7. Descriptor cleanup is underspecified

List every descriptor and directory/temp residue by phase. “Best effort” must
state what can remain after callback failure, cancellation, SIGTERM, and SIGKILL.
Do not promise eventual cleanup after a callback that Node never delivers or
a process that has died. Define what the next boot scavenges, if anything.

## 8. Cancellation claims still exceed observability

`SettledNotCommitted` based on “rename did not report success” is not proof that
rename did not happen if the callback is lost or the process dies. Public results
must describe observed acknowledgments, not unknowable physical truth. Outcomes
need a typed commit stage and typed durability stage. Abandonment has no public
outcome and must not be inferred as failure.

## 9. Stable parent is a hidden precondition

Atomic same-directory rename is not enough if another owner renames/removes the
parent directory. Declare stable-parent ownership for the operation lifetime and
state who guarantees it. Cooperative containment and stable-parent assumptions
must be adjacent to the API.

## 10. Package naming/scope overstates v1

A package named `schelm-node-filesystem` exposing one cooperative atomic text
replace is a foundation for a filesystem package, not Gren's `FileSystem`
equivalent. State the honest v1 scope in module/docs and reserve broader API
claims for later releases.

## 11. Performance gates need a runnable baseline

“Dedicated CI or recorded host” and a 25%/1 ms threshold are not yet runnable.
Specify the checked-in benchmark command, baseline implementation, machine
identity recorded in output, blocking relative metrics, noise policy, and what
runs on ordinary GitHub CI. Do not make an unavailable dedicated runner a merge
precondition.

## 12. The property plan is not yet a plan

Name test entry points, generators, command/state representations, shrinkers,
trace counts, seeds, debug/optimize commands, and which assertions belong to
pure Elm, fixture Node, and real OS tests. Tests must be implementable with the
pinned compiler and Node 24, not aspirational native fault injection.

## Required final revision

Resolve every item above, select the first slice, and state deferred scope
without ambiguity. The six constitution artifacts must be committed before any
source, build script, fixture, or integration implementation begins.
