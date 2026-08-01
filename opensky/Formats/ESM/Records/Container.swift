// CONT contents: the item list a container starts with, plus the container's
// own DATA flags.
//
// `ModelBase` already decodes the CONT fields the cell builder and the
// interaction path need (EDID, FULL, MODL, open/close sounds), and those
// consumers must keep working unchanged, so `Container` *composes* ModelBase
// rather than replacing or duplicating it: `base` is the same decode those
// paths already use, and this type adds only the inventory half.
//
// The contents are a run of subrecords, not one array:
//   COCT  uint32   count of the CNTO entries that follow
//   CNTO  8 bytes  FormID item + int32 count, repeated
//   COED 12 bytes  optional owner data for the CNTO immediately before it
//
// COCT is advisory. The engine counts the CNTO fields it actually decoded and
// records the authored number separately, for the same reason KSIZ is not
// trusted to size KWDA: a stale count in a modded plugin must not truncate a
// container or run the reader past the record.
//
// COED's middle word is a union whose meaning depends on the owner: a GLOB
// FormID when the owner is an NPC_, a required faction rank when it is a FACT.
// Resolving that needs a cross-record type lookup the decoder does not have,
// so the word is carried raw and the ownership consumer (#177) decides.
//
// References:
//   UESP "Skyrim Mod:Mod File Format/CONT"
//     https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format/CONT
//   xEdit dev-4.1.6 Core/wbDefinitionsTES5.pas: `wbCOED` line 2305, `wbCNTO`
//     2315, `wbCOCT` 2329, `wbRecord(CONT, ...)` 4505.
// Layout documented in docs/formats/records.md.

import Foundation

nonisolated struct Container {
    /// One CNTO entry with the COED extra data that followed it, if any.
    struct Entry: Equatable {
        /// The item placed in the container. xEdit constrains it to the
        /// carryable families plus LVLI, so a leveled list is legal here and
        /// the inventory runtime expands it (#176).
        let item: FormID
        /// Stack count. Signed on disk; vanilla never writes a negative.
        let count: Int32
        /// COED owner — an NPC_ or FACT. Nil when the entry is unowned.
        let owner: FormID?
        /// COED union word: a GLOB FormID for an NPC_ owner, a required
        /// faction rank for a FACT owner. Raw because the decoder cannot tell
        /// which without resolving `owner`'s record type.
        let ownerCondition: UInt32?
        /// COED item condition (health fraction).
        let condition: Float?
    }

    struct Flags: OptionSet, Equatable {
        let rawValue: UInt8

        /// Play the open/close sounds even though the model has an animation.
        static let allowSoundsWhenAnimation = Flags(rawValue: 0x01)
        static let respawns = Flags(rawValue: 0x02)
        static let showOwner = Flags(rawValue: 0x04)
    }

    /// The shared MSTT/TREE/FURN/ACTI/CONT/DOOR decode — name, model, sounds.
    let base: ModelBase
    /// CNTO entries in file order.
    let entries: [Entry]
    /// COCT as written; nil when absent. Diagnostics only.
    let declaredEntryCount: UInt32?
    /// DATA flags byte. The float that follows it in the struct is documented
    /// as a misaligned weight and is always 0, so it is not decoded.
    let flags: Flags

    var formID: FormID {
        base.formID
    }

    /// True when COCT is present and disagrees with the CNTO fields decoded.
    var entryCountMismatch: Bool {
        guard let declaredEntryCount else { return false }
        return Int(declaredEntryCount) != entries.count
    }

    init(record: ESMRecord, localized: Bool = false) throws {
        guard record.type == "CONT" else {
            throw ESMError.malformed("expected CONT record, got \(record.type)")
        }
        base = try ModelBase(record: record, localized: localized)

        var contents = Contents()
        for field in try record.fields() {
            try contents.decode(field: field)
        }
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

        mutating func decode(field: ESMField) throws {
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
                break
            }
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
