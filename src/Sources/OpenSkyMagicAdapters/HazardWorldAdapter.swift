// App side of `HazardCoordinator`: live cells hand over their enabled `PHZD`
// hazards, each unpaused frame steps the runtime, and hits land through the
// magic coordinator. The rules live in the coordinator (docs/engine/traps.md).

import Foundation
import OpenSkyCells
import OpenSkyCombatInterface
public import OpenSkyFormatsESM
public import OpenSkyGameData
public import OpenSkyMagic
public import OpenSkyMagicInterface
public import OpenSkyPhysics
import OpenSkyPlayer
public import OpenSkySessionInterface
public import OpenSkyWorld
import OpenSkyWorldInterface

/// What the hazard adapter reads. The session is a closure, because a reload
/// replaces it.
public struct HazardWorldDependencies {
    public let hazards: () -> HazardCoordinator
    public let combat: any CombatPort
    /// A closure, because session start replaces the coordinator.
    public let magic: () -> MagicCoordinator
    public let spellHits: () -> any SpellHitApplying
    public let gameSession: () -> GameSession?

    public init(
        hazards: @escaping () -> HazardCoordinator,
        combat: any CombatPort,
        magic: @escaping () -> MagicCoordinator,
        spellHits: @escaping () -> any SpellHitApplying,
        gameSession: @escaping () -> GameSession?
    ) {
        self.hazards = hazards
        self.combat = combat
        self.magic = magic
        self.spellHits = spellHits
        self.gameSession = gameSession
    }
}

/// Answers `HazardWorld` from the session systems it is given.
public final class HazardWorldAdapter {
    /// A long frame steps as this, so a stall does not stack several hits.
    public static let longestStep: Float = 0.25

    private let dependencies: HazardWorldDependencies
    public private(set) var store: HazardStore?
    var lastFrame: Date?

    public init(_ dependencies: HazardWorldDependencies) {
        self.dependencies = dependencies
    }

    /// Without a stage, as in a test, it registers nothing.
    public convenience init(_ dependencies: HazardWorldDependencies, stage: SessionStage?) {
        self.init(dependencies)
        guard let stage else { return }
        store = stage.data.lockTrapData.hazards
        stage.streamer.cellHazards.register(.hazards) { [weak self] event in
            self?.load(event)
        }
        let gameSession = stage.gameSession
        gameSession.frameSteps.register(.hazards) { [weak self, weak gameSession] _ in
            self?.tick(paused: gameSession?.worldSimPaused ?? true)
        }
    }

    public var hazards: HazardCoordinator {
        dependencies.hazards()
    }

    func load(_ event: CellHazardEvent) {
        let placements = event.hazards.compactMap { hazard -> HazardPlacement? in
            guard let key = hazard.hazardKey, let spec = store?.spec(for: key) else { return nil }
            return HazardPlacement(id: hazard.key, spec: spec, position: hazard.position)
        }
        hazards.load(placements, in: event.location)
    }

    /// Steps by wall-clock time, and not at all while a menu pauses the world.
    func tick(paused: Bool, now: Date = Date()) {
        defer { lastFrame = paused ? nil : now }
        guard !paused, let lastFrame else { return }
        let seconds = Float(now.timeIntervalSince(lastFrame))
        hazards.step(min(seconds, Self.longestStep))
    }
}

extension HazardWorldAdapter {
    public func hazardSpec(for key: ReferenceKey) -> HazardSpec? {
        store?.spec(for: key)
    }

    public func hazardModelPath(for key: ReferenceKey) -> String? {
        store?.modelPath(for: key)
    }
}

extension HazardWorldAdapter: HazardWorld {
    public func hazardCandidates() -> [MeleeTarget] {
        var targets = dependencies.combat.projectileTargets()
        if
            !targets.contains(where: { $0.key == .player }),
            let feet = dependencies.gameSession()?.locomotion.status.feetPosition
        {
            targets.append(MeleeTarget(key: .player, feet: feet))
        }
        return targets
    }

    public func hazardPayload(spell: ReferenceKey, hazard: ReferenceKey) -> SpellPayload? {
        dependencies.magic().caster?.spellbookAccess.record(spell)?.payload(caster: hazard)
    }

    public func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        dependencies.spellHits().applySpellHit(hit)
    }
}

extension HazardWorldAdapter: HazardWorldPort {}
