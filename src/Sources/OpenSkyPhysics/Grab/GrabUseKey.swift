// The Activate key of a grab: a tap on a grabbable object activates it, a hold starts the
// grab, and a second press and release lets go. See docs/engine/grab.md.

nonisolated public struct GrabUseKey: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case idle
        /// The key went down on a grabbable object and is still down.
        case waiting(held: Float)
        /// `pressedAgain` is true once a new press came after the grab started.
        case holding(pressedAgain: Bool)
    }

    public enum Event: Equatable, Sendable {
        /// Released before the hold time: activate the object as a plain press would.
        case tap
        case grab
        case letGo
    }

    public private(set) var phase = Phase.idle
    public let holdDelay: Float

    public init(holdDelay: Float = GrabSettings.vanilla.holdDelay) {
        self.holdDelay = holdDelay
    }

    public var isHolding: Bool {
        if case .holding = phase {
            return true
        }
        return false
    }

    /// A press of Activate. True when the grab takes it, so nothing else activates.
    public mutating func press(onGrabbable: Bool) -> Bool {
        switch phase {
        case .idle:
            guard onGrabbable else { return false }
            phase = .waiting(held: 0)
            return true
        case .waiting:
            return true
        case .holding:
            phase = .holding(pressedAgain: true)
            return true
        }
    }

    /// Each frame with the key's state. Releasing the key that started the grab keeps
    /// the object held.
    public mutating func advance(by delta: Float, isDown: Bool) -> Event? {
        switch phase {
        case .idle:
            return nil
        case let .waiting(held):
            guard isDown else {
                phase = .idle
                return .tap
            }
            let total = held + max(delta, 0)
            guard total >= holdDelay else {
                phase = .waiting(held: total)
                return nil
            }
            phase = .holding(pressedAgain: false)
            return .grab
        case let .holding(pressedAgain):
            guard pressedAgain, !isDown else { return nil }
            phase = .idle
            return .letGo
        }
    }

    /// The hold ended for another reason, such as the spring breaking.
    public mutating func drop() {
        phase = .idle
    }
}
