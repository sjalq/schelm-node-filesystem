# 02 — Adversarial review A

Verdict: **reject `01-design.md` pending revision**. The design is pointed in the
right direction, but several guarantees are stronger than the proposed Node
mechanics and several integration contracts are underspecified. No
implementation should start from design 01.

## 1. Capability minting is ambient

`authorize : RootSpec -> Task Error Root` is public and accepts any absolute
path. Calling the result a scoped capability does not make acquisition secure:
any linked Elm code can mint `/`, a home directory, or a second sessions root.
The caveat acknowledges this, but the MISI claims still speak of authorization
and unforgeable authority too strongly.

Choose one honest contract:

1. compiler/runtime bootstrap supplies a fixed, non-public set of capabilities;
   or
2. the package exposes an explicitly **cooperative token**, useful for avoiding
   accidental root confusion but not a security boundary.

Do not add a JavaScript stack/caller/module-name check. It would be forgeable,
optimizer-sensitive policy in the kernel.

## 2. `lstat` then path-string use is TOCTOU

The proposed containment walk checks path components and then asks Node to use a
path string. Another process can replace a checked component with a symlink
between those steps. Even the same process can race itself. This is not secure
containment.

Either specify a native descriptor-relative `openat`/`renameat` contract with
`O_NOFOLLOW`-style traversal and test it on every supported OS, or label lexical
rooting plus symlink checks as cooperative/non-security containment. The design
cannot claim “capability security” while using Node path strings.

## 3. Cancellation states are conflated

Many Node `fs` operations cannot be aborted after dispatch. An Elm task can stop
caring about its callback while the OS operation later writes or renames. Design
01 says cancellation consumes the transaction and cleanup runs, which is not
always true at cancellation time.

The state model must distinguish:

- cancellation requested;
- Elm result consumer abandoned;
- OS operation still in flight;
- effect committed;
- cleanup requested/in flight/completed;
- one terminal notification to the still-interested Elm consumer.

“One terminal transition” cannot mean “one physical outcome.” A canceled replace
may commit later. The package must never report “not committed” merely because a
callback was abandoned.

## 4. Rename and durability are different commits

After rename succeeds, the destination content is committed in the namespace.
If parent-directory `fsync` then fails, rollback is neither generally possible
nor desirable. Returning a generic `IoFailure` loses the key fact: content is
new, but crash durability is uncertain.

The public result must represent at least:

```text
NotCommitted error
CommittedAndDurable
CommittedDurabilityUnknown error
```

The harness must know which outcomes may safely be retried. Blind retry after an
uncertain durability result is a policy decision and does not belong in JS.

## 5. Concurrency ownership is missing

Atomic rename prevents torn files; it does not prevent lost updates. Two
read-modify-replace operations can both derive from version N and commit N+1A
then N+1B. Likewise, concurrent appends need an exact ordering owner if journal
order matters.

Specify:

- who serializes operations per session/path;
- whether one replace may be in flight at a time;
- whether callers pass complete bytes or mutation functions;
- what happens during session shutdown;
- whether multiple processes are supported.

A hidden global JS queue would be policy and could serialize unrelated sessions.
Prefer an Elm owner with one in-flight write per session. If multi-process
writers are out of scope, say so and enforce single-writer deployment.

## 6. Bounds must constrain work, not only returned values

A pre-stat followed by `readFile` can race file growth and allocate beyond the
limit. `readdir` can materialize all entries before rejecting entry `limit + 1`.
That violates the stated memory/work bound.

Bounded reads require fd-based incremental reads capped at `limit + 1` bytes.
Bounded listings require incremental `opendir`/`Dir.read` capped at
`limit + 1`, followed by close on every path. If v1 does not need read/list,
remove them rather than promise an unimplemented bound.

## 7. Text and platform contracts are incomplete

“Strict UTF-8” does not say what happens to JavaScript lone UTF-16 surrogates,
which Node encoding APIs may replace. Filename validity differs by platform and
Node behavior. The design names Windows paths while leaving durability and
parent-directory sync unresolved.

Specify:

- accepted Elm string scalar contract and lone-surrogate behavior;
- malformed bytes behavior if reads remain;
- NUL/separator/invalid filename behavior;
- Node minimum version;
- normative OS/architecture matrix;
- status of Windows rename-over-existing and directory fsync.

Do not imply cross-platform support from Gren-inspired path names unless it is
actually tested.

## 8. Harness compatibility is byte-level, not semantic only

The first slice replaces `meta.json`, but design 01 does not lock down current
bytes:

- `JSON.stringify(meta, null, 2)` key insertion order;
- no trailing newline today;
- UTF-8 behavior;
- existing/new file mode and umask;
- mtime/ctime effects;
- exact error timing;
- one current JS writer in `patchMeta`.

The integration needs golden byte fixtures and explicit compatibility decisions.
After cutover, old direct `writeFileSync` must be deleted from the meta writer;
a fallback creates two authorities. Atomic temp replacement also changes inode
and may change mode unless the implementation intentionally preserves it.

## 9. Test layers are blurred

Design 01 mentions a model and real temp directories but does not separate the
failure surfaces. Require three layers:

1. pure model for path and transaction semantics;
2. fake-fs state machine with controllable short operations, delayed callbacks,
   cancellation, and failure at every transition;
3. real OS tests and kill/fault tests for Node/kernel integration.

Each stateful layer needs generated command sequences and shrinkers that retain
the failing transition. Example fault cases are insufficient.

## 10. Performance lacks IOPS and fsync gates

Big-O tables do not catch an implementation that performs 12 stats and 3 fsyncs
per metadata patch. The target daemon can have 200 sessions. Add measured gates
for:

- filesystem calls per replace at fixed path depth;
- fsync count and scope;
- throughput/latency with 200 independent session owners;
- event-loop delay;
- heap growth and leaked fd/temp files after fault campaigns.

Warm/cold filesystem effects should be reported separately. A gate must define a
repeatable environment or a relative baseline, not an aspirational millisecond.

## 11. Gren comparison overreaches

The table accurately lists Gren 6.1.3 APIs, but “typed permission” is not an
achieved equivalence while arbitrary code can call public `authorize`. Gren's
`Init.Task` is materially different. Preserve the comparison as provenance, but
label the Schelm token cooperative unless bootstrap authority exists. Gren also
does not provide the atomic durability transaction being designed here, so that
part is Schelm-specific rather than “close to Gren.”

## Required revision

Narrow v1 to the first production slice if necessary. Resolve, rather than defer,
the initial authority, mode, bytes/text, platform, fsync, containment, append,
and integration questions. Define honest outcomes and exact ownership. Keep the
kernel minimal, but do not hide required mechanics behind optimistic API names.
No source implementation is approved until the revised design survives another
independent review.
