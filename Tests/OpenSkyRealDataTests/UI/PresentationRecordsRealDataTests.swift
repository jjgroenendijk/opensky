// The M27 records over the active load order: every Skyrim.esm MESG built to
// text with its unresolved tokens counted, LSCR pass counts for a few
// destinations with the run-on census, and the CSTY numbers combat styles
// feed the machine. Reports go to `.logs/presentation-records.log`.
// Run with `make test-real T='PresentationRecordsRealDataTests'`.

import Foundation
@testable import OpenSkyCombat
@testable import OpenSkyCombatInterface
@testable import OpenSkyConditions
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyMenus
@testable import OpenSkyWorld
import Testing

struct PresentationRecordsRealDataTests {
    private static func stores(
        _ root: GameDataRoot
    ) -> (presentation: PresentationRecordStore, locations: LocationStore) {
        let plugins = ActivePluginFiles.load(root: root)
        let index = RecordIndex(
            plugins: plugins,
            recordTypes: PresentationRecordStore.recordTypes.union(RecordIndex.referenceRecordTypes)
        )
        return (PresentationRecordStore(index: index), LocationStore(index: index))
    }

    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func buildsMessagesPicksLoadingScreensAndReadsCombatStyles() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let (store, locations) = Self.stores(root)
        var lines = Self.messageCensus(store, root: root)
        lines += Self.loadScreenCensus(store, locations: locations)
        lines += Self.combatStyleCensus(store)
        let text = lines.joined(separator: "\n")
        print(text)
        try text.write(
            to: RepositoryLogs.directory().appending(path: "presentation-records.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func messageCensus(
        _ store: PresentationRecordStore,
        root: GameDataRoot
    ) -> [String] {
        let strings = LocalizedStrings(vfs: VirtualFileSystem(root: root), pluginName: "Skyrim.esm")
        let builder = MessageTextBuilder(strings: strings)
        let messages = store.messages.records.filter { $0.sourcePlugin == "Skyrim.esm" }
        var boxes = 0, empty = 0, numberTokens = 0, unresolved: [String] = []
        for message in messages {
            let built = builder.build(message.record)
            boxes += built.isMessageBox ? 1 : 0
            empty += built.text.isEmpty ? 1 : 0
            numberTokens += JournalMenuModel.text(
                message.record.description,
                kind: .dlstrings,
                strings: strings
            )?
                .contains("%") == true ? 1 : 0
            if MessageFormat.hasUnresolvedToken(built.text) {
                unresolved.append(message.record.editorID ?? message.id.description)
            }
        }
        #expect(messages.count > 500)
        #expect(empty < messages.count / 4)
        let sample = ["HelpJumpPC", "WICraftingTanningRackMessage"].compactMap { name in
            store.messages.record(editorID: name)
                .map { "  \(name): \(builder.build($0.record).text.prefix(80))" }
        }
        return [
            "[INFO] MESG in Skyrim.esm \(messages.count): boxes \(boxes), empty text \(empty), "
                + "with % tokens \(numberTokens), unresolved after build \(unresolved.count)",
            "  unresolved sample \(unresolved.prefix(8))"
        ] + sample
    }

    private static func loadScreenCensus(
        _ store: PresentationRecordStore,
        locations: LocationStore
    ) -> [String] {
        var context = ConditionContext()
        context.data = ConditionDataResolution(locations: locations)
        var lines = ["[INFO] LSCR \(store.loadScreens.records.count)"]
        let names = ConditionEvaluator(context: context)
        var runOns: [String: Int] = [:]
        var functions: [String: Int] = [:]
        for screen in store.loadScreens.records {
            for condition in screen.record.conditions {
                runOns["\(condition.runOn)", default: 0] += 1
                functions[names.functionName(of: condition), default: 0] += 1
            }
        }
        lines.append("  run-on \(runOns.sorted { $0.key < $1.key })")
        lines.append("  functions \(functions.sorted { $0.value > $1.value }.prefix(10))")
        for destination in [
            nil,
            "WhiterunLocation",
            "SolitudeLocation",
            "BleakFallsBarrowLocation"
        ] {
            let id = destination.flatMap { locations.location(editorID: $0)?.id }
            let check = LoadScreenSelector.conditionCheck(context: context, destination: id)
            let passing = LoadScreenSelector(store: store, check: check).passing()
            lines.append("  \(destination ?? "no location"): \(passing.count) pass")
            if destination == nil {
                #expect(!passing.isEmpty)
            }
        }
        return lines
    }

    private static func combatStyleCensus(_ store: PresentationRecordStore) -> [String] {
        let tunings = store.combatStyles.records.map { CombatStyleTuning(style: $0.record) }
        #expect(tunings.count > 50)
        func range(_ values: [Float]) -> String {
            guard let low = values.min(), let high = values.max() else { return "-" }
            let mean = values.reduce(0, +) / Float(values.count)
            return String(format: "%.2f...%.2f mean %.2f", low, high, mean)
        }
        let base = CombatBehaviorSettings.standard
        let derived = tunings.map { base.tuned(by: $0) }
        let defaults = tunings
            .filter { $0.name?.localizedCaseInsensitiveContains("default") == true }.map {
                "  \($0.name ?? "?"): offense \($0.offensiveMultiplier), "
                    + "defense \($0.defensiveMultiplier)"
            }
        return ["[INFO] CSTY \(tunings.count)"] + defaults + [
            "  offense \(range(tunings.map(\.offensiveMultiplier)))",
            "  defense \(range(tunings.map(\.defensiveMultiplier)))",
            "  melee \(range(tunings.map(\.meleeScoreMultiplier))), "
                + "magic \(range(tunings.map(\.magicScoreMultiplier)))",
            "  derived attack gap \(range(derived.map(\.attackIntervalSeconds))), "
                + "block \(range(derived.map(\.blockChance))), "
                + "cast \(range(derived.map(\.castChance)))"
        ]
    }
}
