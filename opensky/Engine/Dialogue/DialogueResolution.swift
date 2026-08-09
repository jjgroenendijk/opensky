// The one place a condition asks "what does dialogue know about this actor?"
// (issue #426, roadmap item 17.2), mirroring `QuestResolution`,
// `QuestAliasResolution` and `ActorStateResolution`.
//
// Shaped as a resolved snapshot rather than as a live handle for the reason
// every other seam is: `ConditionContext` is a nonisolated value a build thread
// may evaluate against, so it cannot reach into `WorldStateStore` or into a
// `@MainActor` runtime. The caller that *is* on the main actor builds one and
// hands it over.
//
// Two facts live here, because two dialogue-demanded condition functions need
// them and neither is derivable from anything a condition already has:
//
// * The voice type of an actor, which `GetIsVoiceType` compares. It is a pure
//   read of the NPC_ record's VTCK through the template chain, so it is filled
//   once per resident actor rather than recomputed per condition.
// * Who is currently talking to the player, which `IsInDialogueWithPlayer`
//   reports. That is a fact about the live conversation and about nothing else,
//   which is why it is a field here rather than a component in the store: it
//   does not survive a save, because a reloaded game is not mid-sentence.
//
// An empty resolution — the default in a context with no world running — makes
// both functions a reason-tagged false rather than a convincing "no voice type"
// or "not talking", exactly as the empty actor seam does.
//
// Documented in docs/engine/dialogue.md and docs/formats/conditions.md.

import Foundation

nonisolated struct DialogueResolution: Sendable {
    /// VTCK of each actor this session resolved one for. An actor absent from
    /// the table has no *known* voice type, which is not the same as having
    /// none, so the function that reads it reports a coverage gap.
    private let voiceTypes: [ReferenceKey: FormID]
    /// The actor currently in conversation with the player, or nil when the
    /// player is not talking to anybody.
    let speakerInDialogue: ReferenceKey?

    static let empty = DialogueResolution()

    init(
        voiceTypes: [ReferenceKey: FormID] = [:],
        speakerInDialogue: ReferenceKey? = nil
    ) {
        self.voiceTypes = voiceTypes
        self.speakerInDialogue = speakerInDialogue
    }

    /// Voice type of one actor, or nil when this session resolved none for it.
    func voiceType(of key: ReferenceKey) -> FormID? {
        voiceTypes[key]
    }

    /// Whether `key` is the actor the player is talking to right now.
    func isInDialogueWithPlayer(_ key: ReferenceKey) -> Bool {
        speakerInDialogue == key
    }

    /// This resolution with `speaker` marked as the conversation partner, which
    /// is what opening a conversation produces.
    func talking(to speaker: ReferenceKey?) -> Self {
        DialogueResolution(voiceTypes: voiceTypes, speakerInDialogue: speaker)
    }

    /// Actors this resolution knows a voice type for.
    var voiceTypeCount: Int {
        voiceTypes.count
    }
}
