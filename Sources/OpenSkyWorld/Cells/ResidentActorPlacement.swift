import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyWorldState

/// What per-frame actor systems need about one resident ACHR: its NPC_ base and
/// the cell that holds it. Small, so a lookup copies no decoded record.
nonisolated public struct ResidentActorPlacement: Equatable, Sendable {
    public let base: FormID
    public let cell: CellSceneLocation?

    public init(base: FormID, cell: CellSceneLocation?) {
        self.base = base
        self.cell = cell
    }

    /// Every ACHR in `cells`, keyed by reference. The first cell wins, as in the
    /// grid-order reference lookups.
    static func index(
        _ cells: [(location: CellSceneLocation?, references: RuntimeReferenceIndex)]
    ) -> [ReferenceKey: ResidentActorPlacement] {
        var index: [ReferenceKey: ResidentActorPlacement] = [:]
        for cell in cells {
            for entry in cell.references.sortedActorEntries where index[entry.key] == nil {
                guard let actor = entry.placedActor else { continue }
                index[entry.key] = ResidentActorPlacement(base: actor.base, cell: cell.location)
            }
        }
        return index
    }
}
