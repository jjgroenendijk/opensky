// The shell around `HazardRuntime`: cells add and drop their placed hazards, each
// frame steps the runtime, and every hit lands through `SpellHitApplying`, the
// path spells and enchantments use. See docs/engine/traps.md.

import Foundation
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagicInterface
import OpenSkyPhysics

/// What the hazard coordinator reads from the rest of the game.
@MainActor
public protocol HazardWorld: AnyObject, SpellHitApplying {
    /// Every actor a hazard may hit, the player included, as capsules.
    func hazardCandidates() -> [MeleeTarget]
    /// The spell as a payload sourced to the hazard, or nil when it cannot resolve.
    func hazardPayload(spell: ReferenceKey, hazard: ReferenceKey) -> SpellPayload?
}

/// A placed hazard as a cell build hands it over.
nonisolated public struct HazardPlacement: Equatable, Sendable {
    public let id: ReferenceKey
    public let spec: HazardSpec
    public let position: SIMD3<Float>

    public init(id: ReferenceKey, spec: HazardSpec, position: SIMD3<Float>) {
        self.id = id
        self.spec = spec
        self.position = position
    }
}

/// The last hit one hazard landed, for the sidebar.
nonisolated public struct HazardHitRecord: Equatable, Sendable {
    public let targets: [ReferenceKey]
    public let applied: Int
}

@MainActor
public final class HazardCoordinator {
    public weak var world: (any HazardWorld)?
    public private(set) var runtime = HazardRuntime()
    public private(set) var lastHits: [ReferenceKey: HazardHitRecord] = [:]
    public private(set) var hitTotal = 0
    public private(set) var unresolvedSpellTotal = 0

    public init() {}

    /// Replaces the hazards `cell` placed with `placements`, so a rebuild after an
    /// enable change adds and drops hazards in one step.
    public func load(_ placements: [HazardPlacement], in cell: CellSceneLocation) {
        runtime.removeAll(placedIn: cell)
        for placement in placements {
            runtime.place(
                placement.spec, id: placement.id, at: placement.position, source: .placed(cell)
            )
        }
    }

    public func spawn(_ placement: HazardPlacement) {
        runtime.place(placement.spec, id: placement.id, at: placement.position, source: .spawned)
    }

    /// Advances every hazard by `seconds` of world time and applies its hits.
    public func step(_ seconds: Float) {
        guard let world, !runtime.active.isEmpty else { return }
        let hits = runtime.step(seconds, candidates: world.hazardCandidates())
        for hit in hits {
            guard
                let spell = hit.spec.spell,
                let payload = world.hazardPayload(spell: spell, hazard: hit.hazard)
            else {
                unresolvedSpellTotal += 1
                continue
            }
            let report = world.applySpellHit(SpellHit(payload: payload, targets: hit.targets))
            hitTotal += 1
            lastHits[hit.hazard] = HazardHitRecord(
                targets: hit.targets.map(\.key),
                applied: report.storedCount
            )
        }
    }
}

extension HazardCoordinator {
    /// The live hazards for the Traps section, by name.
    public var hazardRows: [TrapHazardRow] {
        runtime.active.values
            .sorted { ($0.spec.name, $0.id.description) < ($1.spec.name, $1.id.description) }
            .map { hazard in
                let hit = lastHits[hazard.id]
                return TrapHazardRow(
                    name: hazard.spec.name,
                    remainingLifetime: hazard.remainingLifetime,
                    lastHitTargets: hit?.targets.count ?? 0,
                    lastHitEffects: hit?.applied ?? 0,
                    position: hazard.position,
                    tickCount: hazard.tickCount
                )
            }
    }
}
