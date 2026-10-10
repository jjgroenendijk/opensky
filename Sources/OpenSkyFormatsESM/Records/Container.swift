// CONT contents and DATA flags. Composes `ModelBase` so existing consumers
// keep their decode. COCT is advisory: entries are counted as decoded. The
// COED middle word depends on the owner type, so it stays raw.
// Layout and sources: docs/formats/item-records.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct Container: Sendable {
    /// One CNTO entry with the COED extra data that followed it, if any.
    public struct Entry: Equatable, Sendable {
        /// The item placed in the container: a carryable item or an LVLI, which
        /// the inventory runtime expands.
        public let item: FormID
        /// Stack count. Signed on disk; vanilla never writes a negative.
        public let count: Int32
        /// COED owner — an NPC_ or FACT. Nil when the entry is unowned.
        public let owner: FormID?
        /// COED union word: a GLOB FormID for an NPC_ owner, a required
        /// faction rank for a FACT owner. Raw because the decoder cannot tell
        /// which without resolving `owner`'s record type.
        public let ownerCondition: UInt32?
        /// COED item condition (health fraction).
        public let condition: Float?
    }

    public struct Flags: OptionSet, Equatable, Sendable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }

        /// Play the open/close sounds even though the model has an animation.
        public static let allowSoundsWhenAnimation = Flags(rawValue: 0x01)
        public static let respawns = Flags(rawValue: 0x02)
        public static let showOwner = Flags(rawValue: 0x04)
    }

    /// The shared MSTT/TREE/FURN/ACTI/CONT/DOOR decode — name, model, sounds.
    public let base: ModelBase
    /// CNTO entries in file order.
    public let entries: [Entry]
    /// COCT as written; nil when absent. Diagnostics only.
    public let declaredEntryCount: UInt32?
    /// DATA flags byte. The float that follows it in the struct is documented
    /// as a misaligned weight and is always 0, so it is not decoded.
    public let flags: Flags
    /// The fields neither `base` nor the contents run reads.
    public let skipped: FieldTally

    public var formID: FormID {
        base.formID
    }

    /// True when COCT is present and disagrees with the CNTO fields decoded.
    public var entryCountMismatch: Bool {
        guard let declaredEntryCount else { return false }
        return Int(declaredEntryCount) != entries.count
    }

    public init(record: ESMRecord, localized: Bool = false) throws {
        guard record.type == "CONT" else {
            throw ESMError.malformed("expected CONT record, got \(record.type)")
        }
        base = try ModelBase(record: record, localized: localized)

        var contents = Contents()
        var skipped = base.skipped
        for field in try record.fields() where try contents.decode(field: field) {
            skipped.unnote(.unknownField(field.type))
        }
        self.skipped = skipped
        entries = contents.entries
        declaredEntryCount = contents.declaredEntryCount
        flags = contents.flags
    }

    /// Accumulator for the contents run; separate so the CNTO/COED pairing
    /// logic reads as one unit instead of being spread through `init`.
    private struct Contents {
        var entries: [Entry] = []
        var declaredEntryCount: UInt32?
        var flags = Flags()

        mutating func decode(field: ESMField) throws -> Bool {
            var reader = BinaryReader(field.data)
            switch field.type {
            case "COCT":
                guard field.data.count >= 4 else { break }
                declaredEntryCount = try reader.readUInt32()
            case "CNTO":
                // Short payloads cost one entry rather than the whole
                // container — mod-quirk rule, same as XLKR on REFR.
                guard field.data.count >= 8 else { break }
                try entries.append(
                    Entry(
                        item: FormID(reader.readUInt32()),
                        count: Int32(bitPattern: reader.readUInt32()),
                        owner: nil,
                        ownerCondition: nil,
                        condition: nil
                    )
                )
            case "COED":
                try attachExtraData(field)
            case "DATA":
                guard field.data.count >= 1 else { break }
                flags = try Flags(rawValue: reader.readUInt8())
            default:
                return false
            }
            return true
        }

        /// COED applies to the CNTO immediately before it. A COED with no
        /// preceding entry has nothing to own and is dropped.
        private mutating func attachExtraData(_ field: ESMField) throws {
            guard field.data.count >= 12, let last = entries.last else { return }
            var reader = BinaryReader(field.data)
            let owner = try FormID(reader.readUInt32())
            let ownerCondition = try reader.readUInt32()
            let condition = try reader.readFloat32()
            entries[entries.count - 1] = Entry(
                item: last.item,
                count: last.count,
                owner: owner.isNull ? nil : owner,
                ownerCondition: owner.isNull ? nil : ownerCondition,
                condition: condition
            )
        }
    }
}
