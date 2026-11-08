// Where `coc` puts the player in a cell: its `COCMarkerHeading`, else the most recently
// placed `XMarkerHeading` or `XMarker` (https://ck.uesp.net/wiki/CenterOnCell).

import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public enum CenterOnCellMarker {
    /// Engine STAT records in `Skyrim.esm`, read from the install's `EDID` fields.
    static let cocMarkerHeading = FormID(0x32)
    static let xMarkerHeading = FormID(0x34)
    static let xMarker = FormID(0x3B)

    /// Nil when the cell places none of the three markers; `coc` then uses the cell centre.
    public static func placement(in references: [PlacedReference]) -> PlacedReference.Placement? {
        let headings = references.filter { $0.base == cocMarkerHeading }
        let candidates = headings.isEmpty
            ? references.filter { $0.base == xMarkerHeading || $0.base == xMarker }
            : headings
        // The editor numbers new references upwards, so the highest FormID was placed last.
        return candidates.max { $0.formID.rawValue < $1.formID.rawValue }?.placement
    }
}
