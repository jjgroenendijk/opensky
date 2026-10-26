// The decoded behaviour set of one project: the project file an object mesh or a race
// names, its character file, behaviour graph, rig, and clip list. Decoded off the main
// actor; the main actor only instances it. See docs/engine/object-animation.md.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyGameData

nonisolated public enum BehaviorProjectAssetError: Error, Equatable {
    case missing(String)
    case invalid(String)
    case noCharacter(String)
    case noGraph(String)
    case noSkeleton(String)
}

nonisolated public struct BehaviorProjectAsset: Sendable {
    public let projectPath: String
    /// The behaviour file the character names. Behaviour references resolve beside it.
    public let behaviorPath: String
    public let objectGraph: HKXObjectGraph
    public let behavior: HKBBehaviorGraph
    public let skeleton: HKASkeleton
    /// The rig's archive path, such as `...\character assets\skeleton.hkx`.
    public let rigPath: String
    /// Archive paths of the clips the character file lists. With `folderClips`, then the
    /// other clips of the project's `animations` folder, which a referenced file can name.
    public let clipPaths: [String]

    /// The events the graph declares, in index order. Papyrus sends these by name.
    public var eventNames: [String] {
        (behavior.data?.stringData?.eventNames ?? []).compactMap(\.self)
    }

    /// Project, then its first character, then that character's behaviour and rig.
    /// Each later path is relative to the project's folder.
    public static func load(
        fileSystem: any GameFileSource,
        projectPath: String,
        folderClips: Bool = false
    ) throws -> BehaviorProjectAsset {
        let folder = Self.folder(of: projectPath)
        let project = try objects(projectPath, fileSystem) { graph in
            graph.objects(ofClass: HKBProjectData.className).lazy
                .compactMap { HKBProjectData.decode(at: target($0), in: graph) }.first
        }
        guard let characterName = project?.characterFilenames.compactMap(\.self).first
        else { throw BehaviorProjectAssetError.noCharacter(projectPath) }
        let characterPath = join(folder, characterName)
        let character = try objects(characterPath, fileSystem) { graph in
            graph.objects(ofClass: HKBCharacterData.className).lazy
                .compactMap { HKBCharacterData.decode(at: target($0), in: graph) }.first
        }
        guard
            let character, let behaviorName = character.behaviorFilename,
            let rigName = character.rigName
        else { throw BehaviorProjectAssetError.noCharacter(characterPath) }
        let behaviorPath = join(folder, behaviorName)
        let graph = try read(behaviorPath, fileSystem)
        guard let behavior = HKBBehaviorGraph.graphs(in: graph).first else {
            throw BehaviorProjectAssetError.noGraph(behaviorPath)
        }
        let rigPath = join(folder, rigName)
        guard let rig = try? HKASkeleton.skeletons(in: read(rigPath, fileSystem)).first else {
            throw BehaviorProjectAssetError.noSkeleton(rigPath)
        }
        let listed = character.animationNames.compactMap(\.self).map { join(folder, $0) }
        let listedSet = Set(listed)
        let extra = folderClips ? InstallBehaviorClipSource.animationPaths(
            in: fileSystem, folder: join(folder, "animations") + "\\"
        ).filter { !listedSet.contains($0) } : []
        return BehaviorProjectAsset(
            projectPath: projectPath,
            behaviorPath: behaviorPath,
            objectGraph: graph,
            behavior: behavior,
            skeleton: rig,
            rigPath: rigPath,
            clipPaths: listed + extra
        )
    }

    public static func folder(of path: String) -> String {
        guard let cut = path.lastIndex(of: "\\") else { return "" }
        return String(path[..<cut])
    }

    /// `folder\name`, with forward slashes turned and the case folded.
    public static func join(_ folder: String, _ name: String) -> String {
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
        guard let data else { throw BehaviorProjectAssetError.missing(path) }
        guard let graph = try? HKXObjectGraph.decode(data) else {
            throw BehaviorProjectAssetError.invalid(path)
        }
        return graph
    }

    static func tagfilePath(_ path: String) -> String? {
        path.hasSuffix(".hkx") ? String(path.dropLast(4)) + ".hkt" : nil
    }
}
