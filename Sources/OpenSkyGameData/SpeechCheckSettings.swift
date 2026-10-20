// The bribe price and the intimidation check, from UESP "Skyrim:Speech" (Bribe and
// Intimidate formulas). Skyrim.esm sets only the three `fBribe` costs; the other
// fallbacks are the game's defaults from <https://ck.uesp.net/wiki/Category:Settings>.
// See docs/engine/speech-checks.md.

import Foundation
import OpenSkyFormatsESM

nonisolated public struct SpeechCheckSettings: Equatable, Sendable {
    public var bribeCostCurve: Float = 1.4
    public var bribeScale: Float = 0.5
    public var bribeSpeechcraftMult: Float = 0.1
    public var bribeMoralityMult: Float = 1
    public var bribeNPCLevelMult: Float = 0.1
    public var intimidateSpeechcraftCurve: Float = 1.5
    /// By the `Confidence` actor value: cowardly, cautious, average, brave, foolhardy.
    /// A coward yields to anyone; 100 makes a foolhardy actor all but fearless.
    public var intimidateConfidenceMults: [Float] = [0, 0.5, 1, 1.5, 100]

    public static let fallback = SpeechCheckSettings()

    public init() {}

    public static func resolve(store: GameSettingStore) -> SpeechCheckSettings {
        var settings = fallback
        func read(_ editorID: String) -> Float? {
            let value: Float? = switch store.setting(editorID: editorID)?.setting.value {
            case let .float(number)?: number
            case let .integer(number)?: Float(number)
            default: nil
            }
            return value.flatMap { $0.isFinite && $0 >= 0 ? $0 : nil }
        }
        settings.bribeCostCurve = read("fBribeCostCurve") ?? settings.bribeCostCurve
        settings.bribeScale = read("fBribeScale") ?? settings.bribeScale
        settings.bribeSpeechcraftMult = read("fBribeSpeechcraftMult")
            ?? settings.bribeSpeechcraftMult
        settings.bribeMoralityMult = read("fBribeMoralityMult") ?? settings.bribeMoralityMult
        settings.bribeNPCLevelMult = read("fBribeNPCLevelMult") ?? settings.bribeNPCLevelMult
        settings.intimidateSpeechcraftCurve = read("fIntimidateSpeechcraftCurve")
            ?? settings.intimidateSpeechcraftCurve
        let confidence = ["Cowardly", "Cautious", "Average", "Brave", "Foolhardy"]
        for (index, name) in confidence.enumerated() {
            if let mult = read("fIntimidateConfidenceMult\(name)") {
                settings.intimidateConfidenceMults[index] = mult
            }
        }
        return settings
    }

    /// The gold a bribe costs, before the `Mod Bribe Amount` perk entry point.
    public func bribeAmount(_ check: SpeechCheckActors) -> Float {
        let morality = check.npcMorality * bribeMoralityMult + 1
        let speech = (check.playerSpeech - check.npcSpeech - 100) * bribeSpeechcraftMult
        let base = max(0, check.npcLevel * bribeNPCLevelMult + check.playerLevel - speech)
        return (pow(base, bribeCostCurve) * bribeScale * morality).rounded()
    }

    /// True when the player is scarier than the actor. `playerFactor` is the
    /// `Mod Player Intimidation` perk entry point, applied to the player's side.
    public func intimidates(_ check: SpeechCheckActors, playerFactor: Float = 1) -> Bool {
        let edge = max(-1, (check.playerSpeech - check.npcSpeech) / 100)
        let player = check.playerLevel * pow(1 + edge, intimidateSpeechcraftCurve) * playerFactor
        let confidence = min(max(Int(check.npcConfidence), 0), intimidateConfidenceMults.count - 1)
        return player > check.npcLevel * intimidateConfidenceMults[confidence]
    }
}

/// The two sides of one speech check.
nonisolated public struct SpeechCheckActors: Equatable, Sendable {
    public var playerLevel: Float
    public var playerSpeech: Float
    public var npcLevel: Float
    public var npcSpeech: Float
    public var npcMorality: Float
    public var npcConfidence: Float

    public init(
        playerLevel: Float, playerSpeech: Float, npcLevel: Float, npcSpeech: Float,
        npcMorality: Float, npcConfidence: Float
    ) {
        self.playerLevel = playerLevel
        self.playerSpeech = playerSpeech
        self.npcLevel = npcLevel
        self.npcSpeech = npcSpeech
        self.npcMorality = npcMorality
        self.npcConfidence = npcConfidence
    }
}
