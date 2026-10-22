// How often a Guard procedure warns an intruder before it attacks, from `iGuardWarnings`
// and `fAITrespassWarningTimer` (<https://ck.uesp.net/wiki/Guard_(Procedure)>).

import OpenSkyGameData

nonisolated public struct GuardWarningSettings: Equatable, Sendable {
    /// `iGuardWarnings`: the most warnings a guard gives before it attacks.
    public var warnings = 2
    /// `fAITrespassWarningTimer`: "the time between warnings on a Trespass Package or Guard
    /// Package" (<https://ck.uesp.net/wiki/FAITrespassWarningTimer>).
    public var warningSeconds: Float = 5

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("iGuardWarnings", into: &settings, \.warnings)
        store.read("fAITrespassWarningTimer", into: &settings, \.warningSeconds)
        return settings
    }
}
