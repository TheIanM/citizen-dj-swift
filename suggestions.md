# Suggestions (not done — noted per "surgical changes" guideline)

## Consolidate test data loaders
`DecodingTests`, `PatternExpansionTests`, `SampleBankTests`, `TimingModelTests`, and
`OfflineRendererTests` each define their own private `load808()` / `loadPatterns()` /
`loadPattern(id:)` / `jsonURL(_:)` helpers that decode the bundled JSON via `Bundle.module`.
That's ~5 copies of the same ~8 lines.

Consider extracting a shared `TestData` enum in `Tests/CitizenDJTests/TestSupport.swift`
(`library()`, `patterns()`, `machine808()`, `pattern(id:)`, `jsonURL(_:)`) and migrating the
test files to it. Skipped for now to keep changes surgical during the audio-engine build-out.
