// FLOR, TACT, FURN, and TREE sweep over the five masters: every record decodes,
// every produce link reaches a decodable item, and the station census goes to `logs/`.
// Run with `make test-real T='WorldObjectRealDataTests'`.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
import Testing

struct WorldObjectRealDataTests {
    private static let worldTypes: [FourCC] = ["FLOR", "TACT", "FURN", "TREE", "ACTI"]
    /// The world objects plus every type xEdit allows as a FLOR or TREE PFIG target.
    private static let indexTypes: Set<FourCC> = Set(worldTypes).union([
        "KYWD", "ALCH", "AMMO", "APPA", "ARMO", "BOOK", "INGR", "KEYM", "LIGH", "LVLI",
        "MISC", "SCRL", "SLGM", "WEAP"
    ])

    private struct ProduceCheck {
        var checked = 0
        var targets: [String: Int] = [:]
        var failures: [String] = []
    }

    private struct Sweep {
        var records: [String: Int] = [:]
        var failures: [String] = []
        var skipped = FieldTally()
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func decodesEveryWorldObjectAndResolvesItsProduce() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = try VanillaMasters.load(root: root)
        var sweep = Sweep()
        for type in Self.worldTypes {
            for entry in VanillaMasters.liveRecords(of: type, in: plugins) {
                sweep.records[type.description, default: 0] += 1
                do {
                    let base = try ModelBase(record: entry.record, localized: entry.localized)
                    sweep.skipped.merge(base.skipped)
                } catch {
                    sweep.failures.append("\(type) \(FormID(entry.record.formID)): \(error)")
                }
            }
        }
        #expect(sweep.failures.isEmpty, "records that threw: \(sweep.failures.prefix(5))")
        #expect(sweep.records["FLOR"] == 108, "FLOR count drift")
        #expect(sweep.records["TACT"] == 30, "TACT count drift")

        let index = RecordIndex(plugins: plugins, recordTypes: Self.indexTypes)
        let bases = Self.winningBases(index)
        let produce = Self.produceFailures(bases: bases, index: index)
        #expect(produce.failures.isEmpty, "produce links: \(produce.failures.prefix(5))")
        #expect(produce.checked == 178)

        let stations = Self.stationCensus(bases: bases, index: index)
        #expect(stations.types == [
            "alchemy": 2, "createObject": 39, "enchanting": 4, "smithingArmor": 1,
            "smithingWeapon": 1
        ])
        #expect(bases.values.count { $0.base.voiceType != nil } == 30)
        Self.pin(bases: bases, index: index)
        let report = ([
            "[INFO] records \(sweep.records.sorted { $0.key < $1.key })",
            "[INFO] produce links checked \(produce.checked), "
                + "targets \(produce.targets.sorted { $0.key < $1.key })",
            "[INFO] TACT with a voice type: \(bases.values.count { $0.base.voiceType != nil })",
            "[INFO] FURN stations per bench type \(stations.types.sorted { $0.key < $1.key })",
            "[INFO] FURN station keywords:"
        ] + stations.keywords.sorted { $0.value > $1.value }.map { "  \($0.key): \($0.value)" }
            + ["[INFO] unread fields:"] + sweep.skipped.ranked.map { "  \($0.name): \($0.count)" })
            .joined(separator: "\n")
        print(report)
        try? report.write(
            to: RepositoryLogs.directory().appending(path: "world-object-sweep.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func pin(
        bases: [ResolvedFormID: (base: ModelBase, plugin: String)],
        index: RecordIndex
    ) {
        func base(_ editorID: String) -> (base: ModelBase, plugin: String)? {
            bases.values.first { $0.base.editorID == editorID }
        }
        let pod = base("FloraSwampFungalPod01")
        #expect(pod?.base.recordType == "FLOR")
        #expect(editorID(pod?.base.produce?.ingredient, pod?.plugin ?? "", index)
            == "SwampFungalPod01")
        let stump = base("TreePineForestStump02AMoraTapinella")
        #expect(editorID(stump?.base.produce?.ingredient, stump?.plugin ?? "", index)
            == "MoraTapinellaBits")
        #expect(base("TG05TalkingRock01")?.base.voiceType == FormID(0x0001_B080))
        #expect(base("CraftingBlacksmithSharpeningWheel")?.base.workbench
            == Workbench(benchType: .smithingWeapon, skillIndex: 10))
        #expect(base("CraftingEnchantingWorkbench")?.base.workbench?.skillName == "Enchanting")
        #expect(base("BYOHDraftingTable")?.base.workbench?.benchType == .createObject)
    }

    private static func winningBases(
        _ index: RecordIndex
    ) -> [ResolvedFormID: (base: ModelBase, plugin: String)] {
        var bases: [ResolvedFormID: (base: ModelBase, plugin: String)] = [:]
        for id in index.orderedRecordIDs(of: Set(worldTypes)) {
            guard
                let indexed = index.records[id],
                let base = try? ModelBase(record: indexed.record, localized: indexed.localized)
            else { continue }
            bases[id] = (base, indexed.sourcePlugin)
        }
        return bases
    }

    /// Every FLOR and TREE PFIG must name an item that one of our decoders reads.
    private static func produceFailures(
        bases: [ResolvedFormID: (base: ModelBase, plugin: String)],
        index: RecordIndex
    ) -> ProduceCheck {
        var check = ProduceCheck()
        for (id, entry) in bases {
            guard let ingredient = entry.base.produce?.ingredient else { continue }
            check.checked += 1
            guard
                let target = index.resolvedID(ingredient, fromPlugin: entry.plugin),
                case let .record(indexed) = index.lookup(target)
            else {
                check.failures.append("\(id) -> \(ingredient) missing")
                continue
            }
            let type = indexed.record.type
            check.targets[type.description, default: 0] += 1
            let decodes = type == "LVLI"
                ? (try? LeveledList(record: indexed.record)) != nil
                : (try? ModelBase(record: indexed.record, localized: indexed.localized)) != nil
            if !decodes {
                check.failures.append("\(id) -> \(type) \(target) does not decode")
            }
        }
        return check
    }

    private static func stationCensus(
        bases: [ResolvedFormID: (base: ModelBase, plugin: String)],
        index: RecordIndex
    ) -> (types: [String: Int], keywords: [String: Int]) {
        var types: [String: Int] = [:]
        var keywords: [String: Int] = [:]
        for entry in bases.values {
            guard let workbench = entry.base.workbench, workbench.benchType != .none else {
                continue
            }
            types["\(workbench.benchType)", default: 0] += 1
            for keyword in entry.base.keywords.keywords {
                let name = editorID(keyword, entry.plugin, index) ?? keyword.description
                keywords[name, default: 0] += 1
            }
        }
        return (types, keywords)
    }

    private static func editorID(_ id: FormID?, _ plugin: String, _ index: RecordIndex) -> String? {
        guard
            let resolved = index.resolvedID(id, fromPlugin: plugin),
            case let .record(indexed) = index.lookup(resolved)
        else { return nil }
        return ESMWalk.editorID(of: indexed.record)
    }
}
