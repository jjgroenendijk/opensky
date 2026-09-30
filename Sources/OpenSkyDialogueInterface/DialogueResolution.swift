// What dialogue knows about an actor, for conditions: a snapshot the main actor
// builds, like `QuestResolution`. It holds each actor's voice type (VTCK through
// the template chain) for `GetIsVoiceType`, and who talks to the player for
// `IsInDialogueWithPlayer`. An empty resolution gives reason-tagged false.
// See docs/engine/dialogue.md and docs/engine/condition-functions.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM

nonisolated public struct DialogueResolution: Sendable {
    /// VTCK of each actor this session resolved one for. An actor absent from
    /// the table has no *known* voice type, which is not the same as having
    /// none, so the function that reads it reports a coverage gap.
    private let voiceTypes: [ReferenceKey: FormID]
    /// The actor currently in conversation with the player, or nil when the
    /// player is not talking to anybody.
    public let speakerInDialogue: ReferenceKey?

    public static let empty = DialogueResolution()

    public init(
        voiceTypes: [ReferenceKey: FormID] = [:],
        speakerInDialogue: ReferenceKey? = nil
    ) {
        self.voiceTypes = voiceTypes
        self.speakerInDialogue = speakerInDialogue
    }

    /// Voice type of one actor, or nil when this session resolved none for it.
    public func voiceType(of key: ReferenceKey) -> FormID? {
        voiceTypes[key]
    }

    /// Whether `key` is the actor the player is talking to right now.
    public func isInDialogueWithPlayer(_ key: ReferenceKey) -> Bool {
        speakerInDialogue == key
    }

    /// This resolution with `speaker` marked as the conversation partner, which
    /// is what opening a conversation produces.
    public func talking(to speaker: ReferenceKey?) -> Self {
        DialogueResolution(voiceTypes: voiceTypes, speakerInDialogue: speaker)
    }
}

nonisolated extension DialogueResolution: ConditionResolution {}

nonisolated extension ConditionContext {
    /// The one seam dialogue facts come through, shaped exactly
    /// like the five above: an actor's voice type and who the player is talking
    /// to. Empty in a context with no world running, which makes every dialogue
    /// function a reason-tagged false rather than a convincing "no voice type".
    public var dialogue: DialogueResolution {
        get { self[resolution: DialogueResolution.self] }
        set {
            self[resolution: DialogueResolution.self] = newValue
        }
    }
}
