// The shell of the dialogue domain: owns the dialogue index, the open
// conversation's selection and follow-up, and the speaker the focus holds. The
// menu model and the movie stay in the app, because they live in
// `OpenSkyMenus`. See docs/engine/coordinators.md and docs/engine/dialogue.md.

import OpenSkyDialogueInterface
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState
import simd

/// Runs one conversation at a time over `DialogueRuntime`, and reads the world
/// through `DialogueWorld`. Without a dialogue index every call refuses.
@MainActor
public final class DialogueCoordinator {
    public let store: WorldStateStore
    /// Nil without game data.
    public var index: DialogueStore?
    /// Kept for the condition trace. Selecting again for a readout would
    /// evaluate every condition in the game twice a second.
    public private(set) var selection = DialogueSelection.empty
    /// `DialogueRuntime.choose` gives the follow-up topics and the goodbye
    /// flag once. Choosing again after the line would run the scripts again.
    public private(set) var followUp: DialogueChoice?
    /// Turned, stopped, and with its package suspended.
    public private(set) var heldSpeaker: ReferenceKey?
    /// The actor the player talks to, which `IsInDialogueWithPlayer` reads.
    public private(set) var conversationSpeaker: ReferenceKey?
    /// Kept across readout refreshes, so the user sees what they just did.
    public var lastOutcome: String?
    private var cachedStrings: LocalizedStrings?
    private var stringsResolved = false

    weak var world: (any DialogueWorld)?

    public init(store: WorldStateStore) {
        self.store = store
    }

    public func attach(world: any DialogueWorld) {
        self.world = world
    }

    /// Plugin string tables, loaded on first use.
    public var strings: LocalizedStrings? {
        if !stringsResolved {
            stringsResolved = true
            cachedStrings = world?.loadStrings()
        }
        return cachedStrings
    }

    /// Built per call, because every input is a live read. It is a cheap struct.
    public var runtime: DialogueRuntime? {
        guard let index, let world, let quests = world.questStates() else { return nil }
        var context = world.conditionContext()
        context.dialogue = context.dialogue.talking(to: conversationSpeaker)
        return DialogueRuntime(
            store: store,
            dialogue: index,
            questStates: quests,
            context: context,
            registry: world.conditionRegistry,
            fragments: world.fragments
        )
    }

    // MARK: - Conversation

    /// Selects what `speaker` offers. Nil, with the reason in `lastOutcome`,
    /// when no conversation can run.
    public func begin(with speaker: ReferenceKey) -> DialogueRuntime? {
        conversationSpeaker = speaker
        guard let runtime else {
            conversationSpeaker = nil
            lastOutcome = "no dialogue index loaded"
            return nil
        }
        selection = runtime.topics(for: speaker)
        return runtime
    }

    /// A greeting is a delivered response, so a say-once greeting spends
    /// itself. Its topic links are dropped: the greeting is said over the
    /// offered topics, not instead of them.
    public func recordGreeting(_ info: FormID, speaker: ReferenceKey) {
        guard let runtime else { return }
        do {
            _ = try runtime.choose(info, speaker: speaker)
        } catch {
            lastOutcome = "greeting not recorded: \(String(describing: error))"
        }
    }

    /// Says one response. Returns its record, or nil with the reason in
    /// `lastOutcome`.
    public func choose(_ id: FormID, speaker: ReferenceKey) -> TopicInfo? {
        guard let runtime else {
            lastOutcome = "no dialogue index loaded"
            return nil
        }
        guard let info = runtime.dialogue.info(id) else {
            lastOutcome = "no loaded plugin declares INFO \(id)"
            return nil
        }
        do {
            let choice = try runtime.choose(id, speaker: speaker)
            selection = choice.next
            followUp = choice
            lastOutcome = DialogueCore.saidText(info: id, choice: choice)
            return info
        } catch {
            lastOutcome = "choose refused: \(String(describing: error))"
            return nil
        }
    }

    /// Ends the response being said. Without topic links the speaker offers
    /// what they generally offer, selected again, because a say-once line
    /// just changed it.
    public func finishResponse(speaker: ReferenceKey?) -> DialogueResponseEnd {
        let follow = followUp
        followUp = nil
        if follow?.endsConversation == true {
            return .close
        }
        guard let runtime else { return .unchanged }
        if let follow, !follow.next.offers.isEmpty {
            return .topics(follow.next)
        }
        guard let speaker else { return .unchanged }
        selection = runtime.topics(for: speaker)
        return .topics(selection)
    }

    public func endConversation() {
        followUp = nil
        conversationSpeaker = nil
    }

    // MARK: - Speaker focus

    /// Holds `speaker` and turns it towards `playerEye`. Call it every frame
    /// while the camera frames somebody.
    public func focus(on speaker: ReferenceKey, playerEye: SIMD3<Float>) {
        apply(DialogueCore.focus(held: heldSpeaker, speaker: speaker), playerEye: playerEye)
    }

    /// Hands the held actor back to its package.
    public func releaseSpeakerFocus() {
        apply(DialogueCore.focus(held: heldSpeaker, speaker: nil), playerEye: .zero)
    }

    private func apply(
        _ step: (held: ReferenceKey?, effects: [DialogueFocusEffect]),
        playerEye: SIMD3<Float>
    ) {
        heldSpeaker = step.held
        for effect in step.effects {
            switch effect {
            case let .hold(actor):
                world?.suspendPackage(for: actor)
                world?.stopActor(actor)
            case let .face(actor):
                world?.faceActor(actor, towards: playerEye)
            case let .release(actor):
                world?.releaseFacing(of: actor)
                world?.resumePackage(for: actor)
            }
        }
    }
}
