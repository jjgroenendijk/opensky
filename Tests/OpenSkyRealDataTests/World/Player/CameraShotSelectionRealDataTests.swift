// Camera shot selection over the five masters: the CPTH tree with each path's
// zoom, shots and condition functions, then one selection for the player
// against an actor. The report goes to `.logs/camera-shot-selection.log`.
// Run with `make test-real T='CameraShotSelectionRealDataTests'`.

import Foundation
@testable import OpenSkyConditions
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyWorld
import Testing

struct CameraShotSelectionRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func selectsShotsForThePlayerAgainstAnActor() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = try VanillaMasters.load(root: root)
        let store = CameraPathStore(plugins: plugins)
        var lines = ["[INFO] CPTH \(store.paths.records.count), CAMS \(store.shots.records.count)"]
        let names = ConditionEvaluator(context: ConditionContext())
        for rootID in store.forest.roots {
            lines += Self.tree(rootID, depth: 0, store: store, names: names)
        }
        lines += Self.shotCensus(store)

        let target = ReferenceKey.plugin(name: "skyrim.esm", objectID: 0x0001_A67C)
        let check = CameraShotSelector.conditionCheck(
            context: ConditionContext(), attacker: .player, target: target
        )
        var random = ConditionRandom(seed: 27)
        let selection = CameraShotSelector(store: store, check: check).select(random: &random)
        let candidates = selection.candidates.map { $0.record.editorID ?? "?" }
        let pathName = selection.path?.record.editorID ?? "none"
        let chosenName = selection.chosen?.record.editorID ?? "none"
        lines.append("[INFO] selection for player -> \(target): path \(pathName)")
        lines.append("  \(candidates.count) candidates \(candidates), chosen \(chosenName)")
        let verdicts = Dictionary(grouping: selection.trace) { "\($0.verdict)" }
        lines += verdicts.keys.sorted().map { "  verdict \($0): \(verdicts[$0]?.count ?? 0)" }
        #expect(selection.trace.count == store.paths.records.count)
        let bow = try #require(Self.firstBow(plugins: plugins))
        for weapon in [nil, bow] {
            var context = ConditionContext()
            context.camera = CameraShotFacts.resolution(
                weapon: weapon,
                targetBase: nil,
                targetDistance: 900,
                yaw: 0
            ) { _ in 1000 }
            let check = CameraShotSelector.conditionCheck(
                context: context,
                attacker: .player,
                target: target
            )
            var seeded = ConditionRandom(seed: 27)
            let kill = CameraShotSelector(store: store, check: check).select(random: &seeded)
            let path = kill.path?.record.editorID ?? "none"
            lines.append(
                "[INFO] \(weapon?.fields.editorID ?? "unarmed") kill, every side free: "
                    + "path \(path), "
                    + "stages \(kill.sequence.map { $0.record.editorID ?? "?" })"
            )
            lines += kill.trace.compactMap { trace in
                guard case let .rejected(function) = trace.verdict else { return nil }
                return "    rejected \(trace.editorID ?? "?") at depth \(trace.depth) "
                    + "by \(function)"
            }
        }

        let text = lines.joined(separator: "\n")
        print(text)
        try text.write(
            to: RepositoryLogs.directory().appending(path: "camera-shot-selection.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func tree(
        _ id: ResolvedFormID,
        depth: Int,
        store: CameraPathStore,
        names: ConditionEvaluator
    ) -> [String] {
        guard let path = store.paths.record(id) else { return [] }
        let functions = path.record.conditions.map { names.functionName(of: $0) }
        let shots = store.shots(of: path).map { $0.record.editorID ?? "?" }
        let line = String(repeating: "  ", count: depth + 1)
            + "\(path.record.editorID ?? "?") zoom \(path.record.zoom.map(String.init) ?? "-") "
            + "shots \(shots.count) \(shots.prefix(4)) conditions \(functions)"
        return [line] + store.forest.children(of: id).flatMap {
            tree($0, depth: depth + 1, store: store, names: names)
        }
    }

    private static func shotCensus(_ store: CameraPathStore) -> [String] {
        (Array(store.shots.records.prefix(40)) + store.shots.records
            .filter { $0.record.editorID?.hasPrefix("Exit") == true }).map { shot in
            let data = shot.record.properties
            let multipliers = data?.timeMultipliers.map { "\($0.x)/\($0.y)/\($0.z)" } ?? "-"
            return "  CAMS \(shot.record.editorID ?? "?") action \(data?.action ?? 9) "
                + "location \(data?.location ?? 9) target \(data?.target ?? 9) "
                + "flags 0x\(String(data?.flags ?? 0, radix: 16)) time \(multipliers) "
                + "min \(data?.minTime ?? -1) max \(data?.maxTime ?? -1) "
                + "between \(data?.targetPercentBetweenActors ?? -1) "
                + "near \(data?.nearTargetDistance ?? -1) "
                + "imad \(shot.record.imageSpaceModifier != nil)"
        }
    }

    /// The bow with the lowest editor ID, as a stand-in for the player's weapon.
    static func firstBow(plugins: [(name: String, file: ESMFile)]) -> Weapon? {
        let index = RecordIndex(plugins: plugins, recordTypes: ["WEAP"])
        let weapons = TypedRecordStore(
            index: index, types: ["WEAP"],
            decode: { try Weapon(record: $0.record, localized: $0.localized) },
            editorID: \.fields.editorID
        )
        return weapons.records.map(\.record)
            .filter { $0.animationType == .bow && $0.fields.editorID != nil }
            .min { ($0.fields.editorID ?? "") < ($1.fields.editorID ?? "") }
    }
}
