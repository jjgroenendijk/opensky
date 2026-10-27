// The `Actor.PathToReference` calls that wait for their actor to stop walking
// (<https://ck.uesp.net/wiki/PathToReference_-_Actor>). Pure: the caller passes the
// movement readouts each frame.

import OpenSkyFormatsESM
import OpenSkyPhysics

nonisolated public struct ScriptPathWaits: Equatable, Sendable {
    private var actors: [UInt64: ReferenceKey] = [:]

    public init() {}

    /// The gait for `afWalkRunPercent`. OpenSky has walk and run speeds only, so the
    /// half way point picks one.
    public static func gait(forSpeed speed: Float) -> LocomotionGait {
        speed < 0.5 ? .walk : .run
    }

    public mutating func wait(_ token: UInt64, for actor: ReferenceKey) {
        actors[token] = actor
    }

    /// Drops the waits whose walk ended. True when the actor arrived; false when it
    /// gave up, was stopped or pushed, or left the loaded cells.
    public mutating func settle(_ readouts: [NPCMovementReadout]) -> [UInt64: Bool] {
        let states = Dictionary(readouts.map { ($0.actor, $0.state) }) { first, _ in first }
        var answers: [UInt64: Bool] = [:]
        for (token, actor) in actors {
            guard let arrived = Self.outcome(of: states[actor]) else { continue }
            answers[token] = arrived
            actors[token] = nil
        }
        return answers
    }

    public var count: Int {
        actors.count
    }

    private static func outcome(of state: NPCMovementState?) -> Bool? {
        switch state {
        case .moving, .awaitingRepath, .turning:
            nil
        case .arrived:
            true
        case nil, .gaveUp, .halted, .facing, .ridden, .knockedBack:
            false
        }
    }
}
