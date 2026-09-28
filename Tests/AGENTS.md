# AGENTS.md — Tests

Each folder here builds one target, named like the folder. `docs/tools/modules.md` lists
them and the rules `Package.swift` enforces.

## Testing libraries

A folder named `<Name>Testing/` is a library of shared fixtures, not a test target. Every
unit test target that needs the fixtures links it: package test targets, `OpenSkyTests`,
and `OpenSkyRealDataTests`.

- Declarations that tests use are `public`. A struct a test builds has an explicit
  `public init(...)`.
- A library may `@testable import` the module it builds fixtures for, and import the
  modules and testing libraries below it. `Package.swift` lists what it may import; any
  other import fails the build.
- A helper that needs a higher module is an extension in the test target that needs it,
  for example `SpellStoreFixture+Store.swift` in `Tests/OpenSkyGameDataTests/`.
- A library holds no `@Test`. Put tests in the test target of the module they test.
- Fixtures are synthetic and built in code, never an extracted game file (root
  `AGENTS.md`, Legal & IP boundary).
