# AGENTS.md — FormatsTestSupport

Fixtures compiled into all three unit-test bundles: `OpenSkyFormatsTests`, `OpenSkyTests`,
and `OpenSkyRealDataTests`. It is not a target. Membership follows the folder, as in
`Tests/TestSupport/`.

## What belongs here

A fixture that builds the bytes of a format in code: `BSAFixture`, `ESMFixture`,
`NIFFixture`, `PexFixture`, `StringTableFixture`, and the record fixtures under `ESM/`.
Subfolders match the format folders in `Sources/OpenSkyFormats/`.

A file here may import `OpenSkyFormats` and Apple frameworks, never engine code.
`OpenSkyFormatsTests` does not compile the engine, so a fixture that needs a runtime type
fails that build. Such a fixture goes in `Tests/TestSupport/` instead.

Fixtures are synthetic and built in code, never an extracted game file (root `AGENTS.md`,
Legal & IP boundary).

## No tests here

A `@Test` here would run in all three bundles. Put tests in `Tests/OpenSkyFormatsTests/`.
