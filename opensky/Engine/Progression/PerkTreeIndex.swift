// Where each perk sits in a skill's AVIF perk tree (issue #499, roadmap item
// 20.6): the load-order-wide map from a PERK identity to the box that grants
// it, and to the boxes whose lines reach that box.
//
// Built once beside `PerkStore` and `ActorValueInformationStore`, in the shape
// every `*Index` here takes: immutable, cheap to copy, and answering one
// question. Spending a perk point asks it twice — "is this perk in a tree at
// all?" and "which boxes are its parents?" — and neither answer may cost a walk
// of every AVIF record.
//
// ## Which direction a connection points
//
// From parent to child. A node's `CNAM` run is "Line to Index"
// (xEdit dev-4.1.6 `wbRArray('Connections', wbInteger(CNAM, 'Line to Index'))`),
// and this machine's `AVOneHanded` reads:
//
//   #0  perk NULL,        lines to [7]
//   #7  perk Armsman00,   lines to [4, 3, 5, 1, 6]
//   #1  perk FightingStance, lines to [2, 11]
//
// measured 2026-08-20 with `openskycli record AVOneHanded`. The tree's entry
// node is `#0`, it grants no perk, and it is what `Armsman00` hangs from — so
// the first real box of every vanilla tree has a parent that costs nothing to
// own. Parents are therefore collected by inverting the connection run, and a
// node reached from the root node needs no owned parent.
//
// Documented in docs/engine/character-leveling.md.

import Foundation

/// One perk's place in the tree that grants it.
nonisolated struct PerkTreePlacement: Equatable, Sendable {
    /// The AVIF record whose tree carries the box.
    let skill: ResolvedFormID
    /// The actor-value index that AVIF names, when it names a vanilla one. What
    /// a skill requirement is stated against, and what a readout groups by.
    let actorValueIndex: Int32?
    /// The box's own `INAM` identity inside the tree.
    let node: UInt32
    /// Whether the box's `FNAM` asks for a parent.
    let requiresParent: Bool
    /// Perks whose boxes draw a line to this one.
    let parents: [ReferenceKey]
    /// Whether the tree's entry node is one of those boxes, which is what makes
    /// the first real perk of a tree reachable with nothing owned.
    let reachableFromRoot: Bool
}

/// Load-order-wide map from a perk to its box.
nonisolated struct PerkTreeIndex {
    private let placements: [ReferenceKey: PerkTreePlacement]

    /// Nothing at all, which is what a synthetic session with no AVIF records
    /// carries. Every perk is then outside every tree, and a spend is refused
    /// with a reason rather than accepted against a tree that does not exist.
    static let empty = PerkTreeIndex(placements: [:])

    private init(placements: [ReferenceKey: PerkTreePlacement]) {
        self.placements = placements
    }

    /// Builds the map from every AVIF record carrying a perk tree.
    ///
    /// A `PNAM` this load order carries no PERK for is skipped: it is a
    /// dangling link rather than an error, exactly as a dangling `PRKR` is.
    init(information: ActorValueInformationStore, perks: PerkStore) {
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
                    skill: record.id,
                    actorValueIndex: record.actorValueIndex,
                    node: node.index,
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
    func placement(of perk: ReferenceKey) -> PerkTreePlacement? {
        placements[perk]
    }

    var count: Int {
        placements.count
    }
}
