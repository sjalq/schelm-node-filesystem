# 07 — Ergonomics audit

Status: implementation gate for `feat/evan-filesystem-ergonomics`. This audit
accepts the guarantees and platform boundary in 05 and the executable evidence
plan in 06. It changes presentation and recipes, not the transaction.

## 1. The user’s mental model

The package does one thing:

> Replace all the text in one file, while keeping the old complete file visible
> until the replacement is installed.

A caller chooses a stable application-owned root once, chooses a file beneath
it from validated path segments, and then replaces that file. The useful state
diagram is:

```text
old file visible
    | prepare and sync a complete temporary file
    v
replacement installed (rename acknowledged)
    | sync containing directory
    v
replacement durable (sync acknowledged)
```

Cleanup is a separate fact. A durable replacement can still leave a descriptor
whose close was not acknowledged. Conversely, no rename acknowledgement does
not prove that the physical rename never happened. Those distinctions stay in
the advanced result.

Users should not need the terms kernel, ABI, host callback, file descriptor, or
libuv to choose a root, choose a file, perform the common durable replacement,
or recover from a common failure. Node/Linux/ext4 remain explicit platform
preconditions rather than the vocabulary of ordinary use.

## 2. Invalid states and where they are stopped

| Invalid or misleading state | Boundary |
| --- | --- |
| Relative or NUL-containing root | `CooperativeRoot` constructor rejects it |
| Empty file path; `.`, `..`, empty, NUL, or separator-bearing segment | `RelativeFile` constructor rejects it |
| Calling replacement with an unvalidated root or file | opaque values make it unrepresentable |
| Reporting durability before file sync, rename, and directory sync acknowledgements | transaction state machine and generated-worker tests |
| Treating cleanup as durability | distinct `Durability` and `Cleanup` values |
| Treating missing rename acknowledgement as proof that no rename occurred | result vocabulary and docs explicitly deny that claim |
| Treating the publicly mintable root as security authority | honest `CooperativeRoot` name and adjacent warning |
| Hiding a possibly installed file behind a generic task error | durable recipe error must identify `NotAcknowledged`, `InstalledButUnconfirmed`, or `DurableButCleanupIncomplete` |
| Asking common callers to manually combine durability and cleanup correctly | one recipe performs that classification from the core result |

The remaining checked failures are external facts: permissions, missing or
changed directories, symlinks, resource exhaustion, unsupported platform,
I/O failure, and a local process violating the stable-parent/single-writer
preconditions.

## 3. Tiny core and recipes

### Core (kept compatible)

- `cooperativeRoot` validates an application-owned absolute root.
- `relativeFile` validates explicit path segments.
- `replace` exposes commit acknowledgement, durability, and cleanup separately.
- Existing result accessors remain available.

This is the mechanism and remains the one authority.

### Recipes (new)

- `root` is the obvious spelling for first examples; `cooperativeRoot` remains
  as a compatibility alias and as the more cautionary spelling.
- `file` validates one filename. It prevents the common one-file example from
  needing a one-element list.
- `fileAt` validates a list of segments and is the readable recipe for nested
  paths; `relativeFile` remains as a compatibility alias.
- `replaceDurably` succeeds only when replacement, durability, and cleanup were
  all acknowledged. Its error algebra preserves whether installation may have
  happened, so callers never retry blindly.

Every recipe is implemented from the core constructors or `replace`; there is
no second transaction, path validator, or interpretation authority.

## 4. Error recovery

Constructor errors gain stable plain-English rendering. Runtime errors retain a
small typed `ErrorKind`, optional platform code for diagnosis, and a bounded
message. The durable recipe adds a decision-shaped error:

```elm
type DurableReplaceError
    = ReplacementNotAcknowledged ReplaceFailure
    | ReplacementInstalledButDurabilityUnconfirmed DurabilityStage Error Cleanup
    | ReplacementDurableButCleanupIncomplete (List Residue)
```

Recovery is then explicit:

- `ReplacementNotAcknowledged`: inspect the failure and current file before
  retrying; absence of acknowledgement is not proof of absence.
- `ReplacementInstalledButDurabilityUnconfirmed`: treat the new file as
  possibly visible but not proven durable; inspect/reconcile rather than
  blindly retrying.
- `ReplacementDurableButCleanupIncomplete`: the new file is durable; do not
  rewrite it merely to repair cleanup. Log residue and restart the owner if
  resource pressure requires it.

`durableErrorMessage`, `rootErrorMessage`, `pathErrorMessage`, and
`errorKindMessage` provide friendly display text without requiring callers to
parse arbitrary exception strings. Branching remains constructor-based.

## 5. Naming and scope honesty

Renaming the published repository/package would break the private immutable
pin and is unnecessary for this compatibility refactor. The exposed operation
module remains the honest `Schelm.Node.FileSystem.AtomicText`; README, package
summary, module overview, and examples must lead with “atomic text replacement,”
not imply a general filesystem API. `Schelm.Node.FileSystem.Path` remains a
supporting module for compatibility, while ordinary examples import only
`AtomicText`.

The words “filesystem package” describe repository lineage, not v1 breadth.
The docs explicitly defer reads, appends, directory management, binary data,
streams, security containment, and cross-platform support.

## 6. Executable claims

| Public claim | Bounded evidence |
| --- | --- |
| Constructors reject invalid roots/segments and accepted segments round-trip | `tests/elm/PathTest.elm`, `tests/node/path-model.test.cjs` |
| Recipes are aliases over the same validation authority | new recipe assertions in `PathTest.elm` |
| Durable helper classifies every core result without erasing install/durability/cleanup facts | new pure classification tests in `AtomicTextTest.elm` plus harness integration tests |
| Transaction notifies at most once and preserves acknowledgement ordering | `tests/node/model-equivalence.test.cjs`, `transaction.test.cjs`, `generated-kernel-abi.test.cjs` |
| Real generated Elm runs in debug and optimize modes | `scripts/build-fixtures.cjs`, `tests/run-generated-workers.cjs` |
| Production artifacts contain no fixture hooks | `tests/artifact-gate.cjs` |
| Real OS replacement is complete and same-directory atomic | `tests/node/real-os.test.cjs`, bounded performance gates |
| Package archive and compiler/package pins are reproducible/integrity checked | `tests/archive-repro.cjs`, harness `verify-schelm-provenance.cjs` |
| Harness accepts only acknowledged durable clean replacement | `tests/DaemonRendezvousTest.elm` using `replaceDurably` |

Required final evidence is the real package debug/optimize matrix followed by
the full bounded harness Elm, GUI, host, format, provenance, and build gates.
Generated provenance must name the final package commit; no deployment is part
of this stream.

## 7. Acceptance criteria

1. The first useful README example fits on one screen and imports one module.
2. A user can choose root, one file, and durable replacement without matching
   the advanced transaction result.
3. Every convenience failure says whether replacement was unacknowledged,
   installed but not proven durable, or durable with cleanup residue.
4. Existing source using `cooperativeRoot`, `relativeFile`, and `replace` still
   compiles.
5. No transaction/kernel behavior or platform guarantee is broadened.
6. Every new claim has debug/optimized or pure bounded executable evidence.
7. Package and harness branches are committed, provenance-pinned, fully gated,
   and pushed as evidence only.
