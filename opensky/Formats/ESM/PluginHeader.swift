// TES4 plugin-info record decoded into engine types: HEDR stats, author /
// description strings, master list (MAST entries, file order). The master
// list is what gives raw FormIDs meaning — see FormID.swift.
//
// Reference: UESP "Skyrim Mod:Mod File Format" — TES4 record.
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format
// Layout documented in docs/formats/formid.md.

import Foundation

nonisolated struct PluginHeader {
    /// HEDR field (12 bytes): file stats written by the CK.
    struct Stats {
        /// 0.94/1.7 = original Skyrim, 1.71 = SSE with extended header usage.
        let version: Float
        /// Record + group count (CK-maintained; not trusted for traversal).
        let recordCount: Int32
        /// Next object ID the CK would assign in this plugin.
        let nextObjectID: UInt32
    }

    /// Record flags of the TES4 record (esm / localized / esl bits).
    let flags: ESMRecord.Flags
    let stats: Stats
    /// CNAM zstring, absent in most vanilla masters.
    let author: String?
    /// SNAM zstring.
    let description: String?
    /// MAST zstrings in file order; index order defines FormID master indices.
    let masters: [String]

    /// Whether FormIDs in strings-bearing fields point into lstring tables
    /// (`Strings/<plugin>_<lang>.strings` etc.) instead of inline text.
    var isLocalized: Bool {
        flags.contains(.localized)
    }

    init(tes4: ESMRecord) throws {
        guard tes4.type == "TES4" else {
            throw ESMError.malformed("expected TES4 record, got \(tes4.type)")
        }
        flags = tes4.flags

        var stats: Stats?
        var author: String?
        var description: String?
        var masters: [String] = []
        for field in try tes4.fields() {
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
                // DATA (per-master uint64, always 0), ONAM, INTV, INCC, and
                // any modder additions carry nothing OpenSky needs yet.
                break
            }
        }
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
    func formIDResolver(pluginName: String) -> FormIDResolver {
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

extension ESMFile {
    /// Decodes the TES4 record. Cheap (one small record) but not cached —
    /// callers keep the result.
    func pluginHeader() throws -> PluginHeader {
        try PluginHeader(tes4: tes4)
    }
}
