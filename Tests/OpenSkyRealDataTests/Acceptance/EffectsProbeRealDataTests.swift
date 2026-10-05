// Effect probes on the real load order: a projectile's explosion detonates with
// damage and sound, an explosion's hazard hurts an actor once per interval, and a
// dungeon's acoustic space gives a reverb the exterior does not. The report goes
// to `.logs/m26-effects-probe.log`; it names records and numbers only.

import Foundation
@testable import OpenSkyAudio
@testable import OpenSkyCombat
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
@testable import OpenSkyPhysics
import simd
import TagsTesting
import Testing

@MainActor
@Suite(.tags(.acceptance))
struct EffectsProbeRealDataTests {
    /// A Bleak Falls Barrow dungeon cell, and the vanilla exterior the audio
    /// acceptance walks.
    private static let dungeonEditorID = "BleakFallsBarrow01"
    private static let exteriorEditorID = "ChillfurrowFarmExterior"
    private static let npc = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0xFF00_0700)

    private struct Install {
        let plugins: [(name: String, file: ESMFile)]
        let base: ESMFile
        let records: EffectRecordStore

        init() throws {
            let root = try #require(RealDataEnvironment.dataRoot)
            plugins = ActivePluginFiles.load(root: root)
            base = try #require(plugins.first?.file)
            records = EffectRecordStore(plugins: plugins)
        }

        @MainActor
        func explosions(world: ProbeExplosionWorld) -> ExplosionRuntime {
            let runtime = ExplosionRuntime()
            runtime.records = records
            runtime.itemPlugin = "Skyrim.esm"
            runtime.world = world
            return runtime
        }
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aProjectileExplosionDamagesAndSounds() throws {
        let install = try Install()
        let items = ItemDefinitionStore(file: install.base)
        let world = ProbeExplosionWorld(npc: Self.npc)
        let explosions = install.explosions(world: world)
        let found = items.projectiles.values
            .sorted { ($0.editorID ?? "") < ($1.editorID ?? "") }
            .lazy
            .compactMap { projectile in
                explosions.spec(itemLink: projectile.explosion).map { (projectile, $0) }
            }
            .first { $0.1.damage > 0 && !$0.1.sounds.isEmpty }
        let (projectile, spec) = try #require(found, "no PROJ names an EXPL with damage and sound")
        let report = withExtendedLifetime(world) {
            explosions.detonate(spec, at: SIMD3(0, 0, 60), cause: .projectile)
        }
        #expect(report.damaged[Self.npc, default: 0] > 0)
        #expect(report.soundsPlayed > 0)
        try Self.append([
            "projectile\t\(projectile.editorID ?? "?") -> \(spec.name)",
            "explosion damage\t\(spec.damage) in \(spec.radius) units",
            "actor damaged\t\(report.damaged[Self.npc] ?? 0) at 50 units",
            "sounds played\t\(report.soundsPlayed) "
                + "(\(world.sounds.map(\.description).joined(separator: ", ")))"
        ])
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func anExplosionHazardHurtsAnActorOnItsInterval() throws {
        let install = try Install()
        let hazards = HazardStore(plugins: install.plugins)
        let spells = SpellStore(plugins: install.plugins)
        let blast = ProbeExplosionWorld(npc: Self.npc)
        let explosions = install.explosions(world: blast)
        let found = install.records.explosions.records
            .sorted { ($0.record.editorID ?? "") < ($1.record.editorID ?? "") }
            .lazy
            .compactMap { explosions.spec(for: ReferenceKey(resolved: $0.id)) }
            .compactMap { spec -> (ExplosionSpec, HazardSpec)? in
                guard
                    case let .hazard(key)? = spec.placement, let hazard = hazards.spec(for: key),
                    hazard.spell != nil, hazard.targetInterval > 0 else { return nil }
                return (spec, hazard)
            }
            .first
        let (spec, hazard) = try #require(found, "no EXPL places a HAZD with a spell")
        withExtendedLifetime(blast) { _ = explosions.detonate(spec, at: .zero, cause: .debug) }
        #expect(blast.hazards == [hazard.hazard])

        let actor = ProbeHazardWorld(spells: spells, npc: Self.npc)
        let coordinator = HazardCoordinator()
        coordinator.world = actor
        coordinator.spawn(HazardPlacement(
            id: .generated(0x8000_0001), spec: hazard, position: .zero
        ))
        let seconds = min(hazard.lifetime > 0 ? hazard.lifetime : 3, 3) - 0.05
        var elapsed: Float = 0
        while elapsed < seconds {
            coordinator.step(0.05)
            elapsed += 0.05
        }
        let expected = Int(seconds / max(hazard.targetInterval, HazardSpec.minimumInterval)) + 1
        #expect(actor.hits.count >= 2)
        #expect(
            abs(actor.hits.count - expected) <= 1,
            "hits \(actor.hits.count), expected \(expected)"
        )
        let magnitudes = actor.hits.first?.payload.entries.map(\.magnitude) ?? []
        try Self.append([
            "hazard\t\(hazard.name) from \(spec.name), every \(hazard.targetInterval) s",
            "hazard spell\t\(actor.hits.first?.payload.spell.description ?? "none"), "
                + "magnitudes \(magnitudes)",
            "hazard hits on the actor\t\(actor.hits.count) in \(seconds) s"
        ])
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func aDungeonHasReverbAndTheExteriorDoesNot() throws {
        let install = try Install()
        let spaces = AcousticSpaceStore(file: install.base)
        let localized = (try? install.base.pluginHeader().isLocalized) ?? false
        var cells: [String: Cell] = [:]
        ESMWalk.forEachRecord(in: install.base) { record in
            if
                record.type == "CELL", let editorID = ESMWalk.editorID(of: record),
                [Self.dungeonEditorID, Self.exteriorEditorID].contains(editorID)
            {
                cells[editorID] = try? Cell(record: record, localized: localized)
            }
            return cells.count < 2
        }
        func setting(_ editorID: String) throws -> (ReverbSetting, String) {
            let cell = try #require(cells[editorID], "no CELL \(editorID)")
            let space = cell.acousticSpace.flatMap { spaces.acousticSpace($0) }
            let record = space?.reverbModel.flatMap {
                install.records.reverbs.resolve($0, fromPlugin: "Skyrim.esm")?.record
            }
            return (ReverbSetting(record: record), ReverbReadout.recordLine(record))
        }
        let (dungeon, dungeonLine) = try setting(Self.dungeonEditorID)
        let (exterior, exteriorLine) = try setting(Self.exteriorEditorID)
        #expect(exterior.isOff)
        #expect(!dungeon.isOff)
        try Self.append([
            "reverb exterior \(Self.exteriorEditorID)\t\(Self.describe(exterior)); \(exteriorLine)",
            "reverb dungeon \(Self.dungeonEditorID)\t\(Self.describe(dungeon)); \(dungeonLine)"
        ])
    }

    private static func describe(_ setting: ReverbSetting) -> String {
        guard let room = setting.room else { return "off" }
        return "\(room.rawValue), wet \(setting.level) dB"
    }

    private static func append(_ lines: [String]) throws {
        let logs = try RepositoryLogs.directory()
        try FileManager.default.createDirectory(at: logs, withIntermediateDirectories: true)
        let url = logs.appending(path: "m26-effects-probe.log")
        let text = lines.joined(separator: "\n") + "\n"
        print(text)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: Data(text.utf8))
        } else {
            try text.write(to: url, atomically: true, encoding: .utf8)
        }
    }
}

/// One actor 50 units from the blast; records what the explosion does.
@MainActor
private final class ProbeExplosionWorld: ExplosionWorld {
    let npc: ReferenceKey
    private(set) var sounds: [ReferenceKey] = []
    private(set) var hazards: [ReferenceKey] = []

    init(npc: ReferenceKey) {
        self.npc = npc
    }

    func explosionTargets() -> [MeleeTarget] {
        [MeleeTarget(key: npc, feet: SIMD3(50, 0, 0))]
    }

    func explosionViewer() -> SIMD3<Float>? {
        nil
    }

    func applyExplosionDamage(_ amount: Float, to target: ReferenceKey) -> Bool {
        true
    }

    func playExplosionSound(_ sound: ReferenceKey, at position: SIMD3<Float>) {
        sounds.append(sound)
    }

    func startExplosionImageSpace(_ modifier: ReferenceKey, strength: Float) {}

    func placeExplosionHazard(_ hazard: ReferenceKey, at position: SIMD3<Float>) -> Bool {
        hazards.append(hazard)
        return true
    }

    func showExplosionModel(_ path: String, at position: SIMD3<Float>) {}
}

/// One actor standing in the hazard; records each landed hit.
@MainActor
private final class ProbeHazardWorld: HazardWorld {
    let spells: SpellStore
    let npc: ReferenceKey
    private(set) var hits: [SpellHit] = []

    init(spells: SpellStore, npc: ReferenceKey) {
        self.spells = spells
        self.npc = npc
    }

    func hazardCandidates() -> [MeleeTarget] {
        [MeleeTarget(key: npc, feet: SIMD3(10, 0, 0))]
    }

    func hazardPayload(spell: ReferenceKey, hazard: ReferenceKey) -> SpellPayload? {
        spells.spell(key: spell)?.payload(caster: hazard)
    }

    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        hits.append(hit)
        return SpellHitReport(targetCount: hit.targets.count, entryCount: hit.payload.entries.count)
    }
}
