// The condition functions the dialogue suites reach without the engine: the
// core and data families plus the quest and dialogue families. The app uses
// `.standard`, which adds every other feature's functions.

public import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyQuestsInterface

nonisolated extension ConditionFunctionRegistry {
    public static let dialogueTests: ConditionFunctionRegistry = {
        var registry = ConditionFunctionRegistry()
        ConditionFunctions.installCore(into: &registry)
        ConditionFunctionsData.installData(&registry)
        ConditionFunctionsQuest.installQuest(&registry)
        ConditionFunctionsDialogue.installDialogue(&registry)
        return registry
    }()
}
