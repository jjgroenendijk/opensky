// The condition functions the dialogue suites reach without the engine: the
// core and data families plus the quest and dialogue families. The app uses
// `.standard`, which adds every other feature's functions.

import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyQuestsInterface

nonisolated extension ConditionFunctionRegistry {
    public static let dialogueTests: ConditionFunctionRegistry = {
        var registry = ConditionFunctionRegistry()
        ConditionFunctions.installCore(into: &registry)
        ConditionFunctions.installData(&registry)
        ConditionFunctions.installQuest(&registry)
        ConditionFunctions.installDialogue(&registry)
        return registry
    }()
}
