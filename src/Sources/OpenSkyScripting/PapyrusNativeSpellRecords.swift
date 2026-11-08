// Spell record reads and the art preload hints. `Spell.IsHostile` (Creation Kit wiki
// "IsHostile - Spell") reads the hostile flag of the spell's effects, as a cast does.
// OpenSky loads spell and character-creation art when it is first drawn, so the preload
// hints have nothing to start and answer at once.

import Foundation
import OpenSkyFormatsESM
import OpenSkyMagicInterface
import OpenSkyScriptingInterface

extension PapyrusNativeFunctions {
    static func installSpellRecords(into registry: inout PapyrusNativeRegistry) {
        scriptState("Spell", "IsHostile", into: &registry) { call, bridge, spell in
            guard let record = bridge.magicNatives.casterRuntime?()?.spellbookAccess.record(spell)
            else {
                return failure(call, "IsHostile needs a resolved spell")
            }
            return .returned(.boolean(record.payload(caster: .player).isHostile))
        }
        let hints = [("Spell", "Preload"), ("Spell", "Unload"), ("Game", "PrecacheCharGen")]
        for (script, name) in hints {
            registry
                .register(PapyrusNativeFunction(scriptName: script, functionName: name) { _, _ in
                    .returned(.none)
                })
        }
    }
}
