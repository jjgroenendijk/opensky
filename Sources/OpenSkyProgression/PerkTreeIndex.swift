// Where each perk sits in a skill's AVIF perk tree: PERK identity to its box and
// to the boxes whose lines reach it. Connections point from parent to child
// (`CNAM` "Line to Index"). The root node `#0` grants no perk, so the first real
// box needs no owned parent. See docs/engine/character-leveling.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData

/// One perk's place in the tree that grants it.
nonisolated public struct PerkTreePlacement: Equatable, Sendable {
    /// The actor-value index that AVIF names, when it names a vanilla one. What
    /// a skill requirement is stated against, and what a readout groups by.
    public let actorValueIndex: Int32?
    /// Whether the box's `FNAM` asks for a parent.
    public let requiresParent: Bool
    /// Perks whose boxes draw a line to this one.
    public let parents: [ReferenceKey]
    /// Whether the tree's entry node is one of those boxes, which is what makes
    /// the first real perk of a tree reachable with nothing owned.
    public let reachableFromRoot: Bool
}

/// Load-order-wide map from a perk to its box.
nonisolated public struct PerkTreeIndex: Sendable {
    private let placements: [ReferenceKey: PerkTreePlacement]

    /// Nothing at all, which is what a synthetic session with no AVIF records
    /// carries. Every perk is then outside every tree, and a spend is refused
    /// with a reason rather than accepted against a tree that does not exist.
    public static let empty = PerkTreeIndex(placements: [:])

    private init(placements: [ReferenceKey: PerkTreePlacement]) {
        self.placements = placements
    }

    /// Builds the map from every AVIF record carrying a perk tree.
    ///
    /// A `PNAM` this load order carries no PERK for is skipped: it is a
    /// dangling link rather than an error, exactly as a dangling `PRKR` is.
    public init(information: ActorValueInformationStore, perks: PerkStore) {
        var placements: [ReferenceKey: PerkTreePlacement] = [:]
        for record in information.perkTreeRecords {
            let tree = record.information.perkTree
            let plugin = record.sourcePlugin
            // Node identity to the perk it grants, so the inverted connection
            // run can be spelled in perk keys rather than in `INAM` numbers.
            var perkByNode: [UInt32: ReferenceKey] = [:]
            var rootNodes: Set<UInt32> = []
            for node in tree {
                guard
                    let link = node.perk,
                    let resolved = perks.resolve(link, fromPlugin: plugin)
                else {
                    rootNodes.insert(node.index)
                    continue
                }
                perkByNode[node.index] = ReferenceKey(resolved: resolved.id)
            }
            for node in tree {
                guard let perk = perkByNode[node.index] else { continue }
                let incoming = tree.filter { $0.connections.contains(node.index) }
                placements[perk] = PerkTreePlacement(
                    actorValueIndex: record.actorValueIndex,
                    requiresParent: node.parentRequired,
                    parents: incoming.compactMap { perkByNode[$0.index] },
                    reachableFromRoot: incoming.contains { rootNodes.contains($0.index) }
                )
            }
        }
        self.init(placements: placements)
    }

    /// Where `perk` sits, or nil when no tree in this load order grants it —
    /// which is every quest perk, every ability the game hands out directly,
    /// and every perk in a session with no AVIF records.
    public func placement(of perk: ReferenceKey) -> PerkTreePlacement? {
        placements[perk]
    }

    public var count: Int {
        placements.count
    }
}
