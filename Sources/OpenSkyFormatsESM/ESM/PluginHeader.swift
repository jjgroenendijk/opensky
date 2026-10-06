// TES4 plugin-info record: HEDR stats, author, description, and the master list
// that gives raw FormIDs their meaning (FormID.swift).
// Reference: UESP "Skyrim Mod:Mod File Format" — TES4 record.
// Layout documented in docs/formats/formid.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct PluginHeader: Sendable {
    /// HEDR field (12 bytes): file stats written by the CK.
    public struct Stats: Sendable {
        /// 0.94/1.7 = original Skyrim, 1.71 = SSE with extended header usage.
        public let version: Float
        /// Record + group count (CK-maintained; not trusted for traversal).
        public let recordCount: Int32
        /// Next object ID the CK would assign in this plugin.
        public let nextObjectID: UInt32
    }

    /// Record flags of the TES4 record (esm / localized / esl bits).
    public let flags: ESMRecord.Flags
    public let stats: Stats
    /// CNAM zstring, absent in most vanilla masters.
    public let author: String?
    /// SNAM zstring.
    public let description: String?
    /// MAST zstrings in file order; index order defines FormID master indices.
    public let masters: [String]
    /// DATA after each MAST: 8 bytes xEdit leaves unexplained, kept raw.
    public let masterData: [UInt64]
    /// ONAM — the placed references and navmeshes this plugin overrides.
    public let overriddenForms: [FormID]
    /// SCRN screenshot and INTV, both unexplained, kept raw.
    public let screenshot: Data?
    public let intv: Data?
    /// INCC — interior cell count.
    public let interiorCellCount: UInt32?
    public let skipped: FieldTally

    /// Whether FormIDs in strings-bearing fields point into lstring tables
    /// (`Strings/<plugin>_<lang>.strings` etc.) instead of inline text.
    public var isLocalized: Bool {
        flags.contains(.localized)
    }

    public init(tes4: ESMRecord) throws {
        guard tes4.type == "TES4" else {
            throw ESMError.malformed("expected TES4 record, got \(tes4.type)")
        }
        flags = tes4.flags

        var stats: Stats?
        var author: String?
        var description: String?
        var masters: [String] = []
        var rest = try RecordFields(record: tes4, type: "TES4")
        try rest.readEach { field in
            switch field.type {
            case "HEDR":
                var reader = BinaryReader(field.data)
                stats = try Stats(
                    version: Float(bitPattern: reader.readUInt32()),
                    recordCount: Int32(bitPattern: reader.readUInt32()),
                    nextObjectID: reader.readUInt32()
                )
            case "CNAM":
                author = try Self.zstring(field, name: "CNAM")
            case "SNAM":
                description = try Self.zstring(field, name: "SNAM")
            case "MAST":
                try masters.append(Self.zstring(field, name: "MAST"))
            default:
                return false
            }
            return true
        }
        masterData = rest.readAll("DATA") { try $0.readUInt64() }
        overriddenForms = rest.formIDArray("ONAM")
        screenshot = rest.bytes("SCRN")
        intv = rest.bytes("INTV")
        interiorCellCount = rest.uint32("INCC")
        skipped = rest.finish()
        guard let stats else {
            throw ESMError.malformed("TES4 record has no HEDR field")
        }
        self.stats = stats
        self.author = author
        self.description = description
        self.masters = masters
    }

    /// Resolver for raw FormIDs found in this plugin's records. The plugin's
    /// own file name is not stored in the file, so the caller supplies it.
    public func formIDResolver(pluginName: String) -> FormIDResolver {
        FormIDResolver(pluginName: pluginName, masters: masters)
    }

    /// TES4 strings are null-terminated windows-1252, terminator included in
    /// the field size.
    private static func zstring(_ field: ESMField, name: String) throws -> String {
        var reader = BinaryReader(field.data)
        do {
            return try reader.readZString()
        } catch {
            throw ESMError.malformed("TES4 \(name) is not a valid zstring")
        }
    }
}

nonisolated extension ESMFile {
    /// Decodes the TES4 record. Cheap (one small record) but not cached —
    /// callers keep the result.
    public func pluginHeader() throws -> PluginHeader {
        try PluginHeader(tes4: tes4)
    }

    /// Reads only the TES4 record flags, so it cannot fail like `pluginHeader()`.
    public var isLocalized: Bool {
        tes4.flags.contains(.localized)
    }
}
