// The shop harness the crime acceptance runs against (issue #504, roadmap item
// 21.5), split out of `CrimeRealDataTests.swift` when that type reached its
// body-length cap.
//
// The split is along a real seam: the suite asks the questions, and this builds
// the session those questions need — one real interior cell, the resolvers over
// the real load order, and the take path wired the way
// `GameViewControllerCrime` wires the session's.
//
// Read-only external input: nothing here is committed, cached into the repo or
// copied into build output (AGENTS.md "Legal & IP boundary").

import Foundation
import Metal
@testable import opensky
import Testing

extension CrimeRealDataTests {
    /// One shop, built and wired the way the session wires it.
    @MainActor
    struct Harness {
        let scene: CellScene
        let items: WorldItemRuntime
        let reporter: CrimeReporter
        /// Retained here on purpose: `CrimeReporter.world` and
        /// `WorldItemRuntime.references` are both weak, so a harness that let
        /// either seam go would answer `.unowned` for everything and resolve no
        /// reference at all.
        let world: SceneCrimeWorld
        let references: SceneReferences
        let ownership: OwnershipResolver
        let definitions: ItemDefinitionStore
        let crimeFaction: ReferenceKey
        let crimeFactionName: String
        let crimeValuesDescription: String

        /// One owned item the shop places loose, with what taking it should
        /// cost.
        struct Theft {
            let interaction: PlacedInteraction
            let value: Int64
            let expectedBounty: Int32
        }

        /// Every loose item in the cell that the reference index also knows
        /// about, which is what a take can actually resolve.
        ///
        /// Walked from the entries rather than from `scene.interactions`,
        /// because the interaction map is the wider of the two: it carries
        /// references the cell listed and the index did not retain, and
        /// `WorldItemRuntime.take` needs the entry.
        var takeables: [(entry: RuntimeReferenceEntry, interaction: PlacedInteraction)] {
            scene.references.sortedEntries().compactMap { entry in
                guard
                    let interaction = scene.interactions[entry.formID],
                    interaction.action == .take
                else { return nil }
                return (entry, interaction)
            }
        }

        var takeableCount: Int {
            takeables.count
        }

        var ownedTakeableCount: Int {
            takeables.count { reporter.verdict(on: $0.entry.key).isTheft }
        }

        /// The most valuable owned takeable in the cell, ties broken by
        /// reference so a rerun picks the same item.
        ///
        /// The dearest rather than the first, because a shop's loose clutter is
        /// mostly worth nothing and a zero-value item prices the theft at
        /// nothing — which would make the acceptance vacuous.
        func dearestOwnedTakeable() -> Theft? {
            takeables
                .filter { reporter.verdict(on: $0.entry.key).isTheft }
                .map { takeable in
                    Theft(
                        interaction: takeable.interaction,
                        value: Int64(
                            definitions.definition(takeable.interaction.base)?.value ?? 0
                        ),
                        expectedBounty: reporter.theftBounty(
                            of: takeable.interaction.base,
                            count: 1,
                            from: takeable.entry.key
                        )
                    )
                }
                .filter { $0.expectedBounty > 0 }
                .max {
                    $0.value == $1.value
                        ? $0.interaction.reference.rawValue < $1.interaction.reference.rawValue
                        : $0.value < $1.value
                }
        }
    }

    /// Everything the crime layer asks about a running session, answered from
    /// one built scene. The same three lookups `GameViewController` makes, with
    /// the streamer replaced by the scene the suite built.
    @MainActor
    final class SceneCrimeWorld: CrimeWorld {
        var scene: CellScene?
        var ownership: OwnershipResolver?
        var crimeFactions: CrimeFactionResolver?
        var definitions: ItemDefinitionStore?
        var pluginName = "Skyrim.esm"

        func crimeOwner(of key: ReferenceKey) -> ReferenceOwner? {
            guard let scene, let ownership else { return nil }
            return ownership.owner(
                reference: scene.references[key]?.placedReference
                    .flatMap(RecordOwnership.init(reference:)),
                cell: scene.owner
            )
        }

        func crimeFaction(in cell: CellSceneLocation?) -> ReferenceKey? {
            guard
                let scene,
                let link = scene.locationLink,
                let crimeFactions,
                let location = crimeFactions.locations.resolve(link, fromPlugin: pluginName),
                let faction = crimeFactions.crimeFaction(of: location)
            else { return nil }
            return ReferenceKey(resolved: faction.id)
        }

        func crimeCell(of key: ReferenceKey) -> CellSceneLocation? {
            scene?.location
        }

        func crimeItemValue(of item: FormID) -> Int64 {
            Int64(definitions?.definition(item)?.value ?? 0)
        }

        func crimeActor(_ key: ReferenceKey) -> CrimeActor {
            CrimeActor(key: key)
        }
    }

    /// A fixed reference index over the built scene, so the take path resolves
    /// an activated FormID without a `CellStreamer`.
    final class SceneReferences: PapyrusWorldReferenceSource {
        let scene: CellScene

        init(scene: CellScene) {
            self.scene = scene
        }

        func referenceEntry(formID: FormID) -> RuntimeReferenceEntry? {
            scene.references.entry(for: formID)
        }

        func referenceEntry(key: ReferenceKey) -> RuntimeReferenceEntry? {
            scene.references[key]
        }

        func cellLocation(of key: ReferenceKey) -> CellSceneLocation? {
            scene.references[key] == nil ? nil : scene.location
        }
    }

    @MainActor
    static func harness() throws -> Harness {
        let root = try #require(dataRoot)
        let device = try #require(device)
        let esmURL = root.dataURL.appending(path: "Skyrim.esm")
        let file = try ESMFile(url: esmURL)
        let fileSystem = VirtualFileSystem(root: root)
        let textures = TextureLibrary(fileSystem: fileSystem, device: device)
        let builder = CellSceneBuilder(
            file: file,
            meshes: MeshLibrary(fileSystem: fileSystem, device: device, textures: textures),
            textures: textures,
            fileSystem: fileSystem
        )
        let shop = try #require(
            locateShop(in: file),
            "no CELL named \(CrimeRealDataTests.shopEditorID) in this load order"
        )
        let scene = try builder.buildInteriorScene(cellFormID: shop)

        let factions = FactionStoreLoader.load(root: root, baseFile: file)
        let locations = LocationStoreLoader.load(root: root, baseFile: file)
        let plugin = esmURL.lastPathComponent
        let ownership = OwnershipResolver(factions: factions, pluginName: plugin)
        let crimeFactions = CrimeFactionResolver(locations: locations, factions: factions)
        let definitions = InventoryBaselineResolver.build(from: file)

        let world = SceneCrimeWorld()
        world.scene = scene
        world.ownership = ownership
        world.crimeFactions = crimeFactions
        world.definitions = definitions.items
        world.pluginName = plugin

        let store = WorldStateStore()
        let reporter = CrimeReporter(
            runtime: CrimeRuntime(store: store, factions: factions),
            world: world
        )
        let references = SceneReferences(scene: scene)
        let items = WorldItemRuntime(
            inventory: InventoryRuntime(store: store, baselines: definitions),
            references: references
        )
        items.crime = reporter

        let resolved = crimeFaction(of: scene, resolver: crimeFactions, plugin: plugin)
        return Harness(
            scene: scene,
            items: items,
            reporter: reporter,
            world: world,
            references: references,
            ownership: ownership,
            definitions: definitions.items,
            crimeFaction: resolved.map { ReferenceKey(resolved: $0.id) } ?? .player,
            crimeFactionName: resolved?.editorID ?? "none",
            crimeValuesDescription: describe(resolved?.faction.crimeValues)
        )
    }

    static func crimeFaction(
        of scene: CellScene,
        resolver: CrimeFactionResolver,
        plugin: String
    ) -> ResolvedFaction? {
        guard
            let link = scene.locationLink,
            let location = resolver.locations.resolve(link, fromPlugin: plugin)
        else { return nil }
        return resolver.crimeFaction(of: location)
    }

    /// The shop's CELL FormID, found by editor ID so no number is pinned.
    static func locateShop(in file: ESMFile) -> FormID? {
        var found: FormID?
        ESMWalk.forEachRecord(in: file) { record in
            guard record.type == "CELL" else { return true }
            guard
                let cell = try? Cell(record: record, localized: false),
                cell.editorID?
                    .caseInsensitiveCompare(CrimeRealDataTests.shopEditorID) == .orderedSame
            else { return true }
            found = cell.formID
            return false
        }
        return found
    }

    static func describe(_ values: Faction.CrimeValues?) -> String {
        guard let values else { return "none" }
        return "murder \(values.murder), assault \(values.assault), "
            + "trespass \(values.trespass), steal multiplier "
            + (values.stealMultiplier.map { "\($0)" } ?? "absent")
    }
}
