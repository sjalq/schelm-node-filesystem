# schelm-node-filesystem

Private Schelm kernel package. V1 exposes
`Schelm.Node.FileSystem.AtomicText` for cooperative, same-directory replacement
of one complete UTF-8 text file and `Schelm.Node.FileSystem.Path` for opaque,
validated cooperative paths on Node 24.4.1/Linux x86_64/ext4.

`CooperativeRoot` is not authorization. Path/symlink checks are TOCTOU-prone and
are not a security boundary. The caller must own a stable parent directory and
be the sole process writing the destination.

## Toolchain

- Schelm Elm compiler fork commit `76bbe44424106c96f915cb24cd7f50d69f5cee0e`
- Elm language 0.19.2, based on official commit `48befde1`
- Node 24.4.1

## Verification

```sh
node scripts/assemble-kernels.cjs --check
node --test tests/node/*.test.cjs
node tests/artifact-gate.cjs
node tests/perf/atomic-replace-bench.cjs
```

`node scripts/build-fixtures.cjs` builds debug/optimized generated Elm workers
when the pinned Schelm compiler binary exists. It fails explicitly otherwise.
The production kernel is assembled with fixture observation lines removed; CI
greps the generated production artifact and checks a positive-control fixture.
