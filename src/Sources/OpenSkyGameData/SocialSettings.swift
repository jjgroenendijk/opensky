// When NPCs start random conversations: the GMSTs the Creation Kit's Scenes page
// lists under "Controlling Random Conversations". The fallbacks are that page's
// values; Skyrim.esm overrides most of them. See docs/engine/random-conversations.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct SocialSettings: Equatable, Sendable {
    /// Game units. A target further away is not considered.
    public var radius: Float
    public var interiorRadius: Float
    /// Percent chance per attempt.
    public var chance: Float
    public var interiorChance: Float
    /// Seconds between one actor's attempts, rolled between the two.
    public var timerMin: Float
    public var timerMax: Float
    /// Game units. The pair must be this close for the event to fire.
    public var triggerDistance: Float
    /// Seconds before an actor talks to the same actor again.
    public var sameActorSeconds: Float

    public static let documentedDefaults = SocialSettings(
        radius: 2000, interiorRadius: 1000, chance: 25, interiorChance: 25,
        timerMin: 30, timerMax: 60, triggerDistance: 120, sameActorSeconds: 120
    )

    public init(
        radius: Float, interiorRadius: Float, chance: Float, interiorChance: Float,
        timerMin: Float, timerMax: Float, triggerDistance: Float, sameActorSeconds: Float
    ) {
        self.radius = radius
        self.interiorRadius = interiorRadius
        self.chance = chance
        self.interiorChance = interiorChance
        self.timerMin = timerMin
        self.timerMax = max(timerMin, timerMax)
        self.triggerDistance = triggerDistance
        self.sameActorSeconds = sameActorSeconds
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
        read("fAISocialchanceForConversation", \.chance)
        read("fAISocialchanceForConversationInterior", \.interiorChance)
        read("fAISocialTimerForConversationsMin", \.timerMin)
        read("fAISocialTimerForConversationsMax", \.timerMax)
        read("iAISocialDistanceToTriggerEvent", \.triggerDistance)
        read("fAItalktosameNPCTimer", \.sameActorSeconds)
        settings.timerMax = max(settings.timerMin, settings.timerMax)
        return settings
    }
}
