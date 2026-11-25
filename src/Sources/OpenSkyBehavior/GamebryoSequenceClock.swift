// Times the NIF sequences a graph's own mesh plays, so the text keys a sequence passes,
// such as `end`, reach the graph as events. See docs/engine/effect-graphs.md.

/// One NIF sequence as a graph's mesh plays it, in seconds from its start.
nonisolated public struct GamebryoSequenceTiming: Equatable, Sendable {
    public struct Key: Equatable, Sendable {
        public let time: Float
        public let name: String

        public init(time: Float, name: String) {
            self.time = time
            self.name = name
        }
    }

    public let duration: Float
    public let loops: Bool
    public let keys: [Key]

    public init(duration: Float, loops: Bool, keys: [Key]) {
        self.duration = duration
        self.loops = loops
        self.keys = keys.sorted { $0.time < $1.time }
    }

    /// The key names after `from` up to and including `now`; a nil `from` includes time 0.
    /// A looping sequence passes its keys again on each lap.
    func keys(after from: Float?, through now: Float) -> [String] {
        let lower = from ?? -1
        guard loops, duration > 0 else {
            return keys.filter { $0.time > lower && $0.time <= now }.map(\.name)
        }
        let firstLap = Int((max(lower, 0) / duration).rounded(.down))
        let lastLap = min(Int((now / duration).rounded(.down)), firstLap + Self.lapLimit)
        var passed: [String] = []
        for lap in firstLap ... max(firstLap, lastLap) {
            for key in keys {
                let time = key.time + Float(lap) * duration
                if time > lower, time <= now {
                    passed.append(key.name)
                }
            }
        }
        return passed
    }

    /// A long step on a short loop passes each key a few times at most.
    private static let lapLimit = 4
}

/// The seconds each played sequence has run. A sequence the graph leaves starts again
/// at its first key when the graph comes back to it.
nonisolated public struct GamebryoSequenceClock: Sendable {
    private let timings: [String: GamebryoSequenceTiming]
    private var elapsed: [String: Float] = [:]

    public init(timings: [String: GamebryoSequenceTiming]) {
        var folded: [String: GamebryoSequenceTiming] = [:]
        for (name, timing) in timings {
            folded[name.lowercased()] = timing
        }
        self.timings = folded
    }

    /// The text keys the playing sequences pass in this step, in play order. A sequence
    /// the graph has just reached stands at 0 and passes its keys at 0.
    public mutating func advance(playing: [String], by step: Float) -> [String] {
        var passed: [String] = []
        var next: [String: Float] = [:]
        for name in playing {
            let key = name.lowercased()
            guard next[key] == nil, let timing = timings[key] else { continue }
            let from = elapsed[key]
            let now = from.map { $0 + step } ?? 0
            next[key] = now
            passed += timing.keys(after: from, through: now)
        }
        elapsed = next
        return passed
    }
}

nonisolated extension BehaviorGraphInstance {
    /// Raises each text key the played sequences passed; the graph takes them next update.
    func raiseSequenceKeys(step: Float) {
        guard var clock = sequenceClock else { return }
        let passed = clock.advance(playing: gamebryoSequences, by: step)
        sequenceClock = clock
        for name in passed {
            raiseEvent(named: name)
        }
    }
}
