import Foundation
import OpenSkyFormatsCore

/// One XLKR linked-reference entry. A null or absent keyword reads as
/// `keyword == nil`. An 8-byte slot 0 is always read as a keyword, as in
/// Skyrim.esm. Evidence: docs/formats/placed-references.md.
nonisolated public struct LinkedReference: Equatable, Sendable {
    /// KYWD tagging the link (`LinkCarryStart`, `LinkCarryEnd`, ...).
    /// `nil` when the link carries no keyword.
    public let keyword: FormID?
    /// The reference this REFR links to — a REFR/ACHR/PLYR in practice.
    public let ref: FormID
}

nonisolated extension LinkedReference {
    /// Decodes one XLKR payload (8 bytes: keyword, then ref; 4 bytes: ref) and
    /// appends it. Never throws: a bad payload costs one link, while a bad XTEL
    /// would move a door. Other lengths are skipped; extra bytes are ignored.
    static func append(
        _ data: Data,
        to links: inout [Self]
    ) {
        var reader = BinaryReader(data)
        guard let first = attempt({ try FormID(reader.readUInt32()) }) else { return }
        if data.count >= 8, let second = attempt({ try FormID(reader.readUInt32()) }) {
            links.append(Self(keyword: first.isNull ? nil : first, ref: second))
        } else {
            links.append(Self(keyword: nil, ref: first))
        }
    }
}
