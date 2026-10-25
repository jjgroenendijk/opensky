import OpenSkyFormatsESM

/// The load order's packages and the game settings the procedures read. The
/// settings default to the vanilla values.
public struct PackageSessionData {
    public var store: PackageStore
    public var guardWarnings = GuardWarningSettings.vanilla
    public var sandboxSettings = SandboxSettings.vanilla
    public var bumpSettings = BumpReactionSettings.vanilla
    public var followSettings = FollowSettings.vanilla

    public init(store: PackageStore) {
        self.store = store
    }
}
