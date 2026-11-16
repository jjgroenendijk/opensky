// The speeds one actor moves at this step: its movement type, the race's override, and the
// adjustments for the speed multiplier, worn weight, and running.
// See docs/engine/navigation.md#npc-path-following.

public import OpenSkyFormatsESM

nonisolated public struct ActorMovementSpeeds: Equatable, Sendable {
    /// The movement type's speeds, or the race's override of them; nil keeps the default type.
    public var speeds: MovementType.Speeds?
    /// `|SpeedMult|` over 100.
    public var multiplier: Float = 1
    /// The share of a run speed that worn weight leaves; a run never drops below the walk.
    public var runShare: Float = 1
    /// False turns a run into a walk.
    public var canRun = true

    public init(
        speeds: MovementType.Speeds? = nil,
        multiplier: Float = 1,
        runShare: Float = 1,
        canRun: Bool = true
    ) {
        self.speeds = speeds
        self.multiplier = multiplier
        self.runShare = runShare
        self.canRun = canRun
    }

    /// `|SpeedMult|` over 100. A value of 0 counts as 100, so an actor without one still moves.
    public static func multiplier(speedMult: Float) -> Float {
        guard speedMult.isFinite, speedMult != 0 else { return 1 }
        return abs(speedMult) / 100
    }

    /// The speeds a race uses for `type`: its override pair when it has one for that type.
    public static func speeds(of type: MovementType, race: RaceDetails?) -> MovementType.Speeds? {
        race?.movementOverride(forType: type.formID) ?? type.speeds
    }

    /// A run speed after worn weight: its share of the run, but never slower than the walk.
    /// Without the right to run, it is the walk.
    public func run(_ run: Float, walk: Float) -> Float {
        guard canRun else { return walk }
        return runShare >= 0 ? max(runShare * run, walk) : run
    }
}
