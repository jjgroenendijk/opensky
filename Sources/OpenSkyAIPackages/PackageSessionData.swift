public import OpenSkyConditions
public import OpenSkyWorldInterface

/// The load order's packages and the game settings the procedures read. The
/// settings default to the vanilla values.
public struct PackageSessionData {
    public var store: PackageStore
    /// The condition functions package conditions run on.
    public var conditionFunctions: ConditionFunctionRegistry
    public var guardWarnings = GuardWarningSettings.vanilla
    public var sandboxSettings = SandboxSettings.vanilla
    public var bumpSettings = BumpReactionSettings.vanilla
    public var followSettings = FollowSettings.vanilla

    public init(store: PackageStore, conditionFunctions: ConditionFunctionRegistry) {
        self.store = store
        self.conditionFunctions = conditionFunctions
    }
}
