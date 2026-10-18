// Where a sequence door is between open and closed, and the text keys it passes.
// `ObjectReference.GetOpenState` reads the phase. See
// docs/engine/object-animation.md#sequence-doors.

import OpenSkyFormatsMesh

nonisolated public struct SequenceDoorMotion: Equatable, Sendable {
    public enum Phase: Equatable, Sendable {
        case open
        case opening
        case closed
        case closing

        /// The `GetOpenState` code: 1 open, 2 opening, 3 closed, 4 closing.
        public var openStateCode: Int32 {
            switch self {
            case .open: 1
            case .opening: 2
            case .closed: 3
            case .closing: 4
            }
        }

        var isOpenSide: Bool {
            self == .open || self == .opening
        }
    }

    public private(set) var phase: Phase
    /// The key time in the sequence of `motion`.
    public private(set) var time: Float

    /// At rest at the end of its open or close sequence.
    public init(open: Bool, rig: SequenceDoorRig) {
        phase = open ? .open : .closed
        time = rig.sequence(open ? .open : .close).timing.stopTime
    }

    public var motion: SequenceDoorRig.Motion {
        phase.isOpenSide ? .open : .close
    }

    /// Turns toward `wantsOpen` and runs `deltaTime` seconds. Returns the text keys
    /// passed, such as `Sound: DRSWoodGateHelgenOpen`, in time order.
    public mutating func step(
        wantsOpen: Bool, deltaTime: Float, rig: SequenceDoorRig
    ) -> [String] {
        if wantsOpen != phase.isOpenSide {
            reverse(rig: rig)
        }
        guard phase == .opening || phase == .closing else { return [] }
        let sequence = rig.sequence(motion)
        let timing = sequence.timing
        let next = time + max(deltaTime, 0) * max(timing.frequency, .ulpOfOne)
        let finished = next >= timing.stopTime
        let passed = sequence.textKeys.filter { key in
            key.time >= time && (finished || key.time < next)
        }
        time = min(next, timing.stopTime)
        if finished {
            phase = phase == .opening ? .open : .closed
        }
        return passed.map(\.value)
    }

    /// Starts the other sequence. A door that turns back part way starts the other
    /// sequence as far from its end as it was from its own start.
    private mutating func reverse(rig: SequenceDoorRig) {
        let from = rig.sequence(motion).timing
        let progress: Float = switch phase {
        case .open, .closed: 1
        case .opening, .closing: Self.fraction(time, of: from)
        }
        phase = phase.isOpenSide ? .closing : .opening
        let to = rig.sequence(motion).timing
        time = to.startTime + (1 - progress) * (to.stopTime - to.startTime)
    }

    private static func fraction(_ time: Float, of timing: ControllerTiming) -> Float {
        let span = timing.stopTime - timing.startTime
        guard span > 0 else { return 1 }
        return min(max((time - timing.startTime) / span, 0), 1)
    }
}
