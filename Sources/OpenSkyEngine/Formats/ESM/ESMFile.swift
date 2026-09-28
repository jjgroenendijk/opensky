// Plugin (.esm/.esp/.esl) container walk: one TES4 header record followed by
// top-level GRUPs. Init indexes group extents only — Skyrim.esm is ~250 MB, so
// the file is memory-mapped and record payloads parse on demand.
//
// Reference: UESP "Skyrim Mod:Mod File Format"
//   https://en.uesp.net/wiki/Skyrim_Mod:Mod_File_Format
// Layout documented in docs/formats/esm.md.

import Foundation

nonisolated struct ESMFile {
    /// TES4 plugin-info record (HEDR, masters, description).
    let tes4: ESMRecord
    /// Top-level groups in file order (~118 in Skyrim.esm).
    let topGroups: [ESMGroup]

    /// Memory-maps the plugin; nothing beyond top-level headers is read.
    init(url: URL) throws {
        // `mappedIfSafe` may copy external-volume files into anonymous RAM.
        // Game installs are commonly on USB volumes, so mapping is mandatory.
        try self.init(data: Data(contentsOf: url, options: .alwaysMapped))
    }

    init(data: Data) throws {
        let children = try ESMGroup.parseChildren(in: data, range: 0 ..< data.count)
        guard case let .record(first)? = children.first, first.type == "TES4" else {
            throw ESMError.missingTES4
        }
        tes4 = first
        topGroups = try children.dropFirst().map { child in
            guard case let .group(group) = child else {
                throw ESMError.malformed("record outside any group at top level")
            }
            return group
        }
    }

    /// First top group holding `recordType` records (e.g. "WRLD").
    func topGroup(of recordType: FourCC) -> ESMGroup? {
        topGroups.first { $0.recordType == recordType }
    }
}
