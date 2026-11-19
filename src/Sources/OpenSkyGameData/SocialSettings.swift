// The game settings of random conversations and of watching a fight, with the
// `Skyrim.esm` values as fallbacks. See docs/engine/random-conversations.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct SocialSettings: Equatable, Sendable {
    /// Game units. A partner further away is not considered.
    public var radius: Float
    public var interiorRadius: Float
    /// Seconds between one actor's tries, rolled between the two.
    public var timerMin: Float
    public var timerMax: Float
    /// Game units. A scene's pair closer than this talks without a walk.
    public var triggerDistance: Float
    /// Percent chance that a watcher of a fight comments.
    public var observeCombatChance: Float
    /// Seconds a watcher remembers a fighter it no longer sees fight.
    public var spectatorRememberSeconds: Float

    public static let documentedDefaults = SocialSettings(
        radius: 500, interiorRadius: 500, timerMin: 10, timerMax: 30, triggerDistance: 200,
        observeCombatChance: 10, spectatorRememberSeconds: 5
    )

    public init(
        radius: Float, interiorRadius: Float, timerMin: Float, timerMax: Float,
        triggerDistance: Float, observeCombatChance: Float, spectatorRememberSeconds: Float
    ) {
        self.radius = radius
        self.interiorRadius = interiorRadius
        self.timerMin = timerMin
        self.timerMax = max(timerMin, timerMax)
        self.triggerDistance = triggerDistance
        self.observeCombatChance = observeCombatChance
        self.spectatorRememberSeconds = spectatorRememberSeconds
    }

    public static func resolve(store: GameSettingStore) -> SocialSettings {
        var settings = documentedDefaults
        func read(_ editorID: String, _ keyPath: WritableKeyPath<SocialSettings, Float>) {
            let value: Float? = switch store.setting(editorID: editorID)?.setting.value {
            case let .float(number)?: number
            case let .integer(number)?: Float(number)
            default: nil
            }
            if let value, value.isFinite, value >= 0 {
                settings[keyPath: keyPath] = value
            }
        }
        read("fAISocialRadiusToTriggerConversation", \.radius)
        read("fAISocialRadiusToTriggerConversationInterior", \.interiorRadius)
        read("fAISocialTimerForConversationsMin", \.timerMin)
        read("fAISocialTimerForConversationsMax", \.timerMax)
        read("iAISocialDistanceToTriggerEvent", \.triggerDistance)
        read("fAISocialchanceForConversation", \.observeCombatChance)
        read("fAISpectatorRememberThreatTimer", \.spectatorRememberSeconds)
        settings.timerMax = max(settings.timerMin, settings.timerMax)
        return settings
    }
}
