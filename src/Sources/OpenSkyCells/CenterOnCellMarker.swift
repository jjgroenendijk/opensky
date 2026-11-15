// Where `coc` puts the player in a cell (docs/engine/center-on-cell.md).

import OpenSkyFormatsCore
public import OpenSkyFormatsESM

nonisolated public enum CenterOnCellMarker {
    /// Engine STAT records in `Skyrim.esm`, read from the install's `EDID` fields.
    static let cocMarkerHeading = FormID(0x32)
    static let xMarkerHeading = FormID(0x34)
    static let xMarker = FormID(0x3B)

    /// What the rule needs to know about the records behind the cell's references.
    public struct Records: Sendable {
        /// Whether a base object is a `STAT`.
        public let isStatic: @Sendable (FormID) -> Bool
        /// Where a player arriving through a load door in this cell stands.
        public let arrival: @Sendable (PlacedReference) -> PlacedReference.Placement?

        public init(
            isStatic: @escaping @Sendable (FormID) -> Bool,
            arrival: @escaping @Sendable (PlacedReference) -> PlacedReference.Placement?
        ) {
            self.isStatic = isStatic
            self.arrival = arrival
        }

        /// Records that know of no statics and no doors: only the markers count.
        public static let markersOnly = Records(isStatic: { _ in false }, arrival: { _ in nil })
    }

    /// Nil only when the cell has no reference; `coc` then uses the cell's middle.
    /// Only the two heading markers keep their rotation.
    public static func placement(
        in references: [PlacedReference],
        records: Records = .markersOnly
    ) -> PlacedReference.Placement? {
        if
            let heading = newest(references, base: cocMarkerHeading)
            ?? newest(references, base: xMarkerHeading)
        {
            return heading.placement
        }
        if let marker = newest(references, base: xMarker) {
            return facingNorth(marker.placement.position)
        }
        let arrivals = references.compactMap { door in
            records.arrival(door).map { (door: door.formID, position: $0.position) }
        }
        if let arrival = arrivals.max(by: { $0.door.rawValue < $1.door.rawValue }) {
            return facingNorth(arrival.position)
        }
        let statics = references.filter { records.isStatic($0.base) }
        return newest(statics.isEmpty ? references : statics).map {
            facingNorth($0.placement.position)
        }
    }

    /// The game meets references in an order no data gives, so OpenSky takes the
    /// highest FormID: a fixed choice.
    private static func newest(
        _ references: [PlacedReference],
        base: FormID? = nil
    ) -> PlacedReference? {
        references
            .filter { reference in base.map { reference.base == $0 } ?? true }
            .max { $0.formID.rawValue < $1.formID.rawValue }
    }

    private static func facingNorth(_ position: SIMD3<Float>) -> PlacedReference.Placement {
        PlacedReference.Placement(position: position, rotation: .zero)
    }
}
