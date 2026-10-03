// App side of `HazardCoordinator`: live cells hand over their enabled `PHZD`
// hazards, each unpaused frame steps the runtime, and hits land through the
// magic coordinator. The rules live in the coordinator (docs/engine/traps.md).

import Foundation
import OpenSkyCombat
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyMagicInterface
import OpenSkyPhysics
import OpenSkyRendering
import OpenSkyWorld

/// Answers `HazardWorld` from the session systems `game` owns.
final class HazardWorldAdapter {
    /// A long frame steps as this, so a stall does not stack several hits.
    static let longestStep: Float = 0.25

    unowned let game: GameViewController
    private(set) var store: HazardStore?
    private var lastFrame: Date?

    init(game: GameViewController) {
        self.game = game
    }

    var hazards: HazardCoordinator {
        game.hazards
    }

    func wireHazards(provider: any WorldDataProviding, streamer: CellStreamer, renderer: Renderer) {
        store = (provider as? LockTrapDataProviding)?.lockTrapData.hazards
        hazards.world = self
        streamer.cellHazards.add { [weak self] event in
            self?.load(event)
        }
        renderer.onFrame.add { [weak self, weak renderer] _ in
            self?.tick(paused: renderer?.worldSimPaused ?? true)
        }
    }

    private func load(_ event: CellHazardEvent) {
        let placements = event.hazards.compactMap { hazard -> HazardPlacement? in
            guard let key = hazard.hazardKey, let spec = store?.spec(for: key) else { return nil }
            return HazardPlacement(id: hazard.key, spec: spec, position: hazard.position)
        }
        hazards.load(placements, in: event.location)
    }

    /// Steps by wall-clock time, and not at all while a menu pauses the world.
    private func tick(paused: Bool, now: Date = Date()) {
        defer { lastFrame = paused ? nil : now }
        guard !paused, let lastFrame else { return }
        let seconds = Float(now.timeIntervalSince(lastFrame))
        hazards.step(min(seconds, Self.longestStep))
    }
}

extension HazardWorldAdapter: HazardWorld {
    func hazardCandidates() -> [MeleeTarget] {
        var targets = game.combat.projectileTargets()
        if
            !targets.contains(where: { $0.key == .player }),
            let feet = game.renderer?.locomotion.status.feetPosition
        {
            targets.append(MeleeTarget(key: .player, feet: feet))
        }
        return targets
    }

    func hazardPayload(spell: ReferenceKey, hazard: ReferenceKey) -> SpellPayload? {
        game.magic.caster?.spellbookAccess.record(spell)?.payload(caster: hazard)
    }

    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        game.magic.applySpellHit(hit)
    }
}
