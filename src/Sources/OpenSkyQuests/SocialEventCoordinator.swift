// The shell of the social pass: every few frames it asks the world for the loaded
// actors, lets `SocialEventCore` decide what NPCs do with each other, and hands the
// commands to the world. See docs/engine/random-conversations.md.

public import OpenSkyConditions
public import OpenSkyFormatsCore
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyQuestsInterface

/// What `SocialEventCoordinator` reads from the running session.
@MainActor
public protocol SocialEventWorld: AnyObject {
    /// Nil while no world is loaded.
    func socialFrame() -> SocialFrame?
    /// Whether `observer` has a clear sight line to `other`.
    func socialCanSee(_ observer: SocialActor, _ other: SocialActor) -> Bool
}

@MainActor
public final class SocialEventCoordinator {
    /// Frames between passes. Each pass reads every loaded actor.
    public static let frameInterval = 30
    public static let historyLimit = 12

    public let settings: SocialSettings
    public private(set) var recent: [StoryEventData] = []
    public private(set) var sentCounts: [FourCC: Int] = [:]
    public private(set) var state = SocialState()
    private var frames = 0
    let world: any SocialEventWorld
    private var pendingCommands: [SocialEventCommand] = []
    /// When a scene last asked each meeting speaker, in scene seconds.
    private var meetingAsked: [ReferenceKey: Double] = [:]

    public init(world: any SocialEventWorld, settings: SocialSettings = .documentedDefaults) {
        self.world = world
        self.settings = settings
    }

    /// Called once per frame.
    /// - Returns: the commands found since the last call, also by `runPass()`.
    public func tick() -> [SocialEventCommand] {
        frames += 1
        if frames >= Self.frameInterval {
            frames = 0
            runPass()
        }
        defer { pendingCommands = [] }
        return pendingCommands
    }

    /// One pass now, whatever the frame count. The next `tick()` returns its commands.
    public func runPass() {
        guard let frame = world.socialFrame() else { return }
        dropStaleMeetings(now: frame.now)
        let world = world
        let commands = SocialEventCore.pass(frame, settings: settings, state: &state) {
            world.socialCanSee($0, $1)
        }
        let events = commands.compactMap { command -> StoryEventData? in
            guard case let .reportStoryEvent(event) = command else { return nil }
            return event
        }
        for event in events {
            sentCounts[event.event, default: 0] += 1
        }
        recent = Array((recent + events).suffix(Self.historyLimit))
        pendingCommands += commands
    }

    /// A `DialogueActivate` package starts a conversation with `partner`: `ADIA` fires
    /// on the next tick, and a quest has 20 s to answer. False when either is busy.
    @discardableResult
    public func requestConversation(
        speaker: ReferenceKey, partner: ReferenceKey, now: Double
    ) -> Bool {
        guard speaker != partner, !state.isBusy(speaker), !state.isBusy(partner) else {
            return false
        }
        state.conversations.append(SocialConversation(
            speaker: speaker, partner: partner, startedAt: now,
            answerSeconds: SocialLimits.dialogueActivateAnswerSeconds
        ))
        state.recentPartners[speaker, default: []].insert(partner)
        state.recentPartners[partner, default: []].insert(speaker)
        let event = SocialEventCore.event("ADIA", speaker, partner)
        sentCounts[event.event, default: 0] += 1
        recent = Array((recent + [event]).suffix(Self.historyLimit))
        pendingCommands.append(.reportStoryEvent(event))
        return true
    }

    /// A conversation scene that has not begun asks its two partners to meet: one
    /// walks to the other, as after `ADIA`. The scene asks again each tick.
    /// - Returns: true once the pair stands together.
    public func meetForScene(
        speaker: ReferenceKey, partner: ReferenceKey, now: Double
    ) -> Bool {
        let pair: Set = [speaker, partner]
        if let talk = state.conversations.first(where: { pair == [$0.speaker, $0.partner] }) {
            state.sceneMeetings.insert(talk.speaker)
            meetingAsked[talk.speaker] = now
            return talk.phase == .talking
        }
        guard speaker != partner, !state.isBusy(speaker), !state.isBusy(partner) else {
            return false
        }
        state.conversations.append(SocialConversation(
            speaker: speaker, partner: partner, startedAt: now
        ))
        state.sceneMeetings.insert(speaker)
        meetingAsked[speaker] = now
        return false
    }

    /// A meeting no scene has asked for in this time ends by the normal rules.
    static let meetingAskSeconds: Double = 2

    private func dropStaleMeetings(now: Double) {
        for speaker in state.sceneMeetings.sorted()
            where now - (meetingAsked[speaker] ?? now) > Self.meetingAskSeconds
        {
            state.sceneMeetings.remove(speaker)
            meetingAsked[speaker] = nil
        }
        meetingAsked = meetingAsked.filter { state.sceneMeetings.contains($0.key) }
    }

    /// The speakers walking to their partner, whose scenes wait for them.
    public var approachingSpeakers: Set<ReferenceKey> {
        state.approachingSpeakers.subtracting(state.sceneMeetings)
    }

    /// Whether `actor` watches a fight.
    public func isWatchingCombat(_ actor: ReferenceKey) -> Bool {
        state.spectators[actor] != nil
    }

    /// Forgets everything for a new game.
    public func reset() {
        restore(SocialState())
    }

    /// Takes the state a save kept.
    public func restore(_ saved: SocialState) {
        state = saved
        recent = []
        frames = 0
    }
}
