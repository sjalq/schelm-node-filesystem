# Atomic text replacement for Elm on Node

Current compatible release: `1.1.0`. Existing `1.0.0` callers remain source
compatible; the ergonomic names and durable recipe are additive.

`Schelm.Node.FileSystem.AtomicText` replaces one complete UTF-8 text file while
keeping the old complete file visible until the replacement is installed.

Despite the historical repository name, v1 is **not a general filesystem API**.
It does not read files, append, manage directories, stream bytes, or provide a
security sandbox.

## The common path

Choose an application-owned root once, choose a file beneath it, then replace it:

```elm
import Schelm.Node.FileSystem.AtomicText as AtomicText
import Task exposing (Task)

save :
    AtomicText.CooperativeRoot
    -> AtomicText.RelativeFile
    -> String
    -> Task AtomicText.DurableReplaceError ()
save appRoot stateFile text =
    AtomicText.replaceDurably appRoot stateFile text

appRoot : Result AtomicText.RootError AtomicText.CooperativeRoot
appRoot =
    AtomicText.root "/var/lib/my-app"

stateFile : Result AtomicText.PathError AtomicText.RelativeFile
stateFile =
    AtomicText.file "state.json"
```

For a nested path, keep each segment explicit:

```elm
AtomicText.fileAt [ "sessions", "current.json" ]
```

`replaceDurably` succeeds only after installation, file and containing-directory
sync, and cleanup have all been acknowledged.

## Recovery is part of the type

A failed durable replacement says what is known:

```elm
case problem of
    AtomicText.ReplacementNotAcknowledged failure ->
        -- It may still have physically occurred. Inspect before retrying.
        inspectDestination

    AtomicText.ReplacementInstalledButDurabilityUnconfirmed stage error cleanup ->
        -- New text is installed but not proven durable. Reconcile explicitly.
        reconcileInstalledFile

    AtomicText.ReplacementDurableButCleanupIncomplete residue ->
        -- New text is durable. Do not rewrite it just to retry cleanup.
        reportCleanupResidue residue
```

Use `durableErrorMessage`, `rootErrorMessage`, and `pathErrorMessage` for friendly
display text. Branch on constructors rather than parsing messages.

## Advanced result

Use `AtomicText.replace` when your application has a custom recovery policy. It
keeps three facts separate:

1. whether rename installation was acknowledged;
2. whether file and containing-directory durability was acknowledged;
3. whether cleanup was acknowledged.

No rename acknowledgement does **not** prove that the physical rename did not
occur. A durable replacement may still report cleanup residue. The convenience
helper is derived from this result; there is only one transaction.

## Preconditions

This package is intentionally cooperative:

- `CooperativeRoot` is publicly mintable and prevents accidental root mixing;
  it is not security authority.
- The application must own the root and keep the destination parent directory
  at the same pathname throughout an operation.
- Exactly one process may write the destination. There is no package lock or
  queue.
- Path and symlink checks are TOCTOU-prone and do not contain a hostile local
  process.
- Text with unpaired UTF-16 surrogates is rejected before filesystem effects.
- The supported platform is Node 24.4.1, Linux x86_64, and ext4.

The compatibility names `cooperativeRoot` and `relativeFile` remain available.

## Toolchain

- Schelm Elm compiler fork commit `76bbe44424106c96f915cb24cd7f50d69f5cee0e`
- Elm language 0.19.2, based on official commit `48befde1`
- Node 24.4.1

## Verification

Run the full bounded package evidence matrix:

```sh
npm test
```

That includes Elm properties, transaction/model tests, real debug and optimized
Elm workers, real OS tests, fixture-free production artifact checks, archive
reproducibility, and bounded performance gates. The production kernel is
assembled from the same transaction source as the instrumented fixture and is
mechanically checked to contain no fixture hooks.
