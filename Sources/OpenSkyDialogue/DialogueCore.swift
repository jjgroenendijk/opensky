// The pure rules of the dialogue domain: the speaker focus state machine and
// the readout sentences. Values in, values out. See docs/engine/coordinators.md
// and docs/engine/dialogue-camera.md.

import OpenSkyDialogueInterface
import OpenSkyFormatsESM

/// One command the speaker focus sends to an actor.
nonisolated public enum DialogueFocusEffect: Equatable, Sendable {
    /// Suspend the package and stop the movement, once per speaker.
    case hold(ReferenceKey)
    /// Turn towards the player. Sent every frame, because the player moves.
    case face(ReferenceKey)
    /// Release the turn and select a package again.
    case release(ReferenceKey)
}

/// What the conversation does after a response is said to its end.
nonisolated public enum DialogueResponseEnd: Equatable, Sendable {
    case close
    /// Show these topics. The coordinator already stored them as the selection.
    case topics(DialogueSelection)
    /// No runtime, so the list stays as it was.
    case unchanged
}

public enum DialogueCore {
    /// Moves the focus from `held` to `speaker`. A nil speaker releases.
    public static func focus(
        held: ReferenceKey?,
        speaker: ReferenceKey?
    ) -> (held: ReferenceKey?, effects: [DialogueFocusEffect]) {
        var effects: [DialogueFocusEffect] = []
        if let held, held != speaker {
            effects.append(.release(held))
        }
        guard let speaker else { return (nil, effects) }
        if held != speaker {
            effects.append(.hold(speaker))
        }
        effects.append(.face(speaker))
        return (speaker, effects)
    }

    public static func openedText(speaker: String, topicCount: Int, rejectedCount: Int) -> String {
        "opened with \(speaker): \(topicCount) topics, \(rejectedCount) rejected"
    }

    public static func saidText(info: FormID, choice: DialogueChoice) -> String {
        "said \(info): "
            + "\(choice.next.offers.count) follow-up topics, "
            + "\(choice.dispatchedFragments.count) fragments, "
            + "\(choice.unrunFragmentCount) unrun"
    }
}
