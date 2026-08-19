// The PERK field-run state machine. See Perk.swift for the ordering rules and
// the reference block, and PerkEffect.swift for the types this fills.
//
// `PerkContents` walks the field run once, keeping at most one open effect and,
// inside it, one open condition tab. PRKE opens an effect, PRKF closes it, and
// every field in between belongs to that effect. The EPFD payload is kept as
// its raw field until the effect closes, because whether it is a float pair or
// an actor-value pair depends on the function byte in the effect's DATA, and
// nothing in the format guarantees DATA arrives first.

import Foundation

/// Not `private`: `Perk` drives it and reads its result.
nonisolated struct PerkContents {
    /// One PRKE section while it is still being collected.
    struct OpenEffect {
        let type: PerkEffectType
        let rank: UInt8
        let priority: UInt8
        var data: PerkEffectData?
        var tabs: [PerkConditionTab] = []
        var functionType: PerkFunctionType?
        var buttonLabel: LString?
        var scriptFlags: PerkScriptFlags?
        /// EPFD verbatim; read into `PerkFunctionData` when the effect closes.
        var functionDataField: ESMField?

        /// The function byte the effect's DATA declared, which is half of what
        /// decides how EPFD reads.
        var function: PerkFunction? {
            guard case let .entryPoint(payload) = data else { return nil }
            return payload.function
        }
    }

    /// Subrecords that only ever appear inside a PRKE section. One arriving at
    /// record level is counted rather than mistaken for a record-level field.
    private static let effectOnlyFields: Set<FourCC> = [
        "PRKC", "EPFT", "EPF2", "EPF3", "EPFD"
    ]

    let localized: Bool

    var editorID: String?
    var name: LString?
    var description: LString?
    var iconPath: String?
    var conditions = ConditionList()
    var data: PerkHeaderData?
    var nextPerk: FormID?
    var effects: [PerkEffect] = []
    var script = ScriptData(ownerType: "PERK")
    var skipped = PerkTally()

    private var open: OpenEffect?

    init(localized: Bool) {
        self.localized = localized
    }

    mutating func decode(_ field: ESMField) {
        do {
            switch field.type {
            case "PRKE":
                closeOpenEffect(terminated: false)
                try beginEffect(field)
            case "PRKF":
                guard open != nil else {
                    skipped.note(.fieldOutsideEffect(field.type))
                    return
                }
                closeOpenEffect(terminated: true)
            default:
                if open != nil {
                    try decodeEffectField(field)
                } else {
                    try decodeRecordField(field)
                }
            }
        } catch {
            skipped.note(.malformedField(field.type))
        }
    }

    /// Flushes the effect still open, if any. Called on the next PRKE, on PRKF,
    /// and once more after the last field of the record.
    mutating func closeOpenEffect(terminated: Bool) {
        guard let open else { return }
        if !terminated {
            skipped.note(.unterminatedEffect)
        }
        effects.append(PerkEffect(
            type: open.type,
            rank: open.rank,
            priority: open.priority,
            data: open.data,
            conditionTabs: open.tabs,
            functionType: open.functionType,
            buttonLabel: open.buttonLabel,
            scriptFlags: open.scriptFlags,
            functionData: Self.functionData(
                field: open.functionDataField,
                type: open.functionType,
                function: open.function,
                localized: localized
            ),
            isTerminated: terminated
        ))
        self.open = nil
    }

    // MARK: Record level

    private mutating func decodeRecordField(_ field: ESMField) throws {
        if try conditions.decode(field: field) {
            return
        }
        if try script.decode(field: field) {
            return
        }
        switch field.type {
        case "EDID": editorID = try PerkFieldReader.zstring(field)
        case "FULL": name = try LString(field: field, localized: localized)
        case "DESC": description = try LString(field: field, localized: localized)
        case "ICON": iconPath = try PerkFieldReader.zstring(field)
        case "DATA": data = try PerkHeaderData(field: field)
        case "NNAM": nextPerk = try PerkFieldReader.link(field)
        default:
            if Self.effectOnlyFields.contains(field.type) {
                skipped.note(.fieldOutsideEffect(field.type))
            } else {
                skipped.note(.unknownField(field.type))
            }
        }
    }

    // MARK: Effect level

    private mutating func beginEffect(_ field: ESMField) throws {
        guard field.data.count >= 3 else {
            throw ESMError.malformed("PERK PRKE has \(field.data.count) bytes, expected 3")
        }
        var reader = BinaryReader(field.data)
        open = try OpenEffect(
            type: PerkEffectType(rawValue: reader.readUInt8()),
            rank: reader.readUInt8(),
            priority: reader.readUInt8()
        )
    }

    private mutating func decodeEffectField(_ field: ESMField) throws {
        guard var effect = open else { return }
        defer { open = effect }
        switch field.type {
        case "DATA":
            effect.data = try Self.effectData(field, type: effect.type)
        case "PRKC":
            try effect.tabs.append(PerkConditionTab(
                runOn: Int8(bitPattern: PerkFieldReader.byte(field)),
                conditions: ConditionList()
            ))
        case "EPFT":
            try effect.functionType = PerkFunctionType(rawValue: PerkFieldReader.byte(field))
        case "EPF2":
            effect.buttonLabel = try LString(field: field, localized: localized)
        case "EPF3":
            effect.scriptFlags = try PerkFieldReader.scriptFlags(field)
        case "EPFD":
            effect.functionDataField = field
        default:
            try decodeEffectCondition(field, into: &effect)
        }
    }

    /// A CTDA run inside an effect belongs to the tab the last PRKC opened.
    /// Anything else falls back to the record level, which is where a plugin
    /// that emits EDID or VMAD out of order ends up.
    private mutating func decodeEffectCondition(
        _ field: ESMField,
        into effect: inout OpenEffect
    ) throws {
        guard ConditionList.isConditionField(field.type) else {
            try decodeRecordField(field)
            return
        }
        guard !effect.tabs.isEmpty else {
            skipped.note(.conditionOutsideTab)
            return
        }
        try effect.tabs[effect.tabs.count - 1].conditions.decode(field: field)
    }

    // MARK: Payload unions

    private static func effectData(
        _ field: ESMField,
        type: PerkEffectType
    ) throws -> PerkEffectData {
        var reader = BinaryReader(field.data)
        switch type {
        case .quest:
            guard field.data.count >= 8 else {
                throw ESMError.malformed(
                    "PERK quest DATA has \(field.data.count) bytes, expected 8"
                )
            }
            let quest = try FormID(reader.readUInt32())
            return try .quest(quest: quest.isNull ? nil : quest, stage: reader.readUInt16())
        case .ability:
            guard field.data.count >= 4 else {
                throw ESMError.malformed(
                    "PERK ability DATA has \(field.data.count) bytes, expected 4"
                )
            }
            let spell = try FormID(reader.readUInt32())
            return .ability(spell: spell.isNull ? nil : spell)
        case .entryPoint:
            guard field.data.count >= PerkEntryPointEffect.byteCount else {
                throw ESMError.malformed(
                    "PERK entry-point DATA has \(field.data.count) bytes, expected "
                        + "\(PerkEntryPointEffect.byteCount)"
                )
            }
            return try .entryPoint(PerkEntryPointEffect(
                entryPoint: PerkEntryPoint(rawValue: reader.readUInt8()),
                function: PerkFunction(rawValue: reader.readUInt8()),
                conditionTabCount: reader.readUInt8()
            ))
        case .unknown:
            return .raw(field.data)
        }
    }

    /// EPFD read through EPFT, with the effect's function byte breaking the one
    /// tie EPFT leaves open (`wbEPFDDecider`). A payload whose length does not
    /// fit its declared shape is kept raw rather than dropped or guessed at.
    private static func functionData(
        field: ESMField?,
        type: PerkFunctionType?,
        function: PerkFunction?,
        localized: Bool
    ) -> PerkFunctionData? {
        guard let field else { return nil }
        let data = field.data
        var reader = BinaryReader(data)
        do {
            switch type {
            case .float where data.count >= 4:
                return try .float(reader.readFloat32())
            case .floatPair where data.count >= 8:
                if function?.readsActorValuePair == true {
                    // The actor value is stored as a *float* holding the index,
                    // not as an integer: xEdit reads the same four bytes back
                    // through `wbEPFDActorValueToStr`, which reinterprets them
                    // as a `Single` and rounds
                    // (Core/wbDefinitionsTES5.pas line 889), and UESP spells the
                    // payload "float AV, float FACTOR". Reading the raw word as
                    // an integer produces the bit pattern instead of the index —
                    // 0x43120000 rather than 146.
                    return try .actorValueMultiplier(
                        actorValue: PerkFunctionData.actorValueIndex(
                            fromFloat: reader.readFloat32()
                        ),
                        factor: reader.readFloat32()
                    )
                }
                return try .floatPair(reader.readFloat32(), reader.readFloat32())
            case .leveledItem where data.count >= 4:
                return try .leveledItem(FormID(reader.readUInt32()))
            case .spell, .spellWithLabelAndFlags:
                guard data.count >= 4 else { return .raw(data) }
                return try .spell(FormID(reader.readUInt32()))
            case .text:
                return try .text(reader.readZString())
            case .localizedText:
                return try .localizedText(LString(field: field, localized: localized))
            default:
                return .raw(data)
            }
        } catch {
            return .raw(data)
        }
    }
}

/// The fixed-width reads PERK fields need, each checking its own length so a
/// truncated field throws instead of reading past the end.
nonisolated enum PerkFieldReader {
    static func byte(_ field: ESMField) throws -> UInt8 {
        guard let first = field.data.first else {
            throw ESMError.malformed("PERK \(field.type) is empty, expected 1 byte")
        }
        return first
    }

    static func zstring(_ field: ESMField) throws -> String {
        var reader = BinaryReader(field.data)
        return try reader.readZString()
    }

    static func link(_ field: ESMField) throws -> FormID? {
        guard field.data.count >= 4 else {
            throw ESMError.malformed(
                "PERK \(field.type) has \(field.data.count) bytes, expected 4"
            )
        }
        var reader = BinaryReader(field.data)
        let id = try FormID(reader.readUInt32())
        return id.isNull ? nil : id
    }

    static func scriptFlags(_ field: ESMField) throws -> PerkScriptFlags {
        guard field.data.count >= PerkScriptFlags.byteCount else {
            throw ESMError.malformed(
                "PERK EPF3 has \(field.data.count) bytes, expected \(PerkScriptFlags.byteCount)"
            )
        }
        var reader = BinaryReader(field.data)
        return try PerkScriptFlags(
            options: PerkScriptFlags.Options(rawValue: reader.readUInt16()),
            fragmentIndex: reader.readUInt16()
        )
    }
}
