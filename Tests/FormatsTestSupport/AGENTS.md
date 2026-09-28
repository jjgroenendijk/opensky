# AGENTS.md — FormatsTestSupport

The `FormatsTestSupport` library target in `Package.swift`. Every unit test target links
it: the package test targets, `OpenSkyTests`, and `OpenSkyRealDataTests`. Declarations
that tests use are `public`, with an explicit `public init(...)` on a struct a test builds.

## What belongs here

A fixture that builds the bytes of a format in code: `BSAFixture`, `ESMFixture`,
`NIFFixture`, `PexFixture`, `StringTableFixture`, and the record fixtures under `ESM/`.
Subfolders match the format folders in `Sources/OpenSkyFormats/`.

A file here may import `OpenSkyFormats` and Apple frameworks, never `OpenSkyGameData` or
engine code. `Package.swift` does not list them, so such an import fails the build. A
helper that builds a store or engine state over these bytes is an extension in the test
target that needs it, for example `SpellStoreFixture+Store.swift` in
`Tests/OpenSkyGameDataTests/`.

Fixtures are synthetic and built in code, never an extracted game file (root `AGENTS.md`,
Legal & IP boundary).

## No tests here

A library holds no `@Test`. Put tests in the test target of the module they test.
