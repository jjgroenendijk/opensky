// The condition functions the magic tests can reach without the engine: the
// core families plus the actor, data, magic, and perk families. The app uses
// `.standard`, which adds every other feature's functions.

import OpenSkyActorsInterface
import OpenSkyConditions
import OpenSkyMagicInterface
import OpenSkyProgressionInterface

nonisolated extension ConditionFunctionRegistry {
    static let magicTests: ConditionFunctionRegistry = {
        var registry = ConditionFunctionRegistry()
        ConditionFunctions.installCore(into: &registry)
        ConditionFunctions.installActor(&registry)
        ConditionFunctions.installData(&registry)
        ConditionFunctions.installMagic(&registry)
        ConditionFunctions.installPerk(&registry)
        return registry
    }()
}
