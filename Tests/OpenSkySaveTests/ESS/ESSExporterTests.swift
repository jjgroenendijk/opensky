// Session state built in code, written as an `.ess`, read, and imported again: each
// mapped part comes back equal, the same state writes the same bytes, and each part
// the save cannot hold is counted.

import Foundation
import OpenSkyActorsInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
@testable import OpenSkySave
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

struct ESSExporterTests {
    private typealias Fixture = ESSImportSaveFixture

    private static let header = ESSExportHeader(
        saveNumber: 7, gameDate: "Morndas, 17th of Last Seed, 4E 201",
        experienceForNextLevel: 175, savedAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
    private static let moved = skyrim(Fixture.movedReference)
    private static let quest = skyrim(Fixture.quest)
    private static let topic = skyrim(0x2000)

    private static func skyrim(_ objectID: UInt32) -> ReferenceKey {
        ReferenceKey(resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: objectID))
    }

    private static var records: FakeESSImportRecords {
        var records = Fixture.records
        let cell = ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x5000)
        records.add("Skyrim.esm", Fixture.movedReference, "REFR")
        records.add("Skyrim.esm", Fixture.aliasReference, "ACHR")
        records.placed["skyrim.esm:\(Fixture.movedReference)"] = (flags: 0x400, space: cell)
        records.exportScripts["mq101script"] = ESSExportScript(
            name: "MQ101Script", parent: "", variables: [
                .init(name: "::count_var", typeName: "Int", initial: .integer(0)),
                .init(name: "::name_var", typeName: "String", initial: .string("start")),
                .init(name: "::target_var", typeName: "Float", initial: .float(1.5))
            ]
        )
        return records
    }

    private static func entry(
        _ key: ReferenceKey, _ values: [WorldStateComponentValue]
    ) -> WorldStateSnapshotEntry {
        var byKind: [WorldStateComponentKind: WorldStateComponentValue] = [:]
        for value in values {
            byKind[value.kind] = value
        }
        return WorldStateSnapshotEntry(key: key, delta: ReferenceStateDelta(components: byKind))
    }

    private static let identity = PlayerIdentityState(
        race: FormID(0x13746), isFemale: true, name: "Lydia",
        face: PlayerFace(morphs: [0.25, -0.5], parts: [3, 1])
    )

    private static func playerEntry() -> WorldStateSnapshotEntry {
        let sword = FormID(Fixture.sword)
        return entry(.player, [
            WorldStateComponentValue(identity),
            WorldStateComponentValue(PlayerProgressState(level: 6, experience: 42)),
            WorldStateComponentValue(SpellbookState(known: [skyrim(0x12FCD)])),
            WorldStateComponentValue(ActorFactionState(
                memberships: [ActorFactionMembership(faction: skyrim(0x13794), rank: 2)]
            )),
            WorldStateComponentValue(ReferenceInventoryState(
                stacks: [InventoryStack(item: sword, count: 2)], equipped: [sword]
            ))
        ])
    }

    private static func contents() -> OpenSkySaveContents {
        let spawn = ReferenceSpawnState(
            base: FormID(Fixture.sword), location: .interior(FormID(0x5000)),
            placement: PlacedReference.Placement(position: SIMD3(1, 2, 3), rotation: .zero)
        )
        let entries = [
            playerEntry(),
            entry(moved, [
                .enableState(.disabled),
                .transform(ReferenceTransformOverride(position: SIMD3(10, 20, 30), scale: 2))
            ]),
            entry(quest, [
                WorldStateComponentValue(
                    QuestRuntimeState(isRunning: true, stagesReached: [10, 20])
                ),
                WorldStateComponentValue(QuestAliasState(
                    fills: [QuestAliasFill(aliasID: 3, reference: skyrim(Fixture.aliasReference))]
                ))
            ]),
            entry(topic, [WorldStateComponentValue(DialogueRuntimeState(saidCount: 1))]),
            entry(.generated(1), [WorldStateComponentValue(spawn)])
        ]
        var clock = GameClock()
        clock.setProjectedValue(12.5, for: .gameDaysPassed)
        return OpenSkySaveContents(
            snapshot: WorldStateSnapshot(
                entries: entries.sorted { $0.key < $1.key }, nextGeneratedSequence: 2,
                globals: [WorldStateGlobalSnapshotEntry(
                    key: skyrim(0x1C0F2), value: GlobalValue(type: .short, rawValue: 3)
                )]
            ),
            metadata: SaveCreationMetadata(creationTimestamp: 0, appVersion: "test"),
            clock: clock,
            scripts: [PapyrusInstanceState(
                key: PapyrusInstanceKey(reference: quest, scriptName: "MQ101Script"),
                activeState: "",
                variables: [PapyrusVariableState(
                    declaringScript: "MQ101Script", name: "::count_var", value: .integer(4)
                )],
                hasFiredOnInit: true
            )],
            playerPlace: SavePlayerPlace(
                cell: .interior(FormID(0x5000)), feet: SIMD3(100, 200, 50), yaw: 0.5
            )
        )
    }

    private static func roundTrip() throws -> (ESSExportResult, ESSImportResult) {
        let exported = try ESSExporter.run(contents(), records: records, header: header)
        let file = try ESSFile(data: exported.data)
        return (exported, ESSImporter.run(file, records: records, appVersion: "test"))
    }

    private static func component<C: WorldStateComponent>(
        _ type: C.Type, of key: ReferenceKey, in result: ESSImportResult
    ) -> C? {
        result.contents.snapshot.entries.first { $0.key == key }?.delta.component(type)
    }

    @Test func playerComesBackEqual() throws {
        let (_, imported) = try Self.roundTrip()
        let identity = Self.component(PlayerIdentityState.self, of: .player, in: imported)
        #expect(identity == Self.identity)
        let progress = Self.component(PlayerProgressState.self, of: .player, in: imported)
        #expect(progress == PlayerProgressState(level: 6, experience: 42))
        let spells = Self.component(SpellbookState.self, of: .player, in: imported)
        #expect(spells?.known == [Self.skyrim(0x12FCD)])
        let factions = Self.component(ActorFactionState.self, of: .player, in: imported)
        #expect(factions?.rank(in: Self.skyrim(0x13794)) == 2)
        let inventory = Self.component(ReferenceInventoryState.self, of: .player, in: imported)
        #expect(inventory?.count(of: FormID(Fixture.sword)) == 2)
        #expect(inventory?.isEquipped(FormID(Fixture.sword)) == true)
        let place = try #require(imported.placement)
        #expect(place.isInterior && place.position == SIMD3(100, 200, 50))
        #expect(place.heading == ESSExporter.heading(fromYaw: 0.5))
    }

    @Test func worldStateComesBackEqual() throws {
        let (_, imported) = try Self.roundTrip()
        let original = Self.contents().snapshot.entries
        for key in [Self.moved, Self.quest, Self.topic, ReferenceKey.generated(1)] {
            let before = try #require(original.first { $0.key == key })
            let after = imported.contents.snapshot.entries.first { $0.key == key }
            #expect(after?.delta.components == before.delta.components, "\(key)")
        }
        #expect(imported.contents.snapshot.globals == Self.contents().snapshot.globals)
        #expect(imported.contents.snapshot.nextGeneratedSequence == 2)
        let days = imported.contents.clock?.projectedValue(.gameDaysPassed)
        #expect(days == Self.contents().clock?.projectedValue(.gameDaysPassed))
    }

    @Test func scriptVariablesComeBackWithDefaults() throws {
        let (_, imported) = try Self.roundTrip()
        let script = try #require(imported.contents.scripts.first)
        let key = PapyrusInstanceKey(reference: Self.quest, scriptName: "MQ101Script")
        #expect(script.key == key)
        let values = Dictionary(uniqueKeysWithValues: script.variables.map { ($0.name, $0.value) })
        #expect(values["::count_var"] == .integer(4))
        #expect(values["::name_var"] == .string("start"))
        #expect(values["::target_var"] == .float(1.5))
    }

    @Test func sameStateWritesSameBytes() throws {
        let records = Self.records
        let first = try ESSExporter.run(Self.contents(), records: records, header: Self.header)
        let second = try ESSExporter.run(Self.contents(), records: records, header: Self.header)
        #expect(first.data == second.data)
        #expect(first.report == second.report)
    }

    @Test func handleVariablesAndUnloadedFormsAreCounted() throws {
        var records = Self.records
        records.exportScripts["mq101script"] = ESSExportScript(
            name: "MQ101Script", parent: "",
            variables: [.init(name: "::target_var", typeName: "Actor", initial: .none)]
        )
        let contents = Self.contents()
        let extra = Self.entry(
            ReferenceKey(resolved: ResolvedFormID(plugin: "Missing.esp", objectID: 0x800)),
            [.enableState(.disabled)]
        )
        let snapshot = WorldStateSnapshot(
            entries: contents.snapshot.entries + [extra], nextGeneratedSequence: 2
        )
        let changed = OpenSkySaveContents(
            snapshot: snapshot, metadata: contents.metadata, scripts: contents.scripts
        )
        let result = try ESSExporter.run(changed, records: records, header: Self.header)
        let scripts = result.report.category("scripts")
        #expect(scripts?.dropped["script with object or array variables"] == 1)
        let references = result.report.category("references")
        #expect(references?.dropped["reference from a plugin not loaded"] == 1)
        #expect(result.report.category("clock")?.dropped["no game clock in the save"] == 1)
        _ = try ESSFile(data: result.data)
    }
}
