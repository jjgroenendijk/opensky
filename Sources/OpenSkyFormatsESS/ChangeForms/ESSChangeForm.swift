// One change form: a record's runtime change, as a ref id, change flags, a form type,
// a version, and data that may be zlib compressed. See docs/formats/ess-change-forms.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct ESSChangeForm: Equatable, Sendable {
    public let form: ESSRefID
    public let flags: UInt32
    /// The low six bits of the type byte, an index into `ESSChangeFormType`.
    public let typeIndex: UInt8
    /// Bytes each length takes: 1, 2, or 4.
    public let lengthSize: Int
    public let version: UInt8
    /// Stored bytes, compressed when `uncompressedLength` is not zero.
    public let storedData: Data
    public let uncompressedLength: UInt32

    public init(
        form: ESSRefID, flags: UInt32, typeIndex: UInt8, version: UInt8,
        data: ESSChangeFormData
    ) {
        self.form = form
        self.flags = flags
        self.typeIndex = typeIndex
        self.version = version
        storedData = data.stored
        uncompressedLength = data.uncompressedLength
        lengthSize = data.lengthSize
    }

    public var type: ESSChangeFormType? {
        ESSChangeFormType(index: typeIndex)
    }

    public var isCompressed: Bool {
        uncompressedLength != 0
    }

    /// The change data, inflated when compressed.
    public func data() throws(ESSError) -> Data {
        guard isCompressed else { return storedData }
        do {
            return try Zlib.decompress(storedData, decompressedSize: Int(uncompressedLength))
        } catch {
            throw .decompressionFailed(context: "change form \(form): \(error)")
        }
    }

    public func has(_ flag: UInt32) -> Bool {
        flags & flag != 0
    }

    static func read(_ reader: inout ESSReader, count: Int) throws(ESSError) -> [Self] {
        guard count * 10 <= reader.bytesRemaining else {
            throw .invalidCount(context: "change forms", count: count)
        }
        var forms: [Self] = []
        forms.reserveCapacity(count)
        for _ in 0 ..< count {
            try forms.append(readOne(&reader))
        }
        return forms
    }

    private static func readOne(_ reader: inout ESSReader) throws(ESSError) -> Self {
        let form = try reader.refID("change form id")
        let flags = try reader.uint32("change flags")
        let typeByte = try reader.uint8("change form type")
        let version = try reader.uint8("change form version")
        let lengthSize: Int
        switch typeByte >> 6 {
        case 0: lengthSize = 1
        case 1: lengthSize = 2
        case 2: lengthSize = 4
        default: throw .invalidValue(context: "change form \(form) length size bits are 3")
        }
        let length = try readLength(&reader, size: lengthSize)
        let uncompressed = try readLength(&reader, size: lengthSize)
        let stored = try reader.bytes(Int(length), "change form \(form) data")
        return Self(
            form: form, flags: flags, typeIndex: typeByte & 0x3F, version: version,
            data: ESSChangeFormData(
                stored: stored, uncompressedLength: uncompressed, lengthSize: lengthSize
            )
        )
    }

    private static func readLength(
        _ reader: inout ESSReader, size: Int
    ) throws(ESSError) -> UInt32 {
        switch size {
        case 1: try UInt32(reader.uint8("change form length"))
        case 2: try UInt32(reader.uint16("change form length"))
        default: try reader.uint32("change form length")
        }
    }
}

/// The stored bytes of a change form and how their lengths were written.
nonisolated public struct ESSChangeFormData: Equatable, Sendable {
    public let stored: Data
    /// Zero for uncompressed data.
    public let uncompressedLength: UInt32
    public let lengthSize: Int

    public init(stored: Data, uncompressedLength: UInt32 = 0, lengthSize: Int = 4) {
        self.stored = stored
        self.uncompressedLength = uncompressedLength
        self.lengthSize = lengthSize
    }
}

/// The change form type table: an index in the type byte names a record type.
nonisolated public struct ESSChangeFormType: Hashable, Sendable {
    public let index: UInt8
    /// The record signature, such as `REFR`.
    public let signature: String

    /// Index order from UESP "Save File Format", Change Form.
    public static let signatures = [
        "REFR", "ACHR", "PMIS", "PGRE", "PBEA", "PFLA", "CELL", "INFO", "QUST", "NPC_",
        "ACTI", "TACT", "ARMO", "BOOK", "CONT", "DOOR", "INGR", "LIGH", "MISC", "APPA",
        "STAT", "MSTT", "FURN", "WEAP", "AMMO", "KEYM", "ALCH", "IDLM", "NOTE", "ECZN",
        "CLAS", "FACT", "PACK", "NAVM", "WOOP", "MGEF", "SMQN", "SCEN", "LCTN", "RELA",
        "PHZD", "PBAR", "PCON", "FLST", "LVLN", "LVLI", "LVSP", "PARW", "ENCH"
    ]

    public init?(index: UInt8) {
        guard Int(index) < Self.signatures.count else { return nil }
        self.index = index
        signature = Self.signatures[Int(index)]
    }

    public init?(signature: String) {
        guard let index = Self.signatures.firstIndex(of: signature) else { return nil }
        self.init(index: UInt8(index))
    }

    /// Placed objects share the reference layout: an initial block, then flags.
    public var isReference: Bool {
        ["REFR", "ACHR", "PMIS", "PGRE", "PBEA", "PFLA", "PHZD", "PBAR", "PCON", "PARW"]
            .contains(signature)
    }

    public static func name(of index: UInt8) -> String {
        ESSChangeFormType(index: index)?.signature ?? "type \(index)"
    }
}
