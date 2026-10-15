// The speech checks a response tests, indices from xEdit wbDefinitionsTES5.pas: 654
// `GetBribeSuccess` and 655 `GetIntimidateSuccess`. The run-on is the actor the player
// talks to. See docs/engine/speech-checks.md.

import Foundation
import OpenSkyConditions
import OpenSkyFormatsESM
import OpenSkyGameData

/// What the speech checks need beside the two actors' values.
nonisolated public struct SpeechCheckResolution: ConditionResolution, Equatable {
    public var settings: SpeechCheckSettings?
    /// Gold the player carries. Nil without an inventory.
    public var playerGold: Int?
    /// The `Mod Player Intimidation` and `Mod Bribe Amount` perk entry points, as a factor.
    public var intimidationFactor: Float = 1
    public var bribeFactor: Float = 1

    public static let empty = SpeechCheckResolution()

    public init(
        settings: SpeechCheckSettings? = nil, playerGold: Int? = nil,
        intimidationFactor: Float = 1, bribeFactor: Float = 1
    ) {
        self.settings = settings
        self.playerGold = playerGold
        self.intimidationFactor = intimidationFactor
        self.bribeFactor = bribeFactor
    }
}

nonisolated extension ConditionContext {
    public var speechChecks: SpeechCheckResolution {
        get { self[resolution: SpeechCheckResolution.self] }
        set { self[resolution: SpeechCheckResolution.self] = newValue }
    }
}

/// Actor value indices the checks read (UESP "Actor Value Indices").
nonisolated public enum SpeechCheckValues {
    public static let confidence: Int32 = 1
    public static let morality: Int32 = 3
    public static let speechcraft: Int32 = 17

    public static func actors(
        player: some ActorValueReadable, playerLevel: Int,
        npc: some ActorValueReadable, npcLevel: Int
    ) -> SpeechCheckActors {
        SpeechCheckActors(
            playerLevel: Float(playerLevel),
            playerSpeech: player.value(at: speechcraft) ?? 0,
            npcLevel: Float(npcLevel),
            npcSpeech: npc.value(at: speechcraft) ?? 0,
            npcMorality: npc.value(at: morality) ?? 0,
            npcConfidence: npc.value(at: confidence) ?? 0
        )
    }
}

nonisolated extension ConditionFunctions {
    static func installSpeechCheck(_ registry: inout ConditionFunctionRegistry) {
        // The player can pay what this actor asks.
        registry.register(ConditionFunction(index: 654, name: "GetBribeSuccess") { call in
            speechCheck(call) { checks, settings, actors in
                guard let gold = checks.playerGold else { return nil }
                return isTrue(Float(gold) >= settings.bribeAmount(actors) * checks.bribeFactor)
            }
        })
        registry.register(ConditionFunction(index: 655, name: "GetIntimidateSuccess") { call in
            speechCheck(call) { checks, settings, actors in
                isTrue(settings.intimidates(actors, playerFactor: checks.intimidationFactor))
            }
        })
    }

    /// Nil from `read` means the snapshot lacks what the check needs.
    private static func speechCheck(
        _ call: ConditionCall,
        read: (SpeechCheckResolution, SpeechCheckSettings, SpeechCheckActors) -> Float?
    ) -> Result<Float, ConditionFailure> {
        let checks = call.context.speechChecks
        guard let settings = checks.settings else { return .failure(.unavailableData(.speech)) }
        return call.actorState().flatMap { npc in
            guard let player = call.context.actors.state(for: .player) else {
                return .failure(.unavailableActorState)
            }
            let actors = SpeechCheckValues.actors(
                player: player, playerLevel: player.level, npc: npc, npcLevel: npc.level
            )
            guard let value = read(checks, settings, actors) else {
                return .failure(.unavailableData(.speech))
            }
            return .success(value)
        }
    }
}
