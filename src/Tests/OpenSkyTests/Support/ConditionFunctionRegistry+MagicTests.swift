// The condition functions the magic suites name: the
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
        ConditionFunctionsActor.installActor(&registry)
        ConditionFunctionsData.installData(&registry)
        ConditionFunctionsMagic.installMagic(&registry)
        ConditionFunctionsPerk.installPerk(&registry)
        return registry
    }()
}
