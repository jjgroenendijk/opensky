// The world side of the dialogue domain: what `DialogueCoordinator` reads from
// the running session, and the actor commands the speaker focus sends. The app
// answers it; a test passes a fake. See docs/engine/coordinators.md.

import OpenSkyConditions
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyQuestsInterface
import simd

/// What `DialogueCoordinator` reads from and sends to the running world.
@MainActor
public protocol DialogueWorld: AnyObject {
    /// Nil without a quest runtime. Then no conversation can run.
    func questStates() -> QuestResolution?
    func conditionContext() -> ConditionContext
    var conditionRegistry: ConditionFunctionRegistry { get }
    /// Nil in a session with no script runtime.
    var fragments: (any DialogueFragmentDispatching)? { get }
    /// Walks the VFS, so the coordinator calls it once.
    func loadStrings() -> LocalizedStrings?

    func suspendPackage(for actor: ReferenceKey)
    /// Selects a package again for the world as it is now.
    func resumePackage(for actor: ReferenceKey)
    func stopActor(_ actor: ReferenceKey)
    func faceActor(_ actor: ReferenceKey, towards point: SIMD3<Float>)
    func releaseFacing(of actor: ReferenceKey)
}
