// Splits cell-load time into the asset phases a benchmark reports. Each phase
// counts only its own time: a mesh load that reads an archive gives that read
// to `.archive`. See docs/tools/benchmark.md.

import Foundation
import Synchronization

nonisolated public enum LoadPhase: String, CaseIterable, Codable, Sendable {
    /// Reading bytes from loose files and archives, decompression included.
    case archive
    /// DDS parsing and the GPU texture upload.
    case texture
    /// NIF parsing, flattening, and GPU buffer building.
    case mesh
    /// Static collision, trigger volumes, and dynamic bodies.
    case collision
}

/// Milliseconds spent in each phase, plus the time no phase claimed.
nonisolated public struct LoadPhaseTimes: Codable, Equatable, Sendable {
    public var archiveMS: Double
    public var textureMS: Double
    public var meshMS: Double
    public var collisionMS: Double
    public var otherMS: Double

    public init(
        archiveMS: Double = 0,
        textureMS: Double = 0,
        meshMS: Double = 0,
        collisionMS: Double = 0,
        otherMS: Double = 0
    ) {
        self.archiveMS = archiveMS
        self.textureMS = textureMS
        self.meshMS = meshMS
        self.collisionMS = collisionMS
        self.otherMS = otherMS
    }

    public subscript(phase: LoadPhase) -> Double {
        get {
            switch phase {
            case .archive: archiveMS
            case .texture: textureMS
            case .mesh: meshMS
            case .collision: collisionMS
            }
        }
        set {
            switch phase {
            case .archive: archiveMS = newValue
            case .texture: textureMS = newValue
            case .mesh: meshMS = newValue
            case .collision: collisionMS = newValue
            }
        }
    }

    public var measuredMS: Double {
        LoadPhase.allCases.reduce(0) { $0 + self[$1] }
    }

    /// The same times, with `otherMS` set to what `totalMS` leaves after the phases.
    public func completed(totalMS: Double) -> Self {
        var times = self
        times.otherMS = max(0, totalMS - measuredMS)
        return times
    }
}

/// Collects phase times for one thread of loading. Nested measurements are
/// allowed; overlapping ones from two threads would mix their times.
nonisolated public final class LoadPhaseRecorder: Sendable {
    private struct State {
        var totalsNS: [LoadPhase: UInt64] = [:]
        /// Child time of each open measurement, innermost last.
        var openChildNS: [UInt64] = []
    }

    private let state = Mutex(State())
    private let now: @Sendable () -> UInt64

    /// - Parameter now: a monotonic clock in nanoseconds; tests pass a fake.
    public init(now: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds }) {
        self.now = now
    }

    public func measure<T>(_ phase: LoadPhase, _ body: () throws -> T) rethrows -> T {
        state.withLock { $0.openChildNS.append(0) }
        let started = now()
        defer {
            let elapsed = now() &- started
            state.withLock { state in
                let childNS = state.openChildNS.popLast() ?? 0
                state.totalsNS[phase, default: 0] += elapsed &- min(childNS, elapsed)
                if let parent = state.openChildNS.indices.last {
                    state.openChildNS[parent] += elapsed
                }
            }
        }
        return try body()
    }

    /// The phase totals so far; `otherMS` stays zero.
    public func snapshot() -> LoadPhaseTimes {
        let totals = state.withLock { $0.totalsNS }
        var times = LoadPhaseTimes()
        for (phase, nanoseconds) in totals {
            times[phase] = Double(nanoseconds) / 1_000_000
        }
        return times
    }

    public func reset() {
        state.withLock { $0 = State() }
    }
}

nonisolated extension LoadPhaseRecorder? {
    /// Runs `body` directly when no recorder is attached.
    public func measure<T>(_ phase: LoadPhase, _ body: () throws -> T) rethrows -> T {
        guard let recorder = self else { return try body() }
        return try recorder.measure(phase, body)
    }
}
