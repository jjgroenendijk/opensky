// The headless session behind `TrapCellRealDataTests`: one built interior, the
// Papyrus world over the install's scripts, and the hazard coordinator with a
// recording world. Wired the way the app wires them, with the streamer left out.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsPEX
@testable import OpenSkyGameData
@testable import OpenSkyMagic
@testable import OpenSkyMagicInterface
import OpenSkyPhysics
@testable import OpenSkyScripting
@testable import OpenSkyScriptingInterface
@testable import OpenSkyWorld
import OpenSkyWorldInterface
@testable import OpenSkyWorldState
import Testing

@MainActor
final class TrapCellSession {
    /// One step through a trap volume: its script state before and after, and what it wrote.
    struct Crossing {
        let queued: Int
        let before: String?
        let inside: String?
        let activateChildren: Int
        let newDeltas: Int
        let lines: [String]
    }

    struct Hit {
        let targets: [ReferenceKey]
        let storedEffects: Int
        let lines: [String]
    }

    let builder: CellSceneBuilder
    let scene: CellScene
    let worldState = WorldStateStore()
    let bridge: PapyrusWorldStateBridge
    let world: PapyrusWorldRuntime
    let hazards: HazardStore
    let spells: SpellStore
    private let references: CrimeRealDataTests.SceneReferences

    private init(root: GameDataRoot, install: RealDataInstall) throws {
        builder = install.sceneBuilder()
        scene = try builder.buildInteriorScene(cellFormID: TrapCellRealDataTests.cell)
        references = CrimeRealDataTests.SceneReferences(scene: scene)
        bridge = PapyrusWorldStateBridge(worldState: worldState, references: references)
        world = PapyrusWorldRuntime(runtime: PapyrusRuntime(
            files: [],
            nativeDispatch: PapyrusNativeRegistry.standard(
                context: PapyrusNativeContext(world: bridge)
            )
        ))
        bridge.world = world
        bridge.formIDResolver = builder.formIDResolver
        let loader = PexScriptLoader(fileSystem: install.fileSystem)
        world.scriptProvider = { try? loader.load($0) }
        let plugins = ActivePluginFiles.load(root: root, baseFile: install.file)
        hazards = HazardStore(plugins: plugins)
        spells = SpellStore(plugins: plugins)
        bridge.formListStore = FormListStore(plugins: plugins)
    }

    static func make() throws -> TrapCellSession {
        let root = try #require(RealDataEnvironment.dataRoot)
        let session = try TrapCellSession(root: root, install: RealDataInstall.load())
        let location = try #require(session.scene.location)
        session.world.attach(
            cell: location,
            references: session.scene.references,
            formIDResolver: session.builder.formIDResolver,
            firstIntegration: true
        )
        session.drain()
        return session
    }

    var summaryLines: [String] {
        let summary = scene.summary
        return [
            "references\t\(scene.references.sortedEntries().count)",
            "locked interactions\t\(scene.interactions.values.count { $0.lock != nil })",
            "enabled hazards\t\(scene.hazards.count)",
            "disabled at load\t\(summary.disabledSkipCount)",
            "unresolved enable parents\t\(summary.unresolvedEnableParentCount)",
            "script instances\t\(world.instancesByKey.count)"
        ]
    }

    /// References carrying a script named `name`, in reference order.
    func scripted(_ name: String) -> [RuntimeReferenceEntry] {
        scene.references.sortedEntries().filter { entry in
            entry.placedReference?.scriptData.scripts
                .contains { $0.name.lowercased() == name } ?? false
        }
    }

    /// The player steps into the volume of `entry` and out again.
    func cross(_ entry: RuntimeReferenceEntry, script: String, label: String) -> Crossing {
        let journal = worldState.journalEntries.count
        let before = state(of: entry.key, script: script)
        let queued = bridge.handleTriggerTransition(
            TriggerTransitionEvent(reference: entry.key, phase: .enter)
        )
        drain()
        let inside = state(of: entry.key, script: script)
        bridge.handleTriggerTransition(TriggerTransitionEvent(reference: entry.key, phase: .leave))
        drain()
        let after = state(of: entry.key, script: script)
        let deltas = worldState.journalEntries.count - journal
        let children = references.activateChildren(of: entry.key).count
        let states = [before, inside, after].map { $0 ?? "none" }.joined(separator: " -> ")
        return Crossing(
            queued: queued,
            before: before,
            inside: inside,
            activateChildren: children,
            newDeltas: deltas,
            lines: [
                "\(label)\t\(entry.formID)",
                "\(label) events queued\t\(queued)",
                "\(label) states\t\(states)",
                "\(label) activate children\t\(children)",
                "world-state deltas after the \(label)\t\(deltas)"
            ]
        )
    }

    /// The player presses the use key on `entry`; returns the queued script events.
    func press(_ entry: RuntimeReferenceEntry) -> Int {
        let outcome = bridge.activate(entry.key, by: .player, togglesOpen: false)
        drain()
        return outcome.queuedEvents
    }

    /// The cell's first hazard, or any HAZD with a spell when every placed one waits
    /// for its trap, stepped once with the player standing on it.
    func hazardHit() throws -> Hit {
        let placed = scene.hazards.first.flatMap { hazard in
            hazard.hazardKey.flatMap { hazards.spec(for: $0) }.map { ($0, hazard.position) }
        }
        let fallback = hazards.hazards.records
            .sorted { ($0.record.editorID ?? "") < ($1.record.editorID ?? "") }
            .lazy
            .compactMap { self.hazards.spec(for: ReferenceKey(resolved: $0.id)) }
            .first { $0.spell != nil }
            .map { ($0, SIMD3<Float>.zero) }
        let (spec, position) = try #require(placed ?? fallback)
        let recorder = HazardRecorder(spells: spells, position: position)
        let coordinator = HazardCoordinator()
        coordinator.world = recorder
        coordinator.spawn(HazardPlacement(
            id: .plugin(name: "Skyrim.esm", objectID: 0xFF00_0001), spec: spec, position: position
        ))
        coordinator.step(0.1)
        let hit = recorder.hits.first
        return Hit(
            targets: hit?.targets.map(\.key) ?? [],
            storedEffects: hit?.payload.entries.count ?? 0,
            lines: [
                "hazard\t\(spec.name) (\(placed == nil ? "load order" : "placed"))",
                "hazard spell\t\(hit?.payload.name ?? "unresolved")",
                "hazard effects applied\t\(hit?.payload.entries.count ?? 0)"
            ]
        )
    }

    private func state(of key: ReferenceKey, script: String) -> String? {
        world.instancesByKey
            .first { $0.key.reference == key && $0.key.scriptName.lowercased() == script }
            .flatMap { world.runtime.instances[$0.value]?.activeState }
    }

    /// Steps until no event and no `Utility.Wait` is pending. Bounded, so a script
    /// that waits forever fails the test instead of hanging it.
    private func drain() {
        for _ in 0 ..< 10000 where !world.eventQueue.isEmpty || world.scheduler.pendingCount > 0 {
            _ = world.stepFixed()
        }
    }
}

/// Stands the player on the hazard and records each hit instead of applying it.
@MainActor
private final class HazardRecorder: HazardWorld {
    let spells: SpellStore
    let position: SIMD3<Float>
    private(set) var hits: [SpellHit] = []

    init(spells: SpellStore, position: SIMD3<Float>) {
        self.spells = spells
        self.position = position
    }

    func hazardCandidates() -> [MeleeTarget] {
        [MeleeTarget(key: .player, feet: position)]
    }

    func hazardPayload(spell: ReferenceKey, hazard: ReferenceKey) -> SpellPayload? {
        spells.spell(key: spell)?.payload(caster: hazard)
    }

    func applySpellHit(_ hit: SpellHit) -> SpellHitReport {
        hits.append(hit)
        return SpellHitReport(targetCount: hit.targets.count, entryCount: hit.payload.entries.count)
    }
}
