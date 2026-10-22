// How often a Guard procedure warns an intruder before it attacks, from `iGuardWarnings`
// and `fWarningTimer` (<https://ck.uesp.net/wiki/Guard_(Procedure)>). That
// `fWarningTimer` is the wait between two warnings is OpenSky's reading of its name.

import OpenSkyGameData

nonisolated public struct GuardWarningSettings: Equatable, Sendable {
    /// `iGuardWarnings`: the most warnings a guard gives before it attacks.
    public var warnings = 2
    /// `fWarningTimer`: seconds between two warnings.
    public var warningSeconds: Float = 5

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("iGuardWarnings", into: &settings, \.warnings)
        store.read("fWarningTimer", into: &settings, \.warningSeconds)
        return settings
    }
}
