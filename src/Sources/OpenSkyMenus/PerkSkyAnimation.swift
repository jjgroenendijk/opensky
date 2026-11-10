// Which named sequence each perk star and line plays. Each has a steady sequence for
// its state and plays a transition first when the state changes, such as `Unlock`
// before `Unlocked`. See docs/engine/perk-sky.md.

import Foundation

/// A star's state, named after the vanilla `intperkstars01.nif` sequences.
nonisolated enum PerkStarState: String, Equatable, Sendable {
    case locked = "Locked"
    case unlocked = "Unlocked"
    case owned = "Owned"
    case selected = "Selected"

    /// The sequence that leads from `self` into `next`, if the mesh has one.
    func transition(to next: Self) -> String? {
        switch (self, next) {
        case (_, .selected): "Select"
        case (.selected, _): "Deselect"
        case (.locked, .unlocked): "Unlock"
        case (.unlocked, .owned), (.locked, .owned): "Own"
        default: nil
        }
    }
}

/// A line's state, named after the vanilla `intperkline01.nif` sequences.
nonisolated enum PerkLineState: String, Equatable, Sendable {
    case locked = "Locked"
    case unlocked = "Unlocked"

    func transition(to next: Self) -> String? {
        self == .locked && next == .unlocked ? "Unlock" : nil
    }
}

/// The sequence one star or line plays now, and when it started.
nonisolated struct PerkSkyPlayback: Equatable, Sendable {
    let sequence: String
    let started: Double
    /// The steady sequence that follows a transition; nil while steady.
    let next: String?

    func seconds(at now: Double) -> Float {
        Float(max(0, now - started))
    }
}

/// Tracks the playback of every star and line by key.
nonisolated struct PerkSkyAnimator<Key: Hashable & Sendable>: Sendable {
    private var playbacks: [Key: PerkSkyPlayback] = [:]
    private var steady: [Key: String] = [:]

    init() {}

    /// The playback for `key` in steady state `state`. `transition` names the sequence
    /// from the last state; `duration` gives a sequence's length, nil when missing.
    mutating func playback(
        _ key: Key, state: String, transition: (String) -> String?,
        at time: (now: Double, duration: (String) -> Float?)
    ) -> PerkSkyPlayback {
        let (now, duration) = time
        let previous = steady[key]
        steady[key] = state
        if previous != state {
            let via = previous.flatMap(transition).flatMap { duration($0) == nil ? nil : $0 }
            let started = PerkSkyPlayback(
                sequence: via ?? state, started: now, next: via == nil ? nil : state
            )
            playbacks[key] = started
            return started
        }
        guard let current = playbacks[key] else {
            let fresh = PerkSkyPlayback(sequence: state, started: now, next: nil)
            playbacks[key] = fresh
            return fresh
        }
        if let next = current.next, current.seconds(at: now) >= duration(current.sequence) ?? 0 {
            let settled = PerkSkyPlayback(sequence: next, started: now, next: nil)
            playbacks[key] = settled
            return settled
        }
        return current
    }

    /// Drops the keys not in `kept`, so a later return starts steady again.
    mutating func keep(_ kept: Set<Key>) {
        playbacks = playbacks.filter { kept.contains($0.key) }
        steady = steady.filter { kept.contains($0.key) }
    }
}
