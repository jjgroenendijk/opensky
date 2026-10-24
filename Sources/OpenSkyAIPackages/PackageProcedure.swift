// Deterministic AI procedure machines, one per running procedure. Movement commands
// feed the NPC mover; other acts go to the world as `PackageAction`s.
// docs/engine/package-schedules.md, "Procedure machines".

import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyPhysics
import OpenSkyWorldInterface
import simd

nonisolated public enum PackageLoopClip: String, Equatable, Sendable {
    case eat
}

nonisolated public enum PackageProcedureState: Equatable, Sendable {
    case ready
    case moving
    case idleStop(secondsRemaining: Float)
    case looping(PackageLoopClip)
    /// The actor sits in its furniture. A sit package is done here.
    case seated
    /// Holds here until a timer, a sense, or another package moves it on.
    case waiting
    /// A find found nothing yet and looks again after this many seconds.
    case searching(retrySeconds: Float)
    /// Waits for the world to finish an act, such as a spoken line.
    case acting(secondsRemaining: Float?)
    /// A sandbox does one activity until its game-hour timer runs out.
    case sandboxing(SandboxActivity)
    case complete
    case failed
}

nonisolated public enum PackageProcedureCommand: Equatable, Sendable {
    case move(to: SIMD3<Float>)
    /// The gait the next moves use, over the package's own; nil gives it back.
    case pace(LocomotionGait?)
    case playLoop(PackageLoopClip)
    /// Seat the actor in the furniture its package names.
    case sit
    case act(PackageAction)
    /// Stop walking where the actor is.
    case stop
    /// A sandbox activity's time ran out; the world lets go of what it used.
    case endActivity(SandboxActivity)
    /// A sandbox wants a free seat in its area; the world answers with `seatOffered`.
    case seekSeat(SandboxSeatRequest)
}

nonisolated public enum PackageProcedureEvent: Equatable, Sendable {
    case arrived
    /// A sandbox walk ended because the idle runtime gave the actor an idle marker.
    case arrivedAtIdleMarker
    case movementFailed
    case tick(Float)
    case acted(PackageActionResult)
    case sensed(PackageSenses)
    /// The game clock, in game hours since the calendar's start.
    case clock(hours: Double)
    /// The seat the world reserved for a sandbox, or nil when it found none.
    case seatOffered(PackageSeat?)
}

/// What one procedure needs, read from its parameters by `PackageProcedureInputs`.
nonisolated public struct PackageProcedureSetup: Equatable, Sendable {
    public var kind: PackageProcedureKind
    public var center: SIMD3<Float>
    public var destination: SIMD3<Float>?
    public var radius: Float
    /// Patrol points after the first, in walking order.
    public var path: [SIMD3<Float>] = []
    public var repeats = false
    public var seed: UInt64 = 0
    /// The references it acts on, in order. Acquire tries the next one when one fails.
    public var targets: [ReferenceKey] = []
    /// The reference it follows, flees, or greets.
    public var watched: ReferenceKey?
    public var topic: FormID?
    /// The thing a find, a cast, or a shout selects.
    public var selector: Package.Target?
    /// A wait's time; zero waits for ever.
    public var seconds: Float = 0
    /// Follow's minimum radius; Escort's follow distance.
    public var near: Float = 0
    /// Follow's maximum radius, Flee's distance, Orbit's outer radius.
    public var far: Float = 0
    public var height: Float = 0
    /// Lock rather than unlock; repeat fire; flee from a reference rather than to a place.
    public var flag = false
    /// UseWeapon's "Allow Combat Start" input.
    public var startsCombat = false
    /// False when the procedure has no place or target to walk to, so it acts where it is.
    public var walks = true
    /// A Guard procedure's warning count and spacing, from the install.
    public var guardWarnings = GuardWarningSettings.vanilla
    public var sandbox: PackageSandboxSetup?

    public init(
        kind: PackageProcedureKind, center: SIMD3<Float>, destination: SIMD3<Float>? = nil,
        radius: Float = 0
    ) {
        self.kind = kind
        self.center = center
        self.destination = destination
        self.radius = max(0, radius)
    }
}

nonisolated public struct PackageProcedureMachine: Equatable, Sendable {
    static let wanderIdleSeconds: Float = 1
    static let findRetrySeconds: Float = 2
    /// How far a watched reference may move before a follower walks again.
    static let followSlack: Float = 128
    /// How close a greeter walks to the player before it speaks.
    static let greetDistance: Float = 150
    /// `fFollowStartSprintDistance`: a follower this far behind sprints to catch up.
    static let followSprintDistance: Float = 300

    public let setup: PackageProcedureSetup
    /// Times a repeatable patrol went back to its first point.
    public internal(set) var laps = 0
    public internal(set) var state: PackageProcedureState = .ready
    public internal(set) var pathIndex = 0
    /// What a find found, for the object list it fills.
    public internal(set) var found: [ReferenceKey] = []
    var random: ConditionRandom
    var timer: Float?
    var targetIndex = 0
    /// Where the last move went, so a follower walks again only when its target moved.
    var lastGoal: SIMD3<Float>?
    /// The gait a follower last asked for.
    var pace: LocomotionGait?
    /// The warnings a guard gave the intruder now in its warn radius.
    public internal(set) var warnings = 0
    var warnCooldown: Float = 0
    public internal(set) var sandbox = SandboxProgress()

    public var kind: PackageProcedureKind {
        setup.kind
    }

    public var center: SIMD3<Float> {
        setup.center
    }

    public var destination: SIMD3<Float>? {
        setup.destination
    }

    public var radius: Float {
        setup.radius
    }

    public var path: [SIMD3<Float>] {
        setup.path
    }

    public var repeats: Bool {
        setup.repeats
    }

    public var isFinished: Bool {
        state == .complete || state == .failed
    }

    public init(setup: PackageProcedureSetup) {
        self.setup = setup
        random = ConditionRandom(seed: setup.seed)
    }

    public init(
        kind: PackageProcedureKind,
        center: SIMD3<Float>,
        destination: SIMD3<Float>? = nil,
        radius: Float,
        path: [SIMD3<Float>] = [],
        repeats: Bool = false,
        seed: UInt64
    ) {
        var setup = PackageProcedureSetup(
            kind: kind, center: center, destination: destination, radius: radius
        )
        setup.path = path
        setup.repeats = repeats
        setup.seed = seed
        self.init(setup: setup)
    }

    public mutating func handle(_ event: PackageProcedureEvent) -> [PackageProcedureCommand] {
        guard !isFinished else { return [] }
        switch event {
        case .movementFailed:
            guard state == .moving else { return [] }
            return handleMovementFailure()
        case .arrived:
            guard state == .moving else { return [] }
            return handleArrival()
        case .arrivedAtIdleMarker:
            return handleArrivalAtIdleMarker()
        case let .clock(hours):
            return handleClock(hours)
        case let .seatOffered(seat):
            return handleSeatOffer(seat)
        case let .tick(delta):
            return handleTick(max(0, delta))
        case let .acted(result):
            return handleResult(result)
        case let .sensed(senses):
            return handleSenses(senses)
        }
    }

    mutating func move(to point: SIMD3<Float>) -> [PackageProcedureCommand] {
        state = .moving
        lastGoal = point
        return [.move(to: point)]
    }

    mutating func act(_ action: PackageAction) -> [PackageProcedureCommand] {
        state = .acting(secondsRemaining: nil)
        return [.act(action)]
    }

    /// A sandbox never completes, so it waits where it stands and then tries a new point.
    private mutating func handleMovementFailure() -> [PackageProcedureCommand] {
        if kind == .sandbox {
            return leaveSandboxSeat() + beginSandboxActivity(.wandering)
        }
        state = .failed
        return []
    }

    private mutating func handleTick(_ delta: Float) -> [PackageProcedureCommand] {
        warnCooldown = max(0, warnCooldown - delta)
        switch state {
        case let .idleStop(remaining):
            guard remaining - delta <= 0 else {
                state = .idleStop(secondsRemaining: remaining - delta)
                return []
            }
            return move(to: nextWanderPoint())
        case let .searching(retry):
            guard retry - delta <= 0 else {
                state = .searching(retrySeconds: retry - delta)
                return []
            }
            return start()
        case let .acting(remaining?):
            state = remaining - delta <= 0 ? stateAfterAct :
                .acting(secondsRemaining: remaining - delta)
            return []
        case .waiting:
            guard let left = timer else { return [] }
            timer = left - delta
            if left - delta <= 0 {
                state = .complete
            }
            return []
        default:
            return []
        }
    }

    private mutating func handleResult(_ result: PackageActionResult) -> [PackageProcedureCommand] {
        guard state == .acting(secondsRemaining: nil) else { return [] }
        switch result {
        case .done:
            state = stateAfterAct
            return []
        case let .lasts(seconds):
            state = seconds > 0 ? .acting(secondsRemaining: seconds) : stateAfterAct
            return []
        case let .found(references):
            guard !references.isEmpty else {
                state = .searching(retrySeconds: Self.findRetrySeconds)
                return []
            }
            found = references
            state = .complete
            return []
        case .failed where kind == .guardArea:
            // A guard with no trespass line still counts the warning.
            state = .waiting
            return []
        case .failed:
            return retryNextTarget()
        }
    }

    /// A guard and a repeating UseWeapon keep holding after each act.
    private var stateAfterAct: PackageProcedureState {
        kind == .guardArea || (kind == .useWeapon && setup.flag) ? .waiting : .complete
    }

    /// Acquire takes the next item of its list when one cannot be picked up.
    private mutating func retryNextTarget() -> [PackageProcedureCommand] {
        guard kind == .acquire, targetIndex + 1 < setup.targets.count else {
            state = .failed
            return []
        }
        targetIndex += 1
        state = .ready
        return start()
    }

    mutating func nextWanderPoint() -> SIMD3<Float> {
        let angleUnit = Float(random.next() & 0xFFFF) / Float(UInt16.max)
        let radiusUnit = Float(random.next() & 0xFFFF) / Float(UInt16.max)
        let angle = angleUnit * 2 * Float.pi
        let distance = radius * radiusUnit.squareRoot()
        return center + SIMD3(cos(angle) * distance, sin(angle) * distance, 0)
    }
}
