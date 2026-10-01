// The pure rules of the magic shell: cast reach, the game day, the panel's
// spell selection, the condition probes, and the outcome sentences. Values in,
// values out. See docs/engine/coordinators.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface

/// One condition function the Spellcasting panel probes against the player.
nonisolated public struct MagicConditionProbe: Equatable, Sendable {
    public let function: UInt16
    public let name: String
    public let parameter: UInt32
    /// What the parameter names, for the readout line.
    public let parameterText: String

    public func line(value: String) -> String {
        "\(name)(\(parameterText)) -> \(value)"
    }
}

nonisolated public enum MagicCore {
    /// How far an aimed cast reaches when neither the record nor the settings
    /// bound it. The vanilla archery ceiling, so a session without GMSTs does
    /// not aim at infinity.
    public static let fallbackReach: Float = 12288

    /// Seconds one panel cast fast-forwards the charge. Longer than any vanilla
    /// SPIT charge time; the cast loop clamps it to the spell's own.
    static let panelChargeStep: Float = 4

    static let effectsUnavailableText = "Magic effects unavailable: no game data loaded."
    static let castingUnavailableText = "Spellcasting unavailable: no game data loaded."

    /// The reach of a cast with SPIT range `range`. Zero bounds nothing, so the
    /// `fVisibleNavmeshMoveDist` ceiling a projectile flies under applies.
    public static func castReach(within range: Float, ceiling: Float) -> Float {
        [range, ceiling].filter { $0 > 0 }.min() ?? fallbackReach
    }

    /// The whole day a `GameClock.daysPassed` reading names, clamped so an
    /// absurd clock cannot trap the conversion.
    public static func gameDay(_ days: Float) -> Int32 {
        guard days.isFinite else { return 0 }
        let whole = days.rounded(.down)
        if whole <= Float(Int32.min) {
            return Int32.min
        }
        if whole >= Float(Int32.max) {
            return Int32.max
        }
        return Int32(whole)
    }

    /// `selection` clamped into a list of `count`. Forgetting a spell can leave
    /// a stored selection past the end.
    static func clampedSelection(_ selection: Int, count: Int) -> Int {
        min(max(0, selection), count - 1)
    }

    static func nextSelection(after selection: Int, count: Int) -> Int {
        (clampedSelection(selection, count: count) + 1) % count
    }

    /// The eight magic functions in registry order. The record-taking ones probe
    /// the readied spell and its first effect, the records the panel shows.
    static func conditionProbes(readied record: ResolvedSpell?) -> [MagicConditionProbe] {
        let spellID = record?.id.objectID ?? 0
        let effectID = record?.record.effects.first?.effect.rawValue ?? 0
        let spellName = record?.displayName ?? "no readied spell"
        let rightHand = "right hand"
        return [
            MagicConditionProbe(
                function: 214, name: "HasMagicEffect",
                parameter: effectID, parameterText: "first effect of \(spellName)"
            ),
            MagicConditionProbe(
                function: 223, name: "IsSpellTarget", parameter: spellID, parameterText: spellName
            ),
            MagicConditionProbe(
                function: 264, name: "HasSpell", parameter: spellID, parameterText: spellName
            ),
            MagicConditionProbe(
                function: 570, name: "HasEquippedSpell", parameter: 1, parameterText: rightHand
            ),
            MagicConditionProbe(
                function: 571, name: "GetCurrentCastingType", parameter: 1,
                parameterText: rightHand
            ),
            MagicConditionProbe(
                function: 572, name: "GetCurrentDeliveryType", parameter: 1,
                parameterText: rightHand
            ),
            MagicConditionProbe(
                function: 632,
                name: "IsCasting",
                parameter: 0,
                parameterText: "none"
            ),
            MagicConditionProbe(
                function: 699, name: "HasMagicEffectKeyword", parameter: 0,
                parameterText: "keyword 0"
            )
        ]
    }

    // MARK: - Sentences

    static func consumeText(name: String, outcome: MagicItemConsumeOutcome?) -> String {
        guard let outcome else { return "Could not consume \(name)." }
        let verb = outcome.kind == .ingredient ? "Ate" : "Drank"
        return "\(verb) \(name): \(outcome.entryCount) effect entries, "
            + "\(outcome.stored.count) now running."
    }

    static func dispelText(removed: Int) -> String {
        removed == 0
            ? "No effect was acting on the player."
            : "Dispelled \(removed) effect(s) on the player."
    }

    static func startSpellsText(granted: Int, held: Int) -> String {
        granted == 0
            ? "Every start spell was already known."
            : "Learned \(granted) start spell(s); \(held) ability effect(s) now running."
    }

    static func readingText(_ reading: SpellTomeReading, book: String) -> String {
        if reading.alreadyRead {
            return "\(book) was already read."
        }
        return reading.taught
            ? "Read \(book) and learned the spell it teaches."
            : "Read \(book); it taught nothing new."
    }

    static func readyText(_ change: SpellEquipChange, name: String, itemNames: [String]) -> String {
        let hands = SpellHand.allCases
            .filter { change.hands.contains($0.slots) }
            .map(\.describedName)
            .joined(separator: " and ")
        var text = "Readied \(name) in the \(hands)."
        if !itemNames.isEmpty {
            text += " Unequipped \(itemNames.joined(separator: ", "))."
        }
        return text
    }

    static func castText(_ outcome: SpellCastOutcome) -> String {
        switch outcome {
        case let .cast(result):
            String(
                format: "Cast: %.0f magicka spent, %d effect entries, %d now running.",
                result.magickaSpent, result.entryCount, result.storedCount
            )
        case let .released(_, held, spent):
            String(format: "Maintained for %.1fs, %.0f magicka spent.", held, spent)
        case let .failed(reason):
            "Cast refused: \(reason.describedReason)"
        case .charging, .ready, .concentrating:
            "Cast is still running."
        case .ignored:
            "Nothing to cast in that hand."
        }
    }
}
