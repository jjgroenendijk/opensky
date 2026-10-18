// The world side of the dialogue domain: what `DialogueCoordinator` reads from
// the running session. The app answers it; a test passes a fake.
// See docs/engine/coordinators.md.

import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface

/// What `DialogueCoordinator` reads from the running world.
@MainActor
public protocol DialogueWorld: AnyObject {
    /// Nil without a quest runtime. Then no conversation can run.
    func questStates() -> QuestResolution?
    func conditionContext() -> ConditionContext
    /// The filled aliases alone, for a reader that needs them and no condition.
    func questAliases() -> QuestAliasResolution
    var conditionRegistry: ConditionFunctionRegistry { get }
    /// Nil in a session with no script runtime.
    var fragments: (any DialogueFragmentDispatching)? { get }
    /// Walks the VFS, so the coordinator calls it once.
    func loadStrings() -> LocalizedStrings?
}

extension DialogueWorld {
    public func questAliases() -> QuestAliasResolution {
        conditionContext().aliases
    }
}
