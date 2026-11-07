// The ordered steps of one per-frame hook. The phase enum declares the order,
// so the order of the wiring statements cannot change the simulation, and a
// system registered late still runs in its own slot.

import Foundation
import OpenSkyFormatsCore

nonisolated private let frameScheduleLog = EngineLogger(
    subsystem: "nl.jjgroenendijk.opensky",
    category: "FrameSchedule"
)

/// One step slot in a frame hook. The raw value is the run order.
public protocol FramePhase: CaseIterable, Hashable, Sendable, RawRepresentable
    where RawValue == Int {}

/// Runs one step per phase, in phase order. Each phase takes one step only, so a
/// second registration is a wiring bug: it is logged as a fault and dropped.
public final class FrameSchedule<Phase: FramePhase, Value> {
    private var steps: [(phase: Phase, run: (Value) -> Void)] = []

    public init() {}

    public var registeredPhases: [Phase] {
        steps.map(\.phase)
    }

    public var isEmpty: Bool {
        steps.isEmpty
    }

    public func register(_ phase: Phase, _ step: @escaping (Value) -> Void) {
        guard !steps.contains(where: { $0.phase == phase }) else {
            frameScheduleLog
                .fault("frame phase \(phase) registered twice; the second step is dropped")
            return
        }
        let index = steps.firstIndex { $0.phase.rawValue > phase.rawValue } ?? steps.count
        steps.insert((phase, step), at: index)
    }

    public func callAsFunction(_ value: Value) {
        for step in steps {
            step.run(value)
        }
    }
}
