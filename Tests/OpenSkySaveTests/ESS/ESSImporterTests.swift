// A whole synthetic save through the import: each mapped kind lands in the snapshot,
// each unmapped kind is counted, and the result survives an `.osav` round trip.

import Foundation
import OpenSkyActorsInterface
import OpenSkyDialogueInterface
import OpenSkyFactionsInterface
import OpenSkyFormatsESM
import OpenSkyFormatsESS
import OpenSkyFormatsTesting
import OpenSkyGameData
import OpenSkyInventoryInterface
import OpenSkyMagicInterface
import OpenSkyProgressionInterface
import OpenSkyQuestsInterface
@testable import OpenSkySave
import OpenSkySaveFixtures
import OpenSkyScriptingInterface
import OpenSkyWorldState
import Testing

struct ESSImporterTests {
    private typealias Fixture = ESSImportSaveFixture

    private static func run() throws -> ESSImportResult {
        try ESSImporter.run(
            ESSFile(data: Fixture.save()), records: Fixture.records, appVersion: "test"
        )
    }

    private static func skyrim(_ objectID: UInt32) -> ReferenceKey {
        ReferenceKey(resolved: ResolvedFormID(plugin: "Skyrim.esm", objectID: objectID))
    }

    private static func component<C: WorldStateComponent>(
        _ type: C.Type, of key: ReferenceKey, in result: ESSImportResult
    ) -> C? {
        result.contents.snapshot.entries.first { $0.key == key }?.delta.component(type)
    }

    @Test func playerStateAndPlacement() throws {
        let result = try Self.run()
        let identity = try #require(Self.component(
            PlayerIdentityState.self,
            of: .player,
            in: result
        ))
        #expect(identity.race == FormID(0x13746))
        #expect(identity.name == "Prisoner")
        #expect(identity.isFemale)
        let progress = Self.component(PlayerProgressState.self, of: .player, in: result)
        #expect(progress?.level == 3)
        #expect(Self.component(SpellbookState.self, of: .player, in: result)?.known
            == [Self.skyrim(0x12FCD)])
        #expect(Self.component(ActorFactionState.self, of: .player, in: result)?.memberships
            == [ActorFactionMembership(faction: Self.skyrim(0x13794), rank: 0)])
        let inventory = try #require(
            Self.component(ReferenceInventoryState.self, of: .player, in: result)
        )
        #expect(Set(inventory.stacks.map(\.item)) == [FormID(0xF), FormID(Fixture.sword)])
        #expect(inventory.stacks.first { $0.item == FormID(0xF) }?.count == 250)
        #expect(inventory.equipped == [FormID(Fixture.sword)])
        let placement = try #require(result.placement)
        #expect(placement.space == ResolvedFormID(plugin: "Skyrim.esm", objectID: 0x3C))
        #expect(placement.spaceEditorID == "Tamriel")
        #expect(!placement.isInterior)
        #expect(placement.position == SIMD3(-12000, 30000, 512))
        #expect(placement.heading == 1.5)
        #expect(placement.cell == SIMD2(-3, 7))
    }

    @Test func referencesQuestsAndDialogue() throws {
        let result = try Self.run()
        let moved = Self.skyrim(Fixture.movedReference)
        #expect(Self.component(ReferenceEnableState.self, of: moved, in: result)?
            .isEnabled == false)
        let transform = Self.component(ReferenceTransformOverride.self, of: moved, in: result)
        #expect(transform?.position == SIMD3(10, 20, 30))
        #expect(transform?.scale == 2)
        let spawn = try #require(
            Self.component(ReferenceSpawnState.self, of: .generated(1), in: result)
        )
        #expect(spawn.base == FormID(Fixture.sword))
        #expect(spawn.location == .interior(FormID(0x5000)))
        #expect(result.contents.snapshot.nextGeneratedSequence == 2)
        let quest = Self.skyrim(Fixture.quest)
        let runtime = Self.component(QuestRuntimeState.self, of: quest, in: result)
        #expect(runtime?.isRunning == true)
        #expect(runtime?.stagesReached == [10, 20])
        #expect(Self.component(QuestAliasState.self, of: quest, in: result)?.fills
            == [QuestAliasFill(aliasID: 3, reference: Self.skyrim(Fixture.aliasReference))])
        #expect(Self.component(DialogueRuntimeState.self, of: Self.skyrim(0x2000), in: result)?
            .saidCount == 1)
    }

    @Test func globalsClockAndScripts() throws {
        let result = try Self.run()
        let globals = result.contents.snapshot.globals
        #expect(globals.map(\.key) == [Self.skyrim(0x1C0F2)])
        #expect(globals.first?.value == GlobalValue(type: .short, rawValue: 2))
        #expect(result.contents.clock?.projectedValue(.gameDaysPassed) == 3.25)
        let script = try #require(result.contents.scripts.first)
        #expect(result.contents.scripts.count == 1)
        let quest = Self.skyrim(Fixture.quest)
        #expect(script.key == PapyrusInstanceKey(reference: quest, scriptName: "MQ101Script"))
        #expect(script.variables.map(\.name) == ["::count_var", "::name_var"])
        #expect(script.variables.map(\.value) == [.integer(4), .string("Hadvar")])
        #expect(script.hasFiredOnInit)
    }

    @Test func everyUnmappedPartIsCounted() throws {
        let report = try Self.run().report
        let notLoaded = ESSUnmappedReason.pluginNotLoaded("Missing.esp").description
        #expect(report.category("globals")?.dropped == [notLoaded: 1])
        #expect(report.category("globals")?.imported == 1)
        #expect(report.category("clock")?.imported == 1)
        #expect(report.category("references")?.dropped == [notLoaded: 1])
        #expect(report.category("player")?.imported == 5)
        #expect(report.category("inventories")?.imported == 2)
        #expect(report.category("created forms")?.imported == 1)
        #expect(
            report.category("created forms")?.dropped == ["created potion": 1],
            "\(report.lines)"
        )
        #expect(report.category("scripts")?.dropped == [
            "instance on an unmapped form": 1, "object value (handles do not cross VMs)": 1
        ])
        #expect(report.droppedStacks == ["MQ101Script": 1])
        #expect(report.loadOrder.missing == ["Missing.esp"])
        #expect(report.lines.contains("plugins not loaded: Missing.esp"))
    }

    @Test func importedContentsSurviveAnOsavRoundTrip() throws {
        let contents = try Self.run().contents
        let data = OpenSkySaveEncoder.encode(
            snapshot: contents.snapshot, fingerprint: OpenSkySaveFixture.fingerprint,
            metadata: contents.metadata, clock: contents.clock, scripts: contents.scripts,
            summary: contents.summary, thumbnail: contents.thumbnail
        )
        let decoded = try OpenSkySaveDecoder.decode(data)
        #expect(decoded.snapshot.globals == contents.snapshot.globals)
        for entry in contents.snapshot.entries {
            let restored = decoded.snapshot.entries.first { $0.key == entry.key }?.delta
            for kind in entry.delta.sortedKinds {
                #expect(restored?[kind] == entry.delta[kind], "\(entry.key) \(kind.rawValue)")
            }
        }
        #expect(decoded.clock == contents.clock)
        #expect(decoded.scripts == contents.scripts)
        #expect(try OpenSkySaveSummaryCodec.readSummary(data).summary?.characterName == "Prisoner")
    }

    @Test func importIsDeterministic() throws {
        let first = try Self.run()
        let second = try Self.run()
        #expect(first.contents.snapshot == second.contents.snapshot)
        #expect(first.report == second.report)
    }
}
