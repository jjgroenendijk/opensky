// The idle settings: how near an idle marker counts as there, and the pause between
// two idles. See docs/engine/idle-runtime.md.

public import OpenSkyGameData

nonisolated public struct IdleMarkerSettings: Equatable, Sendable {
    /// `fAIMarkerDestinationRadius`: an actor this close to a marker has arrived.
    public var arrivalRadius: Float = 50
    /// `fAIIdleWaitTime`: seconds between one idle ending and the next being picked.
    public var idleWait: Float = 0.1

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        store.read("fAIMarkerDestinationRadius", into: &settings, \.arrivalRadius)
        store.read("fAIIdleWaitTime", into: &settings, \.idleWait)
        return settings
    }
}
