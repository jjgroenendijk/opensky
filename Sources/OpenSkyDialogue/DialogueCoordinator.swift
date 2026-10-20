// The shell of the dialogue domain: owns the dialogue index, the open
// conversation's selection and follow-up, and the speaker the focus holds. The
// menu model and the movie stay in the app, because they live in
// `OpenSkyMenus`. See docs/engine/coordinators.md and docs/engine/dialogue.md.

import OpenSkyDialogueInterface
import OpenSkyFormatsCore
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
    private var followInfo: TopicInfo?
    /// The TWAT topic of the response whose choice list shows, said if the player
    /// backs out (<https://ck.uesp.net/wiki/Topic_Info>).
    public private(set) var walkAwayTopic: FormID?
    /// Turned, stopped, and with its package suspended.
    public private(set) var heldSpeaker: ReferenceKey?
    /// The actor the player talks to, which `IsInDialogueWithPlayer` reads.
    public private(set) var conversationSpeaker: ReferenceKey?
    /// The line being said, which `IsTalking` and the emotion functions read.
    public private(set) var spokenLine: DialogueSpokenLine?
    /// Kept across readout refreshes, so the user sees what they just did.
    public var lastOutcome: String?
    /// Subtype names the Dialogue panel shows beside a topic.
    public var topicSubtypes = TopicSubtypeTexts.vanilla
    private var cachedStrings: LocalizedStrings?
    private var stringsResolved = false

    let world: any DialogueWorld

    public init(store: WorldStateStore, world: any DialogueWorld) {
        self.store = store
        self.world = world
    }

    /// Plugin string tables, loaded on first use.
    public var strings: LocalizedStrings? {
        if !stringsResolved {
            stringsResolved = true
            cachedStrings = world.loadStrings()
        }
        return cachedStrings
    }

    /// Built per call, because every input is a live read. The condition context is
    /// built only when the runtime first reads it.
    public var runtime: DialogueRuntime? {
        guard let index, let quests = world.questStates() else { return nil }
        let speaker = conversationSpeaker
        let line = spokenLine
        return DialogueRuntime(
            store: store,
            dialogue: index,
            questStates: quests,
            aliases: world.questAliases(),
            registry: world.conditionRegistry,
            fragments: world.fragments
        ) { [world] in
            var context = world.conditionContext()
            context.dialogue = context.dialogue.talking(to: speaker).saying(line)
            return context
        }
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
    public func recordGreeting(_ info: FormID, speaker: ReferenceKey) -> [DialogueCommand] {
        guard let runtime else { return [] }
        do {
            _ = try runtime.choose(info, speaker: speaker)
            spokenLine = Self.line(runtime.dialogue.info(info), speaker: speaker, greeting: true)
            return [.spokeToPlayer(speaker)]
        } catch {
            lastOutcome = "greeting not recorded: \(String(describing: error))"
            return []
        }
    }

    /// Says one response. Returns its record, or nil with the reason in
    /// `lastOutcome`.
    public func choose(_ id: FormID, speaker: ReferenceKey) -> DialogueResult<TopicInfo?> {
        guard let runtime else {
            lastOutcome = "no dialogue index loaded"
            return DialogueResult(nil)
        }
        guard let info = runtime.dialogue.info(id) else {
            lastOutcome = "no loaded plugin declares INFO \(id)"
            return DialogueResult(nil)
        }
        do {
            let choice = try runtime.choose(id, speaker: speaker)
            selection = choice.next
            followUp = choice
            followInfo = info
            walkAwayTopic = nil
            lastOutcome = DialogueCore.saidText(info: id, choice: choice)
            spokenLine = Self.line(info, speaker: speaker, greeting: false)
            var commands = [DialogueCommand.spokeToPlayer(speaker)]
            if let challenge = SpeechChallenge.won(by: info) {
                commands.append(.speechChallengeWon(challenge, speaker: speaker))
            }
            return DialogueResult(info, commands: commands)
        } catch {
            lastOutcome = "choose refused: \(String(describing: error))"
            return DialogueResult(nil)
        }
    }

    /// Ends the response being said. Without topic links the speaker offers
    /// what they generally offer, selected again, because a say-once line
    /// just changed it.
    public func finishResponse(speaker: ReferenceKey?) -> DialogueResponseEnd {
        let follow = followUp
        let info = followInfo
        followUp = nil
        followInfo = nil
        spokenLine = nil
        if follow?.endsConversation == true {
            return .close
        }
        if
            let info, info.flags.contains(.invisibleContinue),
            let next = follow?.next.offers.first
        {
            return .continueWith(next.info)
        }
        guard let runtime else { return .unchanged }
        if let follow, !follow.next.offers.isEmpty {
            walkAwayTopic = info?.flags.contains(.walkAway) == true ? info?.walkAwayTopic : nil
            return .topics(Self.hidingWalkAway(follow.next, of: info))
        }
        guard let speaker else { return .unchanged }
        selection = runtime.topics(for: speaker)
        return .topics(selection)
    }

    public func endConversation() {
        followUp = nil
        followInfo = nil
        walkAwayTopic = nil
        spokenLine = nil
        conversationSpeaker = nil
    }

    /// Records the walk-away line of the shown choice list as said and returns it, or
    /// nil when the list has none. The caller voices it as the conversation ends.
    public func walkAway(speaker: ReferenceKey) -> FormID? {
        guard let topic = walkAwayTopic else { return nil }
        walkAwayTopic = nil
        return sayAlone(runtime?.topics(linked: [topic], speaker: speaker), speaker: speaker)
    }

    /// Records the speaker's line for one Favors tab event, such as `SHOW` when a
    /// follower enters the favour state (<https://ck.uesp.net/wiki/Favors_Tab>).
    public func favorLine(_ subtype: FourCC, speaker: ReferenceKey) -> FormID? {
        let selection = runtime?.topics(subtype: subtype, speaker: speaker)
        return sayAlone(selection, speaker: speaker)
    }

    /// The blocking greeting that is a Force Goodbye, recorded as said: the speaker
    /// says it and the menu does not open (<https://ck.uesp.net/wiki/Dialogue_Branch>).
    public func forcedGoodbye(for speaker: ReferenceKey) -> FormID? {
        guard let runtime, let info = runtime.forcedGoodbye(for: speaker) else { return nil }
        return (try? runtime.choose(info, speaker: speaker)) == nil ? nil : info
    }

    private func sayAlone(_ selection: DialogueSelection?, speaker: ReferenceKey) -> FormID? {
        guard
            let runtime, let offer = selection?.offers.first,
            (try? runtime.choose(offer.info, speaker: speaker)) != nil
        else { return nil }
        return offer.info
    }

    /// Walk Away Invisible in Menu keeps the walk-away topic off the choice list.
    private static func hidingWalkAway(
        _ selection: DialogueSelection, of info: TopicInfo?
    ) -> DialogueSelection {
        guard
            let info, info.flags.contains(.walkAwayInvisibleInMenu),
            let hidden = info.walkAwayTopic
        else { return selection }
        return DialogueSelection(
            offers: selection.offers.filter { $0.topic != hidden },
            rejected: selection.rejected,
            tally: selection.tally
        )
    }

    private static func line(
        _ info: TopicInfo?, speaker: ReferenceKey, greeting: Bool
    ) -> DialogueSpokenLine {
        let response = info?.responses.first
        return DialogueSpokenLine(
            speaker: speaker,
            emotion: response?.emotion.rawValue ?? 0,
            emotionValue: response?.emotionValue ?? 0,
            isGreeting: greeting
        )
    }

    // MARK: - Speaker focus

    /// Holds `speaker` and turns it towards `playerEye`. Call it every frame
    /// while the camera frames somebody.
    public func focus(on speaker: ReferenceKey, playerEye: SIMD3<Float>) -> [DialogueCommand] {
        apply(DialogueCore.focus(held: heldSpeaker, speaker: speaker), playerEye: playerEye)
    }

    /// Hands the held actor back to its package.
    public func releaseSpeakerFocus() -> [DialogueCommand] {
        apply(DialogueCore.focus(held: heldSpeaker, speaker: nil), playerEye: .zero)
    }

    private func apply(
        _ step: (held: ReferenceKey?, effects: [DialogueFocusEffect]),
        playerEye: SIMD3<Float>
    ) -> [DialogueCommand] {
        heldSpeaker = step.held
        return step.effects.flatMap { effect -> [DialogueCommand] in
            switch effect {
            case let .hold(actor): [.suspendPackage(actor), .stopActor(actor)]
            case let .face(actor): [.faceActor(actor, towards: playerEye)]
            case let .release(actor): [.releaseFacing(actor), .resumePackage(actor)]
            }
        }
    }
}
