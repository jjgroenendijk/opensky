// The decoded behaviour set of one animated object: the project a mesh names,
// its character file, behaviour graph, one-bone or few-bone rig, and clip list.
// Decoded on the build queue; the main actor only instances it.
// See docs/engine/object-animation.md.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyGameData

nonisolated public enum ObjectBehaviorAssetError: Error, Equatable {
    case missing(String)
    case invalid(String)
    case noCharacter(String)
    case noGraph(String)
    case noSkeleton(String)
}

nonisolated public struct ObjectBehaviorAsset: Sendable {
    public let projectPath: String
    public let behaviorPath: String
    public let objectGraph: HKXObjectGraph
    public let behavior: HKBBehaviorGraph
    public let skeleton: HKASkeleton
    /// Archive paths of the clips the character file lists.
    public let clipPaths: [String]

    /// The events the graph declares, in index order. Papyrus sends these by name.
    public var eventNames: [String] {
        (behavior.data?.stringData?.eventNames ?? []).compactMap(\.self)
    }

    /// Project, then its first character, then that character's behaviour and rig.
    /// Each later path is relative to the project's folder.
    public static func load(
        fileSystem: any GameFileSource,
        projectPath: String
    ) throws -> ObjectBehaviorAsset {
        let folder = Self.folder(of: projectPath)
        let project = try objects(projectPath, fileSystem) { graph in
            graph.objects(ofClass: HKBProjectData.className).lazy
                .compactMap { HKBProjectData.decode(at: target($0), in: graph) }.first
        }
        guard let characterName = project?.characterFilenames.compactMap(\.self).first
        else { throw ObjectBehaviorAssetError.noCharacter(projectPath) }
        let characterPath = join(folder, characterName)
        let character = try objects(characterPath, fileSystem) { graph in
            graph.objects(ofClass: HKBCharacterData.className).lazy
                .compactMap { HKBCharacterData.decode(at: target($0), in: graph) }.first
        }
        guard
            let character, let behaviorName = character.behaviorFilename,
            let rigName = character.rigName
        else { throw ObjectBehaviorAssetError.noCharacter(characterPath) }
        let behaviorPath = join(folder, behaviorName)
        let graph = try read(behaviorPath, fileSystem)
        guard let behavior = HKBBehaviorGraph.graphs(in: graph).first else {
            throw ObjectBehaviorAssetError.noGraph(behaviorPath)
        }
        let rigPath = join(folder, rigName)
        guard let rig = try? HKASkeleton.skeletons(in: read(rigPath, fileSystem)).first else {
            throw ObjectBehaviorAssetError.noSkeleton(rigPath)
        }
        return ObjectBehaviorAsset(
            projectPath: projectPath,
            behaviorPath: behaviorPath,
            objectGraph: graph,
            behavior: behavior,
            skeleton: rig,
            clipPaths: character.animationNames.compactMap(\.self).map { join(folder, $0) }
        )
    }

    static func folder(of path: String) -> String {
        guard let cut = path.lastIndex(of: "\\") else { return "" }
        return String(path[..<cut])
    }

    /// `folder\name`, with forward slashes turned and the case folded.
    static func join(_ folder: String, _ name: String) -> String {
        let relative = name.replacingOccurrences(of: "/", with: "\\").lowercased()
        return folder.isEmpty ? relative : folder + "\\" + relative
    }

    private static func target(_ object: HKXObjectRef) -> HKXPointerTarget {
        HKXPointerTarget(sectionIndex: object.sectionIndex, dataOffset: object.dataOffset)
    }

    private static func objects<Value>(
        _ path: String,
        _ fileSystem: any GameFileSource,
        decode: (HKXObjectGraph) -> Value?
    ) throws -> Value? {
        try decode(read(path, fileSystem))
    }

    /// A packfile or a tagfile. A set that ships as tagfiles still names its files
    /// `.hkx`, so a missing `.hkx` is retried as `.hkt`.
    private static func read(
        _ path: String,
        _ fileSystem: any GameFileSource
    ) throws -> HKXObjectGraph {
        let data = (try? fileSystem.contents(forPath: path))
            ?? tagfilePath(path).flatMap { try? fileSystem.contents(forPath: $0) }
        guard let data else { throw ObjectBehaviorAssetError.missing(path) }
        guard let graph = try? HKXObjectGraph.decode(data) else {
            throw ObjectBehaviorAssetError.invalid(path)
        }
        return graph
    }

    static func tagfilePath(_ path: String) -> String? {
        path.hasSuffix(".hkx") ? String(path.dropLast(4)) + ".hkt" : nil
    }
}
