// MESG messages (notifications and message boxes with buttons) and LSCR
// loading screens. Layout and sources: docs/formats/messages.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct GameMessage: Equatable, Sendable {
    nonisolated public struct Button: Equatable, Sendable {
        /// ITXT.
        public var text: LString?
        public var conditions: [Condition] = []
    }

    public let formID: FormID
    public let editorID: String?
    public let description: LString?
    public let name: LString?
    /// INAM, a leftover icon link that is always null.
    public let unusedIcon: FormID?
    /// QNAM, the owner QUST.
    public let quest: FormID?
    /// DNAM: 0x01 message box, 0x02 auto display.
    public let flags: UInt32
    /// TNAM, seconds on screen for a notification.
    public let displayTime: UInt32?
    public let buttons: [Button]
    public let skipped: FieldTally

    public var isMessageBox: Bool {
        flags & 0x01 != 0
    }

    public init(record: ESMRecord, localized: Bool) throws {
        var fields = try RecordFields(record: record, type: "MESG", localized: localized)
        formID = fields.formID
        editorID = fields.editorID()
        description = fields.lstring("DESC")
        name = fields.lstring("FULL")
        unusedIcon = fields.formID("INAM")
        quest = fields.formID("QNAM")
        flags = fields.uint32("DNAM") ?? 0
        displayTime = fields.uint32("TNAM")
        buttons = Self.buttons(&fields)
        skipped = fields.finish()
    }

    /// ITXT opens a button. The condition fields after it belong to that button.
    private static func buttons(_ fields: inout RecordFields) -> [Button] {
        var buttons: [Button] = []
        var conditions = ConditionList()
        for index in fields.fields.indices where !fields.isUsed(at: index) {
            let field = fields.fields[index]
            if field.type == "ITXT" {
                if !buttons.isEmpty {
                    buttons[buttons.count - 1].conditions = conditions.conditions
                }
                conditions = ConditionList()
                let localized = fields.localized
                let text = fields.read(at: index) { _ in
                    try LString(field: field, localized: localized)
                }
                buttons.append(Button(text: text))
            } else if ConditionList.isConditionField(field.type), !buttons.isEmpty {
                _ = fields.read(at: index) { _ in try conditions.decode(field: field) }
            }
        }
        if !buttons.isEmpty {
            buttons[buttons.count - 1].conditions = conditions.conditions
        }
        return buttons
    }
}

nonisolated public struct LoadScreen: Equatable, Sendable {
    public let formID: FormID
    public let editorID: String?
    public let description: LString?
    public let conditions: [Condition]
    /// NNAM, the STAT shown behind the text.
    public let model: FormID?
    /// SNAM.
    public let initialScale: Float?
    /// RNAM, degrees per axis.
    public let initialRotation: SIMD3<Int16>?
    /// ONAM, the min and max rotation offset.
    public let rotationOffsetRange: SIMD2<Int16>?
    /// XNAM.
    public let initialTranslation: SIMD3<Float>?
    /// MOD2, a camera path file.
    public let cameraPath: String?
    /// Header flag 0x400.
    public let displaysInMainMenu: Bool
    public let skipped: FieldTally

    public init(record: ESMRecord, localized: Bool) throws {
        var fields = try RecordFields(record: record, type: "LSCR", localized: localized)
        formID = fields.formID
        editorID = fields.editorID()
        description = fields.lstring("DESC")
        conditions = fields.conditions()
        model = fields.formID("NNAM")
        initialScale = fields.float("SNAM")
        initialRotation = fields.read("RNAM") { reader in
            try SIMD3(reader.readInt16(), reader.readInt16(), reader.readInt16())
        }
        rotationOffsetRange = fields.read("ONAM") { try SIMD2($0.readInt16(), $0.readInt16()) }
        initialTranslation = fields.read("XNAM") { try $0.readFloat3() }
        cameraPath = fields.zstring("MOD2")
        displaysInMainMenu = record.flags.rawValue & 0x400 != 0
        skipped = fields.finish()
    }
}
