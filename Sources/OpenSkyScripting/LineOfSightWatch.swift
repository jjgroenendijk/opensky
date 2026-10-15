// The line-of-sight registrations of `RegisterForLOS`, `RegisterForSingleLOSGain`, and
// `RegisterForSingleLOSLost`, and the events one check of every pair produces. Pure: the
// bridge answers whether a viewer sees a target. See
// docs/engine/papyrus-registrations.md#line-of-sight.

import Foundation
import OpenSkyFormatsESM
import OpenSkyScriptingInterface
import simd

nonisolated public struct LineOfSightWatch: Equatable, Sendable {
    public enum Mode: Equatable, Sendable {
        /// Every gain and every loss.
        case both
        /// The first gain, then the registration ends.
        case singleGain
        /// The first loss, then the registration ends.
        case singleLost
    }

    public struct Pair: Hashable, Comparable, Sendable {
        public let viewer: ReferenceKey
        public let target: ReferenceKey

        public init(viewer: ReferenceKey, target: ReferenceKey) {
            self.viewer = viewer
            self.target = target
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            (lhs.viewer, lhs.target) < (rhs.viewer, rhs.target)
        }
    }

    public struct Event: Equatable, Sendable {
        public let instance: PapyrusInstanceKey
        public let pair: Pair
        public let gained: Bool
    }

    private struct Entry: Equatable, Sendable {
        var mode: Mode
        /// Nil until the first check, so `both` reports the state it starts in.
        var sees: Bool?
    }

    private var entries: [PapyrusInstanceKey: [Pair: Entry]] = [:]

    public init() {}

    public var isEmpty: Bool {
        entries.isEmpty
    }

    /// A new registration for the same pair replaces the old one.
    public mutating func register(_ instance: PapyrusInstanceKey, _ pair: Pair, mode: Mode) {
        entries[instance, default: [:]][pair] = Entry(mode: mode)
    }

    public mutating func unregister(_ instance: PapyrusInstanceKey, _ pair: Pair) {
        entries[instance]?[pair] = nil
        if entries[instance]?.isEmpty == true {
            entries[instance] = nil
        }
    }

    /// Checks every pair once, in a fixed order. A pair `sees` cannot answer keeps its
    /// state. Instances `isLive` rejects lose their registrations.
    public mutating func step(
        isLive: (PapyrusInstanceKey) -> Bool,
        sees: (Pair) -> Bool?
    ) -> [Event] {
        var events: [Event] = []
        for instance in entries.keys.sorted() {
            guard isLive(instance) else {
                entries[instance] = nil
                continue
            }
            for pair in entries[instance, default: [:]].keys.sorted() {
                guard var entry = entries[instance]?[pair], let now = sees(pair) else { continue }
                let changed = entry.sees != now
                entry.sees = now
                entries[instance]?[pair] = entry
                guard changed else { continue }
                switch entry.mode {
                case .both:
                    events.append(Event(instance: instance, pair: pair, gained: now))
                case .singleGain where now, .singleLost where !now:
                    events.append(Event(instance: instance, pair: pair, gained: now))
                    unregister(instance, pair)
                default:
                    continue
                }
            }
        }
        return events
    }
}

nonisolated extension LineOfSightWatch {
    /// The camera's view, for the player as viewer: its axes and the tangents of half the
    /// field of view across and up.
    public struct View: Equatable, Sendable {
        public let forward: SIMD3<Float>
        public let right: SIMD3<Float>
        public let up: SIMD3<Float>
        public let tanHalfWidth: Float
        public let tanHalfHeight: Float

        public init(
            forward: SIMD3<Float>, right: SIMD3<Float>, up: SIMD3<Float>,
            tanHalfWidth: Float, tanHalfHeight: Float
        ) {
            self.forward = forward
            self.right = right
            self.up = up
            self.tanHalfWidth = tanHalfWidth
            self.tanHalfHeight = tanHalfHeight
        }

        /// True when `offset`, from the eye to the target, falls inside the view.
        public func contains(_ offset: SIMD3<Float>) -> Bool {
            let depth = simd_dot(offset, forward)
            guard depth > 0 else { return false }
            return abs(simd_dot(offset, right)) <= depth * tanHalfWidth
                && abs(simd_dot(offset, up)) <= depth * tanHalfHeight
        }
    }
}
