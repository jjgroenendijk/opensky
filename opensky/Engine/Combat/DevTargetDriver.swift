// The scripted opponent (issue #374, roadmap item 15.7, scope point 2): a
// deterministic fixed-interval attack loop that stands in for the AI M16 will
// bring.
//
// ## Why this is a stand-in and says so
//
// A real opponent perceives, decides, paths and picks an attack. None of that
// exists yet: NPCs are render-only with single-clip playback, they have no
// behavior graph, and trigger occupancy is player-capsule-only. Building half an
// AI here to make the milestone's fight happen would put a second, worse
// decision layer in the engine that M16 would then have to remove.
//
// So the dev target is honest about what it is: a clock. It attacks on a fixed
// interval, from wherever it is standing, at whatever is in front of it. It does
// not chase, it does not choose, and it does not give up. What it *does* do is
// go through the shipping paths — the 15.4 hit volume, the 15.4 damage formula,
// the 15.3 actor-value store — so everything downstream of "an opponent hit the
// player" is the real thing and will still be the real thing when M16 replaces
// the clock with a mind.
//
// ## Why a phase machine rather than a timer per attack
//
// The same reason `MeleeCombatState` is one: a hit has to land at a moment the
// animation is at, and the contact frame has to be a single identifiable step
// rather than "whenever the timer expired". The phases below mirror the player's
// — idle, windup, contact, recovery — so the two sides of a fight are legible
// against each other, and a stagger takes the attack away exactly as the graph's
// own stagger transition does for the player.
//
// Advanced by a fixed step, so a run at 60 frames a second and a run at 144
// produce the same fight. `CombatLoopRuntime` owns the accumulator.
//
// Documented in docs/engine/combat.md.

import Foundation

/// Where the dev target's attack is.
nonisolated enum DevTargetPhase: String, Equatable, Sendable, CaseIterable {
    /// Waiting out the interval between attacks.
    case idle
    /// Winding up. The attack clip is playing and nothing has connected.
    case windup
    /// The contact step. Exactly one step long, which is what makes a hit land
    /// once rather than once per frame of the swing.
    case contact
    /// Following through. No new attack starts until this ends.
    case recovery
    /// Interrupted by a hit. Takes the attack away and holds for its own
    /// duration before the interval starts again.
    case staggered

    var isAttacking: Bool {
        self == .windup || self == .contact || self == .recovery
    }
}

/// What one advanced step of the driver did.
nonisolated struct DevTargetStep: Equatable, Sendable {
    /// The phase after the step.
    let phase: DevTargetPhase
    /// True on the step an attack began, which is the step the attack clip is
    /// asked for.
    let startedAttack: Bool
    /// True on the contact step, which is the step the hit volume runs on.
    let reachedContact: Bool
    /// True on the step a stagger began, which is the step the stagger clip is
    /// asked for.
    let startedStagger: Bool

    static let idle = DevTargetStep(
        phase: .idle, startedAttack: false, reachedContact: false, startedStagger: false
    )
}

/// The scripted attack loop, as a pure value over a fixed step.
nonisolated struct DevTargetDriver: Equatable, Sendable {
    /// Seconds between the end of one attack and the start of the next.
    ///
    /// An OpenSky number, chosen rather than read: no record states an attack
    /// cadence, and vanilla's comes from the combat AI this item deliberately
    /// does not build. Slow enough that a player can block, draw a bow, and
    /// watch what happened between blows.
    static let intervalSeconds: Float = 1.6
    /// Seconds from the attack starting to the contact step, which is roughly
    /// where the vanilla one-handed attack clip puts its `HitFrame`.
    static let windupSeconds: Float = 0.45
    /// Seconds of follow-through after contact.
    static let recoverySeconds: Float = 0.35
    /// How long a stagger holds the attack away.
    static let staggerSeconds: Float = 0.7

    private(set) var phase = DevTargetPhase.idle
    /// Seconds spent in the current phase.
    private(set) var phaseSeconds: Float = 0
    /// Attacks started and contact steps reached since construction. The two
    /// differ only by an attack a stagger interrupted before it connected.
    private(set) var attackCount = 0
    private(set) var contactCount = 0
    /// Whether the driver runs at all. False parks it in idle without losing
    /// its counts, which is what the panel's spawn/reset controls toggle.
    var isEnabled = false

    /// Advances by exactly one fixed step and reports what it did.
    ///
    /// A disabled driver reports idle and advances nothing, so a paused frame
    /// and a parked target are indistinguishable downstream.
    mutating func step(seconds: Float) -> DevTargetStep {
        guard isEnabled, seconds > 0, seconds.isFinite else { return .idle }
        phaseSeconds += seconds
        return switch phase {
        case .idle: advanceIdle()
        case .windup: advanceWindup()
        case .contact: enter(.recovery)
        case .recovery: advanceTimed(after: Self.recoverySeconds)
        case .staggered: advanceTimed(after: Self.staggerSeconds)
        }
    }

    /// Interrupts whatever is in flight, exactly as the graph's own stagger
    /// transition takes the player's attack away.
    ///
    /// - Returns: true when the driver actually entered a stagger, so a caller
    ///   asks for a clip only when there is one to play.
    @discardableResult
    mutating func stagger() -> Bool {
        guard isEnabled, phase != .staggered else { return false }
        phase = .staggered
        phaseSeconds = 0
        return true
    }

    /// Parks the driver back at idle without disturbing its counts, for a
    /// target that died or whose cell unloaded.
    mutating func park() {
        phase = .idle
        phaseSeconds = 0
    }

    /// Forgets everything, including the counts. What the panel's reset does.
    mutating func reset() {
        let enabled = isEnabled
        self = DevTargetDriver()
        isEnabled = enabled
    }

    // MARK: - Private

    private mutating func advanceIdle() -> DevTargetStep {
        guard phaseSeconds >= Self.intervalSeconds else { return unchanged() }
        attackCount += 1
        phase = .windup
        phaseSeconds = 0
        return DevTargetStep(
            phase: .windup, startedAttack: true, reachedContact: false, startedStagger: false
        )
    }

    private mutating func advanceWindup() -> DevTargetStep {
        guard phaseSeconds >= Self.windupSeconds else { return unchanged() }
        contactCount += 1
        phase = .contact
        phaseSeconds = 0
        return DevTargetStep(
            phase: .contact, startedAttack: false, reachedContact: true, startedStagger: false
        )
    }

    /// Returns to idle once the current phase has run for `duration`, which is
    /// what both of the plain waiting phases do.
    private mutating func advanceTimed(after duration: Float) -> DevTargetStep {
        guard phaseSeconds >= duration else { return unchanged() }
        return enter(.idle)
    }

    private mutating func enter(_ next: DevTargetPhase) -> DevTargetStep {
        phase = next
        phaseSeconds = 0
        return unchanged()
    }

    private func unchanged() -> DevTargetStep {
        DevTargetStep(
            phase: phase, startedAttack: false, reachedContact: false, startedStagger: false
        )
    }
}
