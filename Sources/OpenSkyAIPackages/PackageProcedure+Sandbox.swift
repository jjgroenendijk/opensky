// The sandbox procedure: one timed activity after another inside the package's area,
// and meals at the game's meal times. Creation Kit wiki "Sandbox (Procedure)";
// docs/engine/sandbox.md.

import OpenSkyConditions
import OpenSkyWorldInterface
import simd

/// What a sandbox reads from its parameters and from the game settings.
nonisolated public struct PackageSandboxSetup: Equatable, Sendable {
    public var settings: SandboxSettings
    /// The Energy parameter, 0 to 100. A lively actor wanders longer and sits less.
    public var energy: Float = 50
    public var eats = false
    public var usesIdleMarkers = true
    /// Where the actor stood when the procedure started.
    public var start: SIMD3<Float>

    public init(settings: SandboxSettings, start: SIMD3<Float>) {
        self.settings = settings
        self.start = start
    }
}

/// One meal, in game hours since the calendar's start.
nonisolated public struct SandboxMeal: Equatable, Sendable {
    public let start: Double
    public let end: Double
}

nonisolated public struct SandboxProgress: Equatable, Sendable {
    /// The clock at the last `clock` event, in game hours.
    public internal(set) var hours: Double?
    /// Game hours until the current activity ends.
    public internal(set) var hoursLeft: Float = 0
    /// The meals of day `mealDay`, rolled once per day as the wiki describes.
    public internal(set) var meals: [SandboxMeal] = []
    var mealDay: Int?
}

nonisolated extension PackageProcedureMachine {
    private static let hoursPerDay: Double = 24

    private var sandboxSetup: PackageSandboxSetup {
        setup.sandbox ?? PackageSandboxSetup(settings: .vanilla, start: center)
    }

    /// An actor already inside the area starts in place; one outside walks in first.
    mutating func startSandbox() -> [PackageProcedureCommand] {
        guard isInSandboxArea(sandboxSetup.start) else {
            return move(to: nextWanderPoint())
        }
        return beginSandboxActivity(.wandering)
    }

    /// Inside the radius plus `fSandBoxRadiusHysteresis`, and inside the height of the
    /// cylinder the wiki describes.
    func isInSandboxArea(_ point: SIMD3<Float>) -> Bool {
        let settings = sandboxSetup.settings
        let offset = point - center
        let flat = simd_length(SIMD2(offset.x, offset.y))
        return flat <= radius + settings.radiusHysteresis
            && offset.z >= settings.cylinderBottom && offset.z <= settings.cylinderTop
    }

    /// The idle runtime gave the actor a marker, at the end of a walk or while it wandered.
    mutating func handleArrivalAtIdleMarker() -> [PackageProcedureCommand] {
        if state == .sandboxing(.wandering) {
            return beginSandboxActivity(.idleMarker)
        }
        guard state == .moving else { return [] }
        return kind == .sandbox ? beginSandboxActivity(.idleMarker) : handleArrival()
    }

    /// Starts `activity`, or a meal when one is due, and rolls how long it lasts.
    mutating func beginSandboxActivity(_ activity: SandboxActivity) -> [PackageProcedureCommand] {
        let chosen = mealIsDue ? SandboxActivity.eatStanding : activity
        let sandboxSetup = sandboxSetup
        sandbox.hoursLeft = sandboxSetup.settings.duration(
            of: chosen, energy: sandboxSetup.energy, unit: randomUnit()
        )
        state = .sandboxing(chosen)
        return chosen == .eatStanding ? [.playLoop(.eat)] : []
    }

    /// Counts the activity down in game hours. A meal that comes due cuts it short.
    mutating func handleClock(_ hours: Double) -> [PackageProcedureCommand] {
        guard kind == .sandbox else { return [] }
        let elapsed = sandbox.hours.map { max(0, hours - $0) } ?? 0
        sandbox.hours = hours
        rollMeals(day: Int(floor(hours / Self.hoursPerDay)))
        guard case let .sandboxing(activity) = state else { return [] }
        sandbox.hoursLeft -= Float(elapsed)
        let eating = activity == .eatStanding || activity == .eatSitting
        let mealStarts = mealIsDue && !eating
        guard sandbox.hoursLeft <= 0 || mealStarts else { return [] }
        let ended = [PackageProcedureCommand.endActivity(activity)]
        if mealIsDue {
            return ended + beginSandboxActivity(.eatStanding)
        }
        return ended + move(to: nextWanderPoint())
    }

    /// True inside one of today's meals when the package lets the actor eat.
    var mealIsDue: Bool {
        guard sandboxSetup.eats, let now = sandbox.hours else { return false }
        return sandbox.meals.contains { now >= $0.start && now < $0.end }
    }

    private mutating func rollMeals(day: Int) {
        guard sandbox.mealDay != day else { return }
        let settings = sandboxSetup.settings
        sandbox.mealDay = day
        sandbox.meals = settings.meals.map { window in
            let hour = window.earliest + max(0, window.latest - window.earliest) * randomUnit()
            let shortest = settings.mealDuration.lowerBound
            let length = shortest + (settings.mealDuration.upperBound - shortest) * randomUnit()
            let start = Double(day) * Self.hoursPerDay + Double(hour)
            return SandboxMeal(start: start, end: start + Double(length))
        }
    }

    mutating func randomUnit() -> Float {
        Float(random.next() & 0xFFFF) / Float(UInt16.max)
    }
}
