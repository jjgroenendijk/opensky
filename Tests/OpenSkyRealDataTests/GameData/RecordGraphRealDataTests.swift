// The lookup stores of the M23 to M28 records over the five masters: tree
// shapes, dangling links, map markers, combat styles, chargen counts, and BPTD
// node names against the character skeleton. The report goes to `logs/`.
// Run with `make test-real T='RecordGraphRealDataTests'`.

import Foundation
@testable import OpenSkyFormatsCore
@testable import OpenSkyFormatsESM
@testable import OpenSkyFormatsMesh
@testable import OpenSkyGameData
import Testing

struct RecordGraphRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func buildsEveryRecordGraphOverTheMasters() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let plugins = try VanillaMasters.load(root: root)
        let types = HazardStore.linkedTypes.union(IdleStore.types).union(CameraPathStore.types)
            .union(StoryManagerStore.types).union(CharacterPartStore.types)
            .union(["SCEN", "RACE", "QUST"])
        let index = RecordIndex(plugins: plugins, recordTypes: types)
        var report: [String] = []
        report += Self.trees(index: index)
        report += Self.links(index: index)
        report += try Self.characters(index: index, root: root)
        report += Self.markers(plugins: plugins)
        report += Self.world(plugins: plugins, parts: CharacterPartStore(index: index))
        let text = report.joined(separator: "\n")
        print(text)
        try text.write(
            to: RepositoryLogs.directory().appending(path: "record-graph-sweep.log"),
            atomically: true,
            encoding: .utf8
        )
    }

    private static func trees(index: RecordIndex) -> [String] {
        let idles = IdleStore(index: index)
        let cameras = CameraPathStore(index: index)
        let story = StoryManagerStore(index: index)
        #expect(idles.idles.records.count == 4154)
        #expect(idles.markers.records.count == 89)
        #expect(idles.animatedObjects.records.count == 82)
        #expect(cameras.paths.records.count == 193)
        #expect(cameras.shots.records.count == 192)
        #expect(cameras.forest.orphans.isEmpty, "every CPTH ANAM link resolves")
        #expect(cameras.forest.unreachable.isEmpty, "the camera path tree has no cycle")
        #expect(story.nodes.records.count == 657)
        #expect(story.forest.unreachable.isEmpty)
        #expect(idles.forest.unreachable.isEmpty, "the idle tree has no cycle")
        #expect(idles.forest.orphans.isEmpty, "every IDLE parent is an IDLE or an AACT")
        var lines = [
            forestLine("IDLE", idles.idles.records.count, idles.forest),
            forestLine("CPTH", cameras.paths.records.count, cameras.forest),
            forestLine("SM", story.nodes.records.count, story.forest),
            "[INFO] IDLE top idles \(idles.rootIdles.count), under an action "
                + "\(idles.rootIdles.count { idles.forest.parent(of: $0) != nil })",
            "[INFO] IDLM \(idles.markers.records.count), "
                + "ANIO \(idles.animatedObjects.records.count)",
            "[INFO] CAMS \(cameras.shots.records.count), "
                + "dangling shots \(cameras.danglingShotCount)"
        ]
        let groups = Dictionary(grouping: idles.rootIdles) {
            idles.idles.record($0)?.record.properties?.animationGroupSection ?? 255
        }
        lines += groups.keys.sorted()
            .map { "  IDLE roots in group \($0): \(groups[$0]?.count ?? 0)" }
        let events = Set(story.nodes.records.compactMap(\.record.event))
        lines += events.sorted { $0.description < $1.description }.map {
            "  SM event \($0): \(story.roots(forEvent: $0).count) roots"
        }
        return lines
    }

    private static func forestLine(
        _ name: String,
        _ count: Int,
        _ forest: RecordForest<ResolvedFormID>
    ) -> String {
        "[INFO] \(name) \(count), roots \(forest.roots.count), depth \(forest.maximumDepth), "
            + "orphans \(forest.orphans.count), unreachable \(forest.unreachable.count), "
            + "broken sibling chains \(forest.brokenSiblingChains)"
    }

    private static func links(index: RecordIndex) -> [String] {
        let hazards = HazardStore(index: index)
        let scenes = SceneStore(index: index)
        #expect(hazards.hazards.records.count == 51)
        #expect(scenes.scenes.records.count == 2130)
        let quests = Set(scenes.scenes.records.compactMap {
            index.resolvedID($0.record.quest, fromPlugin: $0.sourcePlugin)
        })
        let topics = scenes.scenes.records.reduce(0) { $0 + scenes.dialogueTopics(of: $1).count }
        #expect(hazards.hazards.skippedRecords.isEmpty)
        #expect(scenes.scenes.skippedRecords.isEmpty)
        return Self.sceneAliases(scenes, index: index) + [
            "[INFO] HAZD \(hazards.hazards.records.count), "
                + "dangling links \(hazards.danglingLinkCount)",
            "[INFO] SCEN \(scenes.scenes.records.count) in \(quests.count) quests, "
                + "dialogue topics \(topics)"
        ]
    }

    /// Joins each scene actor to an alias of the scene's quest.
    private static func sceneAliases(_ scenes: SceneStore, index: RecordIndex) -> [String] {
        let quests = TypedRecordStore(
            index: index, types: ["QUST"],
            decode: { try Quest(record: $0.record, localized: $0.localized) },
            editorID: \.editorID
        )
        var joined = 0
        var missing: [String] = []
        for scene in scenes.scenes.records {
            guard let quest = quests.resolve(scene.record.quest, fromPlugin: scene.sourcePlugin)
            else { continue }
            for pair in scenes.actorAliases(of: scene, in: quest.record) {
                if pair.alias != nil {
                    joined += 1
                } else {
                    missing.append("\(scene.record.editorID ?? "?") alias \(pair.actor.aliasID)")
                }
            }
        }
        #expect(missing.isEmpty, "scene actors with no quest alias: \(missing.prefix(5))")
        return ["[INFO] SCEN actors joined to a quest alias \(joined), missing \(missing.count)"]
            + missing.map { "  missing \($0)" }
    }

    private static func characters(index: RecordIndex, root: GameDataRoot) throws -> [String] {
        let parts = CharacterPartStore(index: index)
        #expect(parts.headParts.records.count == 805)
        #expect(parts.bodyParts.records.count == 45)
        #expect(parts.headParts.skippedRecords.isEmpty)
        var cycles = 0
        var dangling = 0
        var widest = 0
        for part in parts.headParts.records {
            let expanded = parts.expandedParts(part.id)
            cycles += expanded.cycles
            dangling += expanded.danglingLinks
            widest = max(widest, expanded.parts.count)
        }
        let types = Dictionary(grouping: parts.headParts.records) {
            "\($0.record.partType.map { "\($0)" } ?? "none")"
        }
        var lines = ["[INFO] BPTD \(parts.bodyParts.records.count)"]
        lines.append("[INFO] HDPT \(parts.headParts.records.count), widest expansion \(widest), "
            + "cycles \(cycles), dangling extras \(dangling)")
        lines += types.keys.sorted().map { "  HDPT type \($0): \(types[$0]?.count ?? 0)" }
        lines += try bodyParts(parts, index: index, root: root)
        return lines
    }

    /// Each BPTD is checked against the skeleton of a race that names it in `GNAM`.
    private static func bodyParts(
        _ parts: CharacterPartStore,
        index: RecordIndex,
        root: GameDataRoot
    ) throws -> [String] {
        let races = TypedRecordStore(
            index: index, types: ["RACE"],
            decode: { try Race(record: $0.record, localized: $0.localized) },
            editorID: \.editorID
        )
        var skeletonPaths: [ResolvedFormID: String] = [:]
        for race in races.records {
            guard
                let data = index.resolvedID(
                    race.record.details.bodyPartData,
                    fromPlugin: race.sourcePlugin
                ),
                let path = race.record.details.skeletons.male?.path
            else { continue }
            skeletonPaths[data] = skeletonPaths[data] ?? path
        }
        let vfs = VirtualFileSystem(root: root)
        var skeletons: [String: Set<String>] = [:]
        var lines: [String] = []
        var misses = 0
        var torsoParts = 0
        for data in parts.bodyParts.records {
            guard let path = skeletonPaths[data.id] else {
                lines.append("  BPTD \(data.record.editorID ?? "?"): no race")
                continue
            }
            if skeletons[path] == nil {
                let nif = try NIFFile(data: vfs.contents(forPath: "meshes\\" + path))
                skeletons[path] = Set(nif.header.strings)
            }
            let result = CharacterPartStore.resolveNodes(
                of: data.record,
                skeletonNodes: skeletons[path] ?? []
            )
            misses += result.misses.count
            torsoParts += data.record.parts(ofType: 0).count
            lines.append("  BPTD \(data.record.editorID ?? "?"): hits \(result.hits.count), "
                + "misses \(result.misses.map(\.self))")
        }
        #expect(misses == 1, "only the ballista centurion names a node its skeleton lacks")
        lines.insert("[INFO] BPTD torso parts \(torsoParts)", at: 0)
        lines.insert("[INFO] BPTD node misses \(misses) over \(skeletons.count) skeletons", at: 0)
        return lines
    }

    private static func markers(plugins: [(name: String, file: ESMFile)]) -> [String] {
        let markers = MapMarkerIndex(plugins: plugins)
        #expect(markers.skippedRecords.isEmpty)
        var lines = ["[INFO] map markers \(markers.count)"]
        for (worldspace, count) in markers.countsByWorldspace.sorted(by: { $0.value > $1.value }) {
            let entries = markers.markers(in: worldspace)
            #expect(entries.count == count)
            let named = entries.count { $0.name != nil }
            let placed = entries.count { $0.position != .zero }
            let plugins = Set(entries.map(\.sourcePlugin)).sorted()
            lines.append("  worldspace \(worldspace): \(count), named \(named), "
                + "placed \(placed), from \(plugins)")
        }
        lines += markers.typeHistogram.sorted { $0.value > $1.value }
            .map { "  marker type \($0.key): \($0.value)" }
        return lines
    }

    private static func world(
        plugins: [(name: String, file: ESMFile)],
        parts: CharacterPartStore
    ) -> [String] {
        var lines = ["[INFO] EYES \(parts.eyes.records.count)"]
        var skyrim: ESMFile?
        for plugin in plugins where plugin.name == "Skyrim.esm" {
            skyrim = plugin.file
        }
        guard let skyrim else { return lines }
        let resolver = ActorTemplateResolver.build(from: skyrim, localized: skyrim.isLocalized)
        let styled = resolver.actors.keys
            .count { (try? resolver.resolveCombatStyle(base: FormID($0)).value) != nil }
        lines
            .append(
                "[INFO] Skyrim.esm NPC_ \(resolver.actors.count), with a combat style \(styled)"
            )
        let haired = resolver.actors.values
            .count { parts.hairColor(of: $0, fromPlugin: "Skyrim.esm") != nil }
        lines.append("[INFO] Skyrim.esm NPC_ with a hair color \(haired)")
        let dialogue = DialogueStore(file: skyrim, pluginName: "Skyrim.esm")
        lines.append("[INFO] Skyrim.esm DLBR \(dialogue.branchCount)")
        lines += races(in: skyrim)
        return lines
    }

    private static func races(in file: ESMFile) -> [String] {
        var skipped = SkippedRecords()
        return file.liveRecords(of: "RACE", skipped: &skipped).compactMap { record in
            guard let race = try? Race(record: record, localized: file.isLocalized)
            else { return nil }
            let head = race.details.headData
            let both = [head.male, head.female]
            return "  RACE \(race.editorID ?? "?"): presets \(both.map(\.presets.count)), "
                + "hair colors \(both.map(\.hairColors.count)), "
                + "tint masks \(both.map(\.tintMasks.count)), "
                + "morph groups \(both.map(\.morphs.count))"
        }
    }
}
