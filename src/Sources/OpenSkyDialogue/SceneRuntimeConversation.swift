// Conversation scenes: a scene of a quest that starts from the actor dialogue event.
// One plays at a time, and it begins only when its two partners can meet.
// See docs/engine/scenes.md#conversation-scenes.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyWorldState

@MainActor
extension SceneRuntime {
    /// The conversation scene that has begun, other than `scene`.
    func playingConversation(except scene: FormID) -> CatalogScene? {
        playingScenes().first { other in
            other.isConversation && other.formID != scene
                && store.component(SceneRuntimeState.self, for: other.key)?.holdsActors == true
        }
    }
}

@MainActor
extension SceneRuntime.Playback {
    /// False while a conversation scene must wait before its first phase. A dead
    /// partner ends the scene. Every other scene may always begin.
    mutating func conversationMayBegin() -> Bool {
        guard entry.isConversation, !state.holdsActors else { return true }
        let partners = runtime.filledActors(of: entry).prefix(2).map(\.reference)
        if
            partners
                .contains(where: { runtime.host?.sceneActorStatus($0).contains(.dead) == true })
        {
            end(.actorBehavior)
            return false
        }
        let ready = partners.count == 2 && partners.allSatisfy { partner in
            runtime.holder(of: partner, except: entry.formID) == nil
                && runtime.host?.hasLoadedBody(partner) != false
        }
        let free = runtime.playingConversation(except: entry.formID) == nil
            && runtime.now >= runtime.pendingLines.conversationFreeAt
        guard ready, free else {
            // Noted once, at the start call, so ticks do not flood the trace.
            if isNew {
                note(.waitingForConversation)
            }
            return false
        }
        return true
    }

    /// Starts the gap before the next conversation scene, when this one had begun.
    func endConversation() {
        guard entry.isConversation, state.holdsActors else { return }
        let gap = Double(runtime.loopPause(runtime.conversationGap))
        runtime.pendingLines.conversationFreeAt = runtime.now + max(gap, 0)
    }
}
