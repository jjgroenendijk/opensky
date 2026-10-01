// Env-gated: how many records each GameData store drops on the user's load order.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct RecordStoreSkipsRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func loadOrderStoresReportTheirSkippedRecords() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: RecordIndex.referenceRecordTypes.union(["CLAS"])
        )
        let magicEffects = MagicEffectStore(index: index)
        let spells = SpellStore(index: index, effects: magicEffects)
        let stores: [(String, SkippedRecords)] = [
            ("KeywordStore", KeywordStore(index: index).skippedRecords),
            ("FormListStore", FormListStore(index: index).skippedRecords),
            ("MagicEffectStore", magicEffects.skippedRecords),
            ("SpellStore", spells.skippedRecords),
            (
                "EnchantmentStore",
                EnchantmentStore(index: index, effects: magicEffects)
                    .skippedRecords
            ),
            ("ShoutStore", ShoutStore(index: index, spells: spells).skippedRecords),
            ("PerkStore", PerkStore(index: index, spells: spells).skippedRecords),
            ("EquipSlotStore", EquipSlotStore(index: index).skippedRecords),
            ("LocationStore", LocationStore(index: index).skippedRecords),
            ("EncounterZoneStore", EncounterZoneStore(index: index).skippedRecords),
            ("CollisionLayerStore", CollisionLayerStore(index: index).skippedRecords),
            ("DefaultObjectStore", DefaultObjectStore(index: index).skippedRecords),
            ("FactionStore", FactionStore(index: index).skippedRecords),
            ("RelationshipStore", RelationshipStore(index: index).skippedRecords),
            ("CharacterClassStore", CharacterClassStore(index: index).skippedRecords),
            (
                "ActorValueInformationStore",
                ActorValueInformationStore(index: index)
                    .skippedRecords
            ),
            ("GameSettingStore", GameSettingStore(plugins: plugins).skippedRecords)
        ]
        report(stores, scope: "load order")
        for (name, skipped) in stores {
            #expect(skipped.isEmpty, "\(name) skipped records: \(skipped.lines)")
        }
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func skyrimMasterStoresReportTheirSkippedRecords() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let skyrim = try #require(
            ActivePluginFiles.load(root: root).first {
                $0.name.caseInsensitiveCompare("Skyrim.esm") == .orderedSame
            }
        )
        let file = skyrim.file
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        let stores: [(String, SkippedRecords)] = [
            ("ItemDefinitionStore", ItemDefinitionStore(file: file).skippedRecords),
            ("EquipmentCatalog", EquipmentCatalog.build(from: file).skippedRecords),
            ("WeatherStore", WeatherStore(file: file).skippedRecords),
            ("ActorValueResolver", ActorValueResolver.build(
                from: file,
                localized: localized,
                pluginName: skyrim.name
            ).skippedRecords)
        ]
        report(stores, scope: skyrim.name)
        for (name, skipped) in stores {
            #expect(skipped.isEmpty, "\(name) skipped records: \(skipped.lines)")
        }
    }

    private func report(_ stores: [(String, SkippedRecords)], scope: String) {
        for (name, skipped) in stores {
            let detail = skipped.lines.isEmpty ? "" : " — " + skipped.lines.joined(separator: "; ")
            print("[INFO] \(scope) \(name) skipped \(skipped.total)\(detail)")
        }
    }
}
