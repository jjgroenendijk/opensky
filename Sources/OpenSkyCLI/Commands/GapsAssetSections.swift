// The `gaps` sections over asset files: meshes, textures, animations, and sound. Each
// reads every archived file of its kind once, one at a time, so memory stays flat.

import Foundation
import OpenSkyActorPresentation
import OpenSkyAudio
import OpenSkyBehavior
import OpenSkyCombat
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyMagic
import OpenSkyPlayer
import OpenSkyProgression
import OpenSkyScripting

extension GapsGatherer {
    func meshes() -> [GapSection] {
        var census = NIFMeshGapCensus()
        let unread = forEachFile(suffixes: [".nif", ".btr", ".bto"]) { census.record(data: $1) }
        let note = "\(census.fileCount) meshes (.nif, .btr, .bto), \(unread) did not read"
        return [
            GapSection(
                title: "NIF block types", unit: "block types", counts: census.blockTypes,
                handled: NIFBlockTypes.handled.contains, usesUnit: "blocks", notes: [note]
            ),
            GapSection(
                title: "Lighting shader types", unit: "shader types", counts: census.lightingTypes,
                handled: NIFMeshGapCensus.readLightingTypes.contains, usesUnit: "shader blocks"
            ),
            GapSection(
                title: "Lighting shader flags", unit: "flags", counts: census.lightingFlags,
                handled: NIFMeshGapCensus.readLightingFlags.contains, usesUnit: "shader blocks",
                notes: ["done means a surface term or draw state depends on the flag"]
            ),
            GapSection(
                title: "Effect shader flags", unit: "flags", counts: census.effectFlags,
                handled: NIFMeshGapCensus.readEffectFlags.contains, usesUnit: "shader blocks"
            ),
            GapSection(
                title: "Mesh decode failures", unit: "failure kinds", failures: census.failures,
                usesUnit: "meshes", notes: [note]
            )
        ]
    }

    func textures() -> [GapSection] {
        var census = DDSGapCensus()
        var count = 0
        let unread = forEachFile(suffixes: [".dds"]) { _, data in
            count += 1
            census.record(data: data)
        }
        return [GapSection(
            title: "Texture variants", unit: "variants", counts: census.variants,
            handled: DDSGapCensus.isRead, usesUnit: "textures",
            notes: ["\(count) textures, \(unread) did not read"]
        )]
    }

    func animations() -> [GapSection] {
        var census = HKXGapCensus()
        let unread = forEachFile(suffixes: [".hkx"]) { census.record(data: $1, path: $0) }
        let handledEvents = Set(
            (CombatGraphNames.observedEvents + ArcheryGraphNames.observedEvents
                + ShoutGraphNames.observedEvents + SpellFireGraphNames.observedEvents
                + RagdollGraphNames.handOffEvents + AnimationEventAction.handledEvents
                + AnimationObjectEvent.handledEvents + animationObjectUnloadEvents()
                + DragonFlightGraphNames.observedEvents)
                .map { $0.lowercased() }
        )
        let footsteps = footstepTags()
        let scripts = scriptAnimationCensus()
        let handled = handledEvents.union(footsteps).union(census.hearing.heardEvents())
            .union(scripts.registeredEvents).union(effectGraphEvents(census.hearing))
        let boundVariables = Set(
            (CombatGraphNames.variables + CombatGraphNames.loopVariables
                + ArcheryGraphNames.variables
                + LocomotionGraphNames.variables + LocomotionGraphNames.perspectiveVariables
                + ActorStateGraphNames.inputs + ActorStateGraphNames.outputs
                + ActorGraphState.allCases.map(\.variableName) + perkGraphVariables()
                + DragonFlightGraphNames.variables)
                .map { $0.lowercased() }
        )
        let note = "\(census.fileCount) .hkx files, \(unread) did not read, "
            + "\(census.failures.total) did not decode"
        return [
            GapSection(
                title: "Havok classes", unit: "classes", counts: census.classes,
                handled: HKXGapCensus.decoded.contains, usesUnit: "objects",
                notes: [note] + GapCounts.ranked(census.failures.uses).prefix(5)
                    .map { "\($0.count) files: \($0.name)" }
            ),
            GapSection(
                title: "Animation events", unit: "events", counts: census.annotations,
                handled: {
                    handled.contains($0.lowercased())
                        || FootstepStore.isUnanswered(tag: $0, known: footsteps)
                },
                usesUnit: "clips",
                notes: [
                    "done means engine code reacts to it, a script registers for it, "
                        + "or a graph of the clip's own folder or of an effect art waits for it"
                ]
            ),
            GapSection(
                title: "Behavior graph variables", unit: "variables",
                counts: census.graphVariables,
                handled: { name in
                    boundVariables.contains(name.lowercased())
                        || scripts.writtenVariables.contains(name.lowercased())
                        || Self.role(of: name, census, scripts: scripts) != .engineInput
                },
                usesUnit: "graphs",
                notes: Self.variableNotes(census, scripts: scripts, boundVariables: boundVariables)
            )
        ]
    }

    /// How the done variables split: set by the engine, or one of the other roles.
    private static func variableNotes(
        _ census: HKXGapCensus, scripts: PapyrusAnimationCensus, boundVariables: Set<String>
    ) -> [String] {
        var counts: [String: Int] = [:]
        for name in census.graphVariables.uses.keys {
            let kind = role(of: name, census, scripts: scripts)
            if boundVariables.contains(name.lowercased()) {
                counts["set by the engine", default: 0] += 1
            } else if scripts.writtenVariables.contains(name.lowercased()) {
                counts["set by scripts", default: 0] += 1
            } else if kind != .engineInput {
                counts[kind.rawValue, default: 0] += 1
            }
        }
        let order = ["set by the engine", "set by scripts"] + BehaviorVariableRole.allCases
            .filter { $0 != .engineInput }.map(\.rawValue)
        return [
            "done means engine code or a script sets it, or the engine need not: the graph "
                + "computes it, authors it, or nothing reads it",
            order.map { "\(counts[$0] ?? 0) \($0)" }.joined(separator: ", ")
        ]
    }

    private static func role(
        of name: String, _ census: HKXGapCensus, scripts: PapyrusAnimationCensus
    ) -> BehaviorVariableRole {
        BehaviorVariableRoles.role(
            of: name,
            uses: census.variableUses[name] ?? [],
            isAuthored: census.authoredVariables.contains(name),
            isScriptRead: scripts.readVariables.contains(name.lowercased())
        )
    }

    func audio() -> [GapSection] {
        var census = AudioGapCensus()
        var lips = GapCounts()
        let unread = forEachFile(suffixes: [".wav", ".xwm", ".fuz", ".lip"]) { path, data in
            if path.lowercased().hasSuffix(".lip") {
                lips.add(Self.lipVariant(data))
            } else if let lip = census.record(path: path, data: data) {
                lips.add(Self.lipVariant(lip))
            }
        }
        return [
            GapSection(
                title: "Sound file variants", unit: "variants", counts: census.variants,
                handled: AudioGapCensus.isRead, usesUnit: "files",
                notes: ["\(census.variants.total) sound files, \(unread) did not read"]
            ),
            GapSection(
                title: "Lip sync data", unit: "variants", counts: lips,
                handled: { $0 == Self.lipRead }, usesUnit: "lip files"
            )
        ]
    }

    func swfTags() -> GapSection {
        var census = SWFTagCensus()
        let unread = forEachFile(suffixes: [".swf"]) { census.record(data: $1) }
        let failed = GapCounts.ranked(census.failures.uses).map { "\($0.count) movies: \($0.name)" }
        return GapSection(
            title: "SWF tags", unit: "tag types", counts: census.tags,
            handled: SWFTagCensus.isHandled, usesUnit: "tags",
            notes: ["\(census.movieCount) movies, \(unread) did not read"] + failed
        )
    }

    /// Calls `body` with each archived file whose path ends in one of `suffixes`.
    /// Returns how many could not be read.
    func forEachFile(suffixes: [String], _ body: (String, Data) -> Void) -> Int {
        var unread = 0
        for entry in fileSystem.archiveEntries() {
            let path = entry.path.lowercased()
            guard suffixes.contains(where: path.hasSuffix) else { continue }
            guard let data = try? fileSystem.contents(forPath: entry.path) else {
                unread += 1
                continue
            }
            body(entry.path, data)
        }
        return unread
    }

    private static let lipRead = "lip reads"

    private static func lipVariant(_ data: Data) -> String {
        do {
            _ = try LIPFile(data: data)
            return lipRead
        } catch {
            return "fails: " + GapCounts.failureKind("\(error)")
        }
    }

    /// The graph variables perk effects set, which the combat runtime writes.
    private func perkGraphVariables() -> [String] {
        var skipped = SkippedRecords()
        let perks = (try? requirePlugins().decodeRecords(of: "PERK", skipped: &skipped) {
            try Perk(record: $0, localized: $1)
        }) ?? []
        return Array(PerkGapCensus(perks: perks).graphVariables)
    }

    /// The animation events a script registers for; `OnAnimationEvent` handles them.
    private func scriptAnimationCensus() -> PapyrusAnimationCensus {
        let loader = PexScriptLoader(fileSystem: fileSystem)
        let files = loader.scriptPaths().compactMap { try? loader.load($0) }
        return PapyrusAnimationCensus(files: files)
    }

    /// The events that take an animation object off its actor (`ANIO` `BNAM`).
    private func animationObjectUnloadEvents() -> [String] {
        var skipped = SkippedRecords()
        let objects = (try? requirePlugins().decodeRecords(of: "ANIO", skipped: &skipped) {
            try AnimatedObject(record: $0)
        }) ?? []
        return objects.compactMap(\.unloadEvent)
    }

    /// The events the graphs of `ARTO` and `ARMA` models wait for. An actor's events
    /// reach the graphs of the effects and armour addons on it (docs/engine/effect-graphs.md).
    private func effectGraphEvents(_ hearing: HKXAnnotationHearing) -> Set<String> {
        var skipped = SkippedRecords()
        let arts = (try? requirePlugins().decodeRecords(of: "ARTO", skipped: &skipped) {
            try ArtObject(record: $0)
        }) ?? []
        let addons = (try? requirePlugins().decodeRecords(of: "ARMA", skipped: &skipped) {
            try ArmorAddon(record: $0)
        }) ?? []
        let models = arts.compactMap(\.modelPath)
            + addons.flatMap { [$0.maleModelPath, $0.femaleModelPath].compactMap(\.self) }
        var projects = Set<String>()
        for model in Set(models.map { $0.lowercased() }) {
            let path = model.hasPrefix("meshes\\") ? model : "meshes\\" + model
            guard
                let data = try? fileSystem.contents(forPath: path),
                let file = try? NIFFile(data: data),
                let project = NIFBehaviorGraphExtraData.projectPath(in: file)
            else { continue }
            projects.insert(HKXAnnotationHearing.project(of: project))
        }
        return hearing.listenedEvents(inProjects: projects)
    }

    /// Footstep tags (`FSTP` `ANAM`): annotation events the footstep sounds answer.
    private func footstepTags() -> Set<String> {
        let store = FootstepStore(loadOrder: plugins)
        return Set(store.footsteps.values.compactMap { $0.tag?.lowercased() })
    }
}
