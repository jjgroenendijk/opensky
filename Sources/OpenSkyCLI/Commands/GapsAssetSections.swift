// The `gaps` sections over asset files: meshes, textures, animations, and sound. Each
// reads every archived file of its kind once, one at a time, so memory stays flat.

import Foundation
import OpenSkyAudio
import OpenSkyCombat
import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyFormatsMesh
import OpenSkyFormatsSWF
import OpenSkyGameData
import OpenSkyWorld

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
        let unread = forEachFile(suffixes: [".hkx"]) { census.record(data: $1) }
        let handledEvents = Set(
            (CombatGraphNames.observedEvents + ArcheryGraphNames.observedEvents
                + RagdollGraphNames.handOffEvents).map { $0.lowercased() }
        ).union(footstepTags())
        let boundVariables = Set(
            (CombatGraphNames.variables + ArcheryGraphNames.variables
                + LocomotionGraphNames.variables).map { $0.lowercased() }
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
                handled: { handledEvents.contains($0.lowercased()) }, usesUnit: "clips",
                notes: ["done means engine code reacts to it; the graph itself uses many others"]
            ),
            GapSection(
                title: "Behavior graph variables", unit: "variables",
                counts: census.graphVariables,
                handled: { boundVariables.contains($0.lowercased()) }, usesUnit: "graphs",
                notes: ["done means engine code reads or sets it; the graph sets many itself"]
            )
        ]
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

    /// Footstep tags (`FSTP` `ANAM`): annotation events the footstep sounds answer.
    private func footstepTags() -> Set<String> {
        let store = FootstepStore(loadOrder: plugins)
        return Set(store.footsteps.values.compactMap { $0.tag?.lowercased() })
    }
}
