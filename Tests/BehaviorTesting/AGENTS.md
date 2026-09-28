# AGENTS.md — BehaviorTesting

The `BehaviorTesting` library target in `Package.swift`: behavior graph fixtures that
`OpenSkyBehaviorTests` and the tests of higher modules share. Declarations that tests use
are `public`. A library holds no `@Test`; tests go in the test target of the module they
test. Fixtures are synthetic and built in code (root `AGENTS.md`, Legal & IP boundary).
