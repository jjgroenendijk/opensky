// Minimal deterministic AI-package procedure machines (issue #201). Movement
// commands feed the existing MoveToPointControl/NPC mover; animation commands
// are explicit seams for the sleep/eat loop clips.

import simd

nonisolated enum PackageLoopClip: String, Equatable, Sendable {
    case sleep
    case eat
}

nonisolated enum PackageProcedureState: Equatable, Sendable {
    case ready
    case moving
    case idleStop(secondsRemaining: Float)
    case looping(PackageLoopClip)
    case complete
    case failed
}

nonisolated enum PackageProcedureCommand: Equatable, Sendable {
    case move(to: SIMD3<Float>)
    case playLoop(PackageLoopClip)
    case stopLoop
}

nonisolated enum PackageProcedureEvent: Equatable, Sendable {
    case arrived
    case movementFailed
    case tick(Float)
}

nonisolated struct PackageProcedureMachine: Equatable, Sendable {
    private static let wanderIdleSeconds: Float = 1
    private static let sandboxIdleSeconds: Float = 4

    let kind: PackageProcedureKind
    let center: SIMD3<Float>
    let destination: SIMD3<Float>?
    let radius: Float
    private(set) var state: PackageProcedureState = .ready
    private var random: ConditionRandom

    init(
        kind: PackageProcedureKind,
        center: SIMD3<Float>,
        destination: SIMD3<Float>? = nil,
        radius: Float,
        seed: UInt64
    ) {
        self.kind = kind
        self.center = center
        self.destination = destination
        self.radius = max(0, radius)
        random = ConditionRandom(seed: seed)
    }

    mutating func start() -> [PackageProcedureCommand] {
        guard state == .ready else { return [] }
        switch kind {
        case .travel, .sleep, .eat:
            state = .moving
            return [.move(to: destination ?? center)]
        case .wander, .sandbox:
            state = .moving
            return [.move(to: nextWanderPoint())]
        case .unsupported:
            state = .failed
            return []
        }
    }

    mutating func handle(_ event: PackageProcedureEvent) -> [PackageProcedureCommand] {
        switch event {
        case .movementFailed:
            state = .failed
            return []
        case .arrived:
            return handleArrival()
        case let .tick(delta):
            return handleTick(max(0, delta))
        }
    }

    private mutating func handleArrival() -> [PackageProcedureCommand] {
        guard state == .moving else { return [] }
        switch kind {
        case .travel:
            state = .complete
            return []
        case .sleep:
            state = .looping(.sleep)
            return [.playLoop(.sleep)]
        case .eat:
            state = .looping(.eat)
            return [.playLoop(.eat)]
        case .wander:
            state = .idleStop(secondsRemaining: Self.wanderIdleSeconds)
            return []
        case .sandbox:
            state = .idleStop(secondsRemaining: Self.sandboxIdleSeconds)
            return []
        case .unsupported:
            state = .failed
            return []
        }
    }

    private mutating func handleTick(_ delta: Float) -> [PackageProcedureCommand] {
        guard case let .idleStop(remaining) = state else { return [] }
        let next = remaining - delta
        guard next <= 0 else {
            state = .idleStop(secondsRemaining: next)
            return []
        }
        state = .moving
        return [.move(to: nextWanderPoint())]
    }

    private mutating func nextWanderPoint() -> SIMD3<Float> {
        let angleUnit = Float(random.next() & 0xFFFF) / Float(UInt16.max)
        let radiusUnit = Float(random.next() & 0xFFFF) / Float(UInt16.max)
        let angle = angleUnit * 2 * Float.pi
        let distance = radius * radiusUnit.squareRoot()
        return center + SIMD3(cos(angle) * distance, sin(angle) * distance, 0)
    }
}
