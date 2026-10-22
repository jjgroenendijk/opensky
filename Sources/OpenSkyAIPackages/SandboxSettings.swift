// The sandbox procedure's game settings: how long each activity lasts, when meals are,
// and the shape of the search area. Formulas and defaults from the Creation Kit wiki
// "Sandbox (Procedure)". See docs/engine/sandbox.md.

import OpenSkyGameData

/// What a sandboxing actor does between two choices.
nonisolated public enum SandboxActivity: String, CaseIterable, Equatable, Sendable {
    case furniture
    case idleMarker = "idle marker"
    case eatSitting = "eating sitting"
    case eatStanding = "eating standing"
    case sitting
    case sleeping
    case wandering
}

/// One activity's two settings: `fSandboxDurationMult...` and `fSandboxEnergyMult...`.
nonisolated public struct SandboxActivityScale: Equatable, Sendable {
    public var duration: Float
    public var energy: Float

    public init(duration: Float, energy: Float) {
        self.duration = duration
        self.energy = energy
    }
}

/// A meal's start window, in hours of the day.
nonisolated public struct SandboxMealWindow: Equatable, Sendable {
    public var earliest: Float
    public var latest: Float

    public init(earliest: Float, latest: Float) {
        self.earliest = earliest
        self.latest = latest
    }
}

nonisolated public struct SandboxSettings: Equatable, Sendable {
    /// `fSandboxDurationBase`, in game hours.
    public var durationBase: Float = 0.2
    /// `fSandboxDurationRangeMult`: the duration varies this fraction either way.
    public var durationRange: Float = 0.25
    /// `fSandboxEnergyMult`: scales the procedure's Energy, 0 to 100.
    public var energyMult: Float = 0.05
    public var scales: [SandboxActivity: SandboxActivityScale] = [
        .furniture: SandboxActivityScale(duration: 3, energy: -0.1),
        .idleMarker: SandboxActivityScale(duration: 1.5, energy: -0.05),
        .eatSitting: SandboxActivityScale(duration: 1.5, energy: -0.05),
        .eatStanding: SandboxActivityScale(duration: 1.5, energy: -0.05),
        .sitting: SandboxActivityScale(duration: 2, energy: -0.1),
        .sleeping: SandboxActivityScale(duration: 2, energy: -0.1),
        .wandering: SandboxActivityScale(duration: 0.5, energy: 0.2)
    ]
    /// `fSandboxBreakfast...`, `fSandboxLunch...`, `fSandboxDinner...`, in day order.
    public var meals = [
        SandboxMealWindow(earliest: 6, latest: 9),
        SandboxMealWindow(earliest: 11.5, latest: 12.5),
        SandboxMealWindow(earliest: 18, latest: 19)
    ]
    /// `fSandboxMealDurationMin` and `...Max`, in game hours.
    public var mealDuration: ClosedRange<Float> = 0.1 ... 0.25
    /// `fSandboxCylinderBottom`, negative, and `fSandboxCylinderTop`: the area's height
    /// below and above its centre.
    public var cylinderBottom: Float = -100
    public var cylinderTop: Float = 150
    /// `fSandBoxRadiusHysteresis`: an actor this far outside the radius is still inside.
    public var radiusHysteresis: Float = 50
    /// `fSandBoxInterMarkerMinDist`: the next idle marker is at least this far from the last.
    public var interMarkerMinDistance: Float = 100

    public static let vanilla = Self()

    public init() {}

    /// The game hours one activity lasts, before the random spread.
    public func baseDuration(of activity: SandboxActivity, energy: Float) -> Float {
        let scale = scales[activity] ?? SandboxActivityScale(duration: 1, energy: 0)
        let duration = durationBase * scale.duration * (1 + energy * energyMult * scale.energy)
        return max(0, duration)
    }

    /// `unit` in 0...1 picks a point between `1 - range` and `1 + range` of the base.
    public func duration(of activity: SandboxActivity, energy: Float, unit: Float) -> Float {
        let spread = 1 - durationRange + 2 * durationRange * min(max(unit, 0), 1)
        return baseDuration(of: activity, energy: energy) * spread
    }

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fSandboxDurationBase", into: &settings, \.durationBase)
        store.read("fSandboxDurationRangeMult", into: &settings, \.durationRange)
        store.read("fSandboxEnergyMult", into: &settings, \.energyMult)
        for activity in SandboxActivity.allCases {
            let name = activity.settingName
            var scale = settings.scales[activity] ?? SandboxActivityScale(duration: 1, energy: 0)
            store.read("fSandboxDurationMult" + name, into: &scale, \.duration)
            store.read("fSandboxEnergyMult" + name, into: &scale, \.energy)
            settings.scales[activity] = scale
        }
        for (index, meal) in ["Breakfast", "Lunch", "Dinner"].enumerated() {
            store.read("fSandbox\(meal)Min", into: &settings.meals[index], \.earliest)
            store.read("fSandbox\(meal)Max", into: &settings.meals[index], \.latest)
        }
        var shortest = settings.mealDuration.lowerBound
        var longest = settings.mealDuration.upperBound
        store.read("fSandboxMealDurationMin", into: &shortest, \.self)
        store.read("fSandboxMealDurationMax", into: &longest, \.self)
        settings.mealDuration = min(shortest, longest) ... max(shortest, longest)
        store.read("fSandboxCylinderBottom", into: &settings, \.cylinderBottom)
        store.read("fSandboxCylinderTop", into: &settings, \.cylinderTop)
        store.read("fSandBoxRadiusHysteresis", into: &settings, \.radiusHysteresis)
        store.read("fSandBoxInterMarkerMinDist", into: &settings, \.interMarkerMinDistance)
        return settings
    }
}

nonisolated extension SandboxActivity {
    /// The suffix of the activity's `fSandboxDurationMult` and `fSandboxEnergyMult` settings.
    var settingName: String {
        switch self {
        case .furniture: "Furniture"
        case .idleMarker: "IdleMarker"
        case .eatSitting: "EatSitting"
        case .eatStanding: "EatStanding"
        case .sitting: "Sitting"
        case .sleeping: "Sleeping"
        case .wandering: "Wandering"
        }
    }
}
