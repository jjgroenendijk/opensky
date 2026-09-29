// One PERK effect: the PRKE header, its typed DATA, the PRKC condition tabs,
// and the EPFT/EPF2/EPF3/EPFD parameters. The PRKE type and the function type
// decide what the payloads mean, so each enum keeps an `unknown(raw:)` case and
// a mismatched payload stays as raw bytes. Layout: docs/formats/perks.md.

import Foundation

/// PRKE byte 0 — which of the three shapes the effect's DATA carries.
nonisolated public enum PerkEffectType: Hashable, CustomStringConvertible, Sendable {
    case quest
    case ability
    case entryPoint
    case unknown(raw: UInt8)

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .quest
        case 1: self = .ability
        case 2: self = .entryPoint
        default: self = .unknown(raw: rawValue)
        }
    }

    public var description: String {
        switch self {
        case .quest: "quest"
        case .ability: "ability"
        case .entryPoint: "entry point"
        case let .unknown(raw): "unknown (\(raw))"
        }
    }
}

/// The second byte of an entry-point DATA: how the entry point's value is
/// changed. Which EPFD shape belongs to each is noted per case, and it is the
/// EPFT field — not this — that is trusted when the two disagree.
nonisolated public enum PerkFunction: Hashable, CustomStringConvertible, Sendable {
    case setValue
    case addValue
    case multiplyValue
    case addRangeToValue
    case addActorValueMultiplier
    case absoluteValue
    case negativeAbsoluteValue
    case addLeveledList
    case addActivateChoice
    case selectSpell
    case selectText
    case setToActorValueMultiplier
    case multiplyActorValueMultiplier
    case multiplyOnePlusActorValueMultiplier
    case setText
    case unknown(raw: UInt8)

    // One branch per documented value; a lookup table would not read better
    // than the list, so the complexity cap is waived here.
    // swiftlint:disable:next cyclomatic_complexity
    public init(rawValue: UInt8) {
        switch rawValue {
        case 1: self = .setValue
        case 2: self = .addValue
        case 3: self = .multiplyValue
        case 4: self = .addRangeToValue
        case 5: self = .addActorValueMultiplier
        case 6: self = .absoluteValue
        case 7: self = .negativeAbsoluteValue
        case 8: self = .addLeveledList
        case 9: self = .addActivateChoice
        case 10: self = .selectSpell
        case 11: self = .selectText
        case 12: self = .setToActorValueMultiplier
        case 13: self = .multiplyActorValueMultiplier
        case 14: self = .multiplyOnePlusActorValueMultiplier
        case 15: self = .setText
        default: self = .unknown(raw: rawValue)
        }
    }

    /// The four functions whose EPFT=2 payload is an actor value and a factor
    /// rather than a pair of floats (`wbEPFDDecider`, line 1196).
    public var readsActorValuePair: Bool {
        switch self {
        case .addActorValueMultiplier,
             .setToActorValueMultiplier,
             .multiplyActorValueMultiplier,
             .multiplyOnePlusActorValueMultiplier:
            true
        default:
            false
        }
    }

    public var description: String {
        switch self {
        case .setValue: "set value"
        case .addValue: "add value"
        case .multiplyValue: "multiply value"
        case .addRangeToValue: "add range to value"
        case .addActorValueMultiplier: "add actor value mult"
        case .absoluteValue: "absolute value"
        case .negativeAbsoluteValue: "negative absolute value"
        case .addLeveledList: "add leveled list"
        case .addActivateChoice: "add activate choice"
        case .selectSpell: "select spell"
        case .selectText: "select text"
        case .setToActorValueMultiplier: "set to actor value mult"
        case .multiplyActorValueMultiplier: "multiply actor value mult"
        case .multiplyOnePlusActorValueMultiplier: "multiply 1 + actor value mult"
        case .setText: "set text"
        case let .unknown(raw): "unknown (\(raw))"
        }
    }
}

/// EPFT — the declared shape of the EPFD payload.
nonisolated public enum PerkFunctionType: Hashable, CustomStringConvertible, Sendable {
    case none
    case float
    case floatPair
    case leveledItem
    case spellWithLabelAndFlags
    case spell
    case text
    case localizedText
    case unknown(raw: UInt8)

    public init(rawValue: UInt8) {
        switch rawValue {
        case 0: self = .none
        case 1: self = .float
        case 2: self = .floatPair
        case 3: self = .leveledItem
        case 4: self = .spellWithLabelAndFlags
        case 5: self = .spell
        case 6: self = .text
        case 7: self = .localizedText
        default: self = .unknown(raw: rawValue)
        }
    }

    public var description: String {
        switch self {
        case .none: "none"
        case .float: "float"
        case .floatPair: "float pair"
        case .leveledItem: "leveled item"
        case .spellWithLabelAndFlags: "spell with label and flags"
        case .spell: "spell"
        case .text: "text"
        case .localizedText: "localized text"
        case let .unknown(raw): "unknown (\(raw))"
        }
    }
}

/// EPFD, read through the EPFT type and — for the float pair — the declared
/// function. `raw` is the honest answer for a payload whose declared type this
/// build does not know or whose bytes do not fit the declared shape.
nonisolated public enum PerkFunctionData: Equatable, Sendable, CustomStringConvertible {
    case float(Float)
    case floatPair(Float, Float)
    /// EPFT 2 under an actor-value function: the actor value, then the factor. The
    /// index is stored as a float (UESP, xEdit) and rounded to the usual signed
    /// index, so `AlchemySkillBoosts` reads 146.
    case actorValueMultiplier(actorValue: Int32, factor: Float)
    case leveledItem(FormID)
    case spell(FormID)
    case text(String)
    case localizedText(LString)
    case raw(Data)

    public var description: String {
        switch self {
        case let .float(value): String(format: "%.4f", value)
        case let .floatPair(first, second): String(format: "%.4f, %.4f", first, second)
        case let .actorValueMultiplier(actorValue, factor):
            String(
                format: "%@ x %.4f",
                ActorValueIdentity.description(of: actorValue),
                factor
            )
        case let .leveledItem(id): "leveled item \(id)"
        case let .spell(id): "spell \(id)"
        case let .text(value): "\"\(value)\""
        case let .localizedText(value): Self.describe(value)
        case let .raw(data): "\(data.count) raw bytes"
        }
    }

    /// The stored float as the actor-value index it spells, rounded to nearest
    /// as xEdit rounds it. A payload outside `Int32`'s range, or a NaN, reads
    /// as -1 — the "no actor value" index the rest of the engine already uses —
    /// rather than trapping on the conversion.
    public static func actorValueIndex(fromFloat value: Float) -> Int32 {
        let rounded = value.rounded()
        guard
            rounded.isFinite,
            rounded >= Float(Int32.min),
            rounded <= Float(Int32.max)
        else { return -1 }
        return Int32(rounded)
    }

    private static func describe(_ value: LString) -> String {
        switch value {
        case let .inline(text): "\"\(text)\""
        case let .tableID(id): "string #\(id)"
        }
    }
}

/// EPF3 — the flags an "add activate choice" function carries beside its
/// button label.
nonisolated public struct PerkScriptFlags: Equatable, Sendable {
    public static let byteCount = 4

    public struct Options: OptionSet, Equatable, Sendable {
        public let rawValue: UInt16

        public init(rawValue: UInt16) {
            self.rawValue = rawValue
        }

        public static let runImmediately = Options(rawValue: 1 << 0)
        public static let replaceDefault = Options(rawValue: 1 << 1)
    }

    public let options: Options
    /// Which VMAD perk fragment runs for this choice.
    public let fragmentIndex: UInt16
}

/// One PRKC block: the tab index conditions run against, and the CTDA run that
/// belongs to it. Which subject each index names depends on the entry point
/// (UESP "Perk Effect Types" lists them per effect, typically perk owner,
/// target and attacker), so the index is kept raw.
nonisolated public struct PerkConditionTab: Equatable, Sendable {
    public let runOn: Int8
    public var conditions: ConditionList
}

/// The DATA payload an entry-point effect declares.
nonisolated public struct PerkEntryPointEffect: Equatable, Sendable {
    public static let byteCount = 3

    public let entryPoint: PerkEntryPoint
    public let function: PerkFunction
    /// How many PRKC tabs the effect is expected to carry. xEdit marks it
    /// ignored on write because it is fixed per entry point; it is kept here so
    /// a sweep can check it against the tabs actually decoded.
    public let conditionTabCount: UInt8
}

/// The typed DATA of one effect, chosen by the PRKE type byte.
nonisolated public enum PerkEffectData: Equatable, Sendable {
    /// Quest effect: 4-byte QUST link, uint16 stage, then two unused bytes
    /// that carry junk in vanilla records.
    case quest(quest: FormID?, stage: UInt16)
    case ability(spell: FormID?)
    case entryPoint(PerkEntryPointEffect)
    /// A DATA under a PRKE type this build does not know, kept verbatim.
    case raw(Data)
}

/// One complete PRKE...PRKF section.
nonisolated public struct PerkEffect: Equatable, Sendable {
    public let type: PerkEffectType
    /// PRKE byte 1. Zero means rank 1, which is how the Creation Kit shows it.
    public let rank: UInt8
    public let priority: UInt8
    /// Nil when the section carried no DATA at all, which is a mod quirk the
    /// record tally counts.
    public let data: PerkEffectData?
    public let conditionTabs: [PerkConditionTab]
    public let functionType: PerkFunctionType?
    /// EPF2, the activate-choice button label.
    public let buttonLabel: LString?
    public let scriptFlags: PerkScriptFlags?
    public let functionData: PerkFunctionData?
    /// Whether the section ended on its PRKF marker rather than at the end of
    /// the record.
    public let isTerminated: Bool

    /// The entry point this effect answers for, or nil for a quest or ability
    /// effect. This is what `PerkStore`'s entry-point index keys on.
    public var entryPoint: PerkEntryPoint? {
        guard case let .entryPoint(payload) = data else { return nil }
        return payload.entryPoint
    }

    /// The spell this effect grants or casts: an ability effect's DATA link,
    /// or the SPEL an entry-point function selects.
    public var spell: FormID? {
        switch data {
        case let .ability(spell):
            return spell
        default:
            guard case let .spell(id) = functionData else { return nil }
            return id.isNull ? nil : id
        }
    }

    /// Rank as the Creation Kit numbers it, counting from one.
    public var displayRank: Int {
        Int(rank) + 1
    }
}
