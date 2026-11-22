// Conversation scenes: a scene of a quest that starts from the actor dialogue event.
// One plays at a time, and it begins only when its two partners can meet.
// See docs/engine/scenes.md#conversation-scenes.

import Foundation
import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyWorldState

@MainActor
extension SceneRuntime {
    /// How long a pair may take to meet, and how long its scene then waits before it
    /// tries again. OpenSky's choices (docs/engine/unverified-values.md).
    static let meetingSeconds: Double = 30
    static let meetingRetrySeconds: Double = 60
    /// How long a line waits for its speaker to face the listener. OpenSky's choice.
    static let facingSeconds: Double = 3

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
        let free = runtime.playingConversation(except: entry.formID) == nil
            && runtime.now >= runtime.pendingLines.conversationFreeAt
        if free, partners.count == 2, !mayStillTalk(partners[0], partners[1]) {
            end(.stopped)
            return false
        }
        let ready = partners.count == 2 && partners.allSatisfy { partner in
            runtime.holder(of: partner, except: entry.formID) == nil
                && runtime.host?.hasLoadedBody(partner) != false
        }
        if !ready, runtime.pendingLines.meeting?.scene == entry.formID {
            runtime.pendingLines.meeting = nil
        }
        guard ready, free, mayMeet() else {
            // Noted once, at the start call, so ticks do not flood the trace.
            if isNew {
                note(.waitingForConversation)
            }
            return false
        }
        return partnersMet(partners[0], partners[1])
    }

    /// The game's check on a waiting pair, run once its turn has come and no other scene
    /// holds a partner. False ends the scene, and with it the quest.
    private func mayStillTalk(_ speaker: ReferenceKey, _ partner: ReferenceKey) -> Bool {
        guard let host = runtime.host else { return true }
        let held = [speaker, partner].contains {
            runtime.holder(of: $0, except: entry.formID) != nil
        }
        guard !held else { return true }
        let blocksSpeaker: SceneActorStatus = [.inPlayerDialogue, .farFromPlayer, .talkForbidden]
        let blocksPartner: SceneActorStatus = [.inCombat, .talkForbidden, .changingSeat]
        return host.hasLoadedBody(speaker)
            && host.sceneActorStatus(speaker).isDisjoint(with: blocksSpeaker)
            && host.sceneActorStatus(partner).isDisjoint(with: blocksPartner)
    }

    /// One pair walks together at a time, and a pair that did not meet waits its turn.
    private func mayMeet() -> Bool {
        let lines = runtime.pendingLines
        if let meeting = lines.meeting, meeting.scene != entry.formID {
            return false
        }
        return runtime.now >= (lines.meetingRetryAt[entry.formID] ?? 0)
    }

    /// False while one partner still walks to the other. A pair that does not meet
    /// in `meetingSeconds` gives its turn to another scene.
    private mutating func partnersMet(_ speaker: ReferenceKey, _ partner: ReferenceKey) -> Bool {
        let lines = runtime.pendingLines
        if runtime.host?.conversationPartnersMeet(speaker, partner) != false {
            lines.meeting = nil
            return true
        }
        guard let meeting = lines.meeting else {
            lines.meeting = (entry.formID, runtime.now)
            note(.waitingForPartners)
            return false
        }
        if runtime.now - meeting.since > SceneRuntime.meetingSeconds {
            lines.meeting = nil
            lines.meetingRetryAt[entry.formID] = runtime.now + SceneRuntime.meetingRetrySeconds
        }
        return false
    }

    /// Starts the gap before the next conversation scene, when this one had begun.
    func endConversation() {
        if runtime.pendingLines.meeting?.scene == entry.formID {
            runtime.pendingLines.meeting = nil
        }
        guard entry.isConversation, state.holdsActors else { return }
        let gap = Double(runtime.loopPause(runtime.conversationGap))
        runtime.pendingLines.conversationFreeAt = runtime.now + max(gap, 0)
    }
}
