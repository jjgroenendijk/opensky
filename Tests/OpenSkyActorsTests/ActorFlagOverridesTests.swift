// Script and alias changes to the `ACBS` record flags. Rules:
// docs/engine/papyrus-script-state.md#record-flags.

import OpenSkyActorsInterface
import OpenSkyFormatsESM
import Testing

struct ActorFlagOverridesTests {
    @Test func aScriptClearWinsOverTheRecordAndAnAliasAddsItsFlag() {
        var overrides = ActorFlagOverrides(fromAliases: .protected)
        overrides.script(.essential, false)
        overrides.script(.ghost, true)
        overrides.script(.invulnerable, nil)
        let flags = overrides.applied(to: [.essential, .unique])
        #expect(flags == [.unique, .ghost, .protected])
    }
}
