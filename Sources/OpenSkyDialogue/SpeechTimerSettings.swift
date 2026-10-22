// How often an NPC may speak outside a conversation: the voice gap, the greetings, the
// combat lines, idle chatter, comments on the player, and bump lines. Each comes from the
// install; where the wiki does not say how a setting applies, the use is OpenSky's reading
// (docs/engine/dialogue.md#speech-timers).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public struct SpeechTimerSettings: Equatable, Sendable {
    /// `fGameplayVoiceFilePadding`: "seconds of silence that Skyrim inserts between
    /// consecutive voice lines" (<https://ck.uesp.net/wiki/Category:Settings>).
    public var voiceFilePadding: Float = 0.5
    /// `fAIForceGreetingTimer`: "Time until an NPC can initialize a force greeting again".
    public var forceGreetingSeconds: Float = 3
    /// `fAIGreetingTimer`: "Time until an NPC can greet again".
    public var greetingSeconds: Float = 5
    /// `fAIExclusiveGreetingTimer`: after any hello, no other NPC greets for this long.
    public var exclusiveGreetingSeconds: Float = 2.5
    /// `fAIMinGreetingDistance`: a hello needs the player this close. Not in `Skyrim.esm`;
    /// the CK wiki table value.
    public var greetingDistance: Float = 150
    /// `fCombatDialogueAttackMinElapsedTime` and `...Max...`: the attack and hit line window.
    public var attackLineMinSeconds: Float = 5
    public var attackLineMaxSeconds: Float = 10
    /// `fCombatDialogueTauntMinElapsedTime` and `...Max...`: the taunt window.
    public var tauntMinSeconds: Float = 10
    public var tauntMaxSeconds: Float = 30
    /// `fCombatSpeakAttackChance`, `fCombatSpeakHitChance`, `fCombatSpeakTauntChance`:
    /// the chance, 0 to 1, that a line speaks once its window has passed.
    public var attackLineChance: Float = 0.01
    public var hitLineChance: Float = 0.01
    public var tauntChance: Float = 0.01
    /// `fCombatSpeakHitThreshold`: a hit speaks only when its damage is at least this
    /// share of the target's maximum health.
    public var hitLineThreshold: Float = 0.01
    /// `fIdleChatterCommentTimer` and `...Max`: the wait between two idle comments.
    public var idleChatterMinSeconds: Float = 10
    public var idleChatterMaxSeconds: Float = 20
    /// `fCommentOnPlayerActionsTimer` and `fCommentOnPlayerKnockingThings`.
    public var playerActionCommentSeconds: Float = 20
    public var knockOverCommentSeconds: Float = 40
    /// `fBumpReactionSmallWaitTimer`: the wait before a bumped NPC speaks again.
    public var bumpLineSeconds: Float = 3
    /// `fSpeechDelay`: the pause before a line said outside a conversation starts.
    public var speechDelay: Float = 0.1
    /// `fDialogSpeechDelaySeconds` and `fSubtitleSpeechDelay`: the shortest and longest
    /// time a line with no voice file stays up.
    public var silentLineMinSeconds: Float = 2
    public var silentLineMaxSeconds: Float = 8
    /// `fRandomSceneAgainMinTime` and `...MaxTime`: the wait before a scene flagged
    /// "Repeat while true" plays again.
    public var sceneRepeatMinSeconds: Float = 10
    public var sceneRepeatMaxSeconds: Float = 30

    public static let vanilla = Self()

    public init() {}

    public static func resolve(store: GameSettingStore) -> Self {
        var settings = vanilla
        let fields: [(String, WritableKeyPath<Self, Float>)] = [
            ("fGameplayVoiceFilePadding", \.voiceFilePadding),
            ("fAIForceGreetingTimer", \.forceGreetingSeconds),
            ("fAIGreetingTimer", \.greetingSeconds),
            ("fAIExclusiveGreetingTimer", \.exclusiveGreetingSeconds),
            ("fAIMinGreetingDistance", \.greetingDistance),
            ("fCombatDialogueAttackMinElapsedTime", \.attackLineMinSeconds),
            ("fCombatDialogueAttackMaxElapsedTime", \.attackLineMaxSeconds),
            ("fCombatDialogueTauntMinElapsedTime", \.tauntMinSeconds),
            ("fCombatDialogueTauntMaxElapsedTime", \.tauntMaxSeconds),
            ("fCombatSpeakAttackChance", \.attackLineChance),
            ("fCombatSpeakHitChance", \.hitLineChance),
            ("fCombatSpeakTauntChance", \.tauntChance),
            ("fCombatSpeakHitThreshold", \.hitLineThreshold),
            ("fIdleChatterCommentTimer", \.idleChatterMinSeconds),
            ("fIdleChatterCommentTimerMax", \.idleChatterMaxSeconds),
            ("fCommentOnPlayerActionsTimer", \.playerActionCommentSeconds),
            ("fCommentOnPlayerKnockingThings", \.knockOverCommentSeconds),
            ("fBumpReactionSmallWaitTimer", \.bumpLineSeconds),
            ("fSpeechDelay", \.speechDelay),
            ("fDialogSpeechDelaySeconds", \.silentLineMinSeconds),
            ("fSubtitleSpeechDelay", \.silentLineMaxSeconds),
            ("fRandomSceneAgainMinTime", \.sceneRepeatMinSeconds),
            ("fRandomSceneAgainMaxTime", \.sceneRepeatMaxSeconds)
        ]
        for (editorID, keyPath) in fields {
            store.read(editorID, into: &settings, keyPath)
        }
        return settings
    }

    /// The waits and chances for the Dialogue panel.
    public var readout: String {
        let percent = { (line: NPCSpeechLine) in Int((chance(of: line) * 100).rounded()) }
        return String(
            format: "Speech timers: force greet %.1f s · hello %.1f s (gap %.1f s) · "
                + "combat line %.1f-%.1f s · taunt %.0f-%.0f s · attack %d%% · hit %d%% · "
                + "taunt %d%% · idle %.0f-%.0f s · comment %.0f s · voice gap %.2f s",
            forceGreetingSeconds, greetingSeconds, exclusiveGreetingSeconds,
            attackLineMinSeconds, attackLineMaxSeconds, tauntMinSeconds, tauntMaxSeconds,
            percent(.combatAttack), percent(.combatHit), percent(.combatTaunt),
            idleChatterMinSeconds, idleChatterMaxSeconds, playerActionCommentSeconds,
            voiceFilePadding
        )
    }

    /// A voiced line's seconds with the gap the next line waits for.
    public func padded(_ seconds: Float) -> Float {
        seconds + finite(voiceFilePadding)
    }

    /// How long a line with no voice file stays up: its reading time, kept inside the
    /// silent line window.
    public func silentLineSeconds(readingSeconds: Float) -> Float {
        let low = finite(min(silentLineMinSeconds, silentLineMaxSeconds))
        let high = finite(max(silentLineMinSeconds, silentLineMaxSeconds))
        return min(max(finite(readingSeconds), low), high)
    }

    /// The scene repeat window, ordered and never negative.
    public var sceneRepeatPause: ClosedRange<Float> {
        let low = finite(min(sceneRepeatMinSeconds, sceneRepeatMaxSeconds))
        return low ... max(low, finite(max(sceneRepeatMinSeconds, sceneRepeatMaxSeconds)))
    }

    /// Seconds before `line` may come again. `unit` in 0...1 picks a point in a window.
    public func wait(after line: NPCSpeechLine, unit: Float) -> Double {
        let seconds: Float = switch line {
        case .forceGreeting: finite(forceGreetingSeconds)
        case .hello: finite(greetingSeconds)
        case .combatAttack, .combatHit:
            window(attackLineMinSeconds, attackLineMaxSeconds, unit: unit)
        case .combatTaunt: window(tauntMinSeconds, tauntMaxSeconds, unit: unit)
        case .idleChatter: window(idleChatterMinSeconds, idleChatterMaxSeconds, unit: unit)
        case .playerAction: finite(playerActionCommentSeconds)
        case .knockOver: finite(knockOverCommentSeconds)
        case .bump: finite(bumpLineSeconds)
        }
        return Double(seconds)
    }

    /// The wait every other speaker of `line` keeps after one speaks it, or nil when
    /// each speaker keeps only its own.
    public func sharedWait(after line: NPCSpeechLine, unit: Float) -> Double? {
        switch line {
        case .hello: Double(finite(exclusiveGreetingSeconds))
        case .idleChatter, .playerAction, .knockOver: wait(after: line, unit: unit)
        case .forceGreeting, .combatAttack, .combatHit, .combatTaunt, .bump: nil
        }
    }

    /// The chance, 0 to 1, that `line` speaks when its wait has passed.
    public func chance(of line: NPCSpeechLine) -> Float {
        let chance: Float = switch line {
        case .combatAttack: attackLineChance
        case .combatHit: hitLineChance
        case .combatTaunt: tauntChance
        case .forceGreeting, .hello, .idleChatter, .playerAction, .knockOver, .bump: 1
        }
        return chance.isFinite ? min(max(chance, 0), 1) : 0
    }

    /// The chance a taunt speaks over `seconds`. The setting is read as a chance per
    /// 1/60 s step, so the taunt rate does not depend on the frame rate.
    public func tauntChance(over seconds: Float) -> Float {
        let perStep = chance(of: .combatTaunt)
        let steps = finite(seconds) * 60
        return 1 - pow(1 - perStep, steps)
    }

    /// Whether a hit of `damage` on a target with `maximumHealth` is strong enough to speak.
    public func hitSpeaks(damage: Float, maximumHealth: Float) -> Bool {
        guard maximumHealth.isFinite, maximumHealth > 0 else { return damage > 0 }
        return finite(damage) >= finite(hitLineThreshold) * maximumHealth
    }

    private func window(_ first: Float, _ second: Float, unit: Float) -> Float {
        let low = finite(min(first, second))
        let high = finite(max(first, second))
        let blend = unit.isFinite ? min(max(unit, 0), 1) : 0
        return low + (high - low) * blend
    }

    private func finite(_ value: Float) -> Float {
        value.isFinite ? max(value, 0) : 0
    }
}

/// A line an NPC says on its own, outside a conversation.
nonisolated public enum NPCSpeechLine: Hashable, Sendable {
    case forceGreeting
    case hello
    case combatAttack
    case combatHit
    case combatTaunt
    case idleChatter
    /// A comment on something the player did, by its `DIAL` subtype (Misc Tab).
    case playerAction(FourCC)
    case knockOver
    case bump

    /// The DIAL subtype the line is picked from; nil for a force greet.
    public var subtype: FourCC? {
        switch self {
        case .forceGreeting: nil
        case .hello: "HELO"
        case .combatAttack: "ATCK"
        case .combatHit: "HIT_"
        case .combatTaunt: "TAUT"
        case .idleChatter: "IDLE"
        case let .playerAction(subtype): subtype
        case .knockOver: "KNOO"
        case .bump: "ACAC"
        }
    }
}
