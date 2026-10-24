// Loads the player's behavior graph from the install. `0_master.hkx` is the entry all
// three vanilla character files name. Nothing caches globally: one call is one instance
// over one decode, so a first-person graph can run beside it.
// See docs/engine/behavior-runtime.md.

import Foundation
import OpenSkyBehavior
import OpenSkyFormatsAnimation
import OpenSkyGameData

nonisolated public enum PlayerBehaviorGraphError: LocalizedError, Equatable, Sendable {
    case missing(String)
    case invalid(String)
    case noGraph(String)
    case noSkeleton(String)

    public var errorDescription: String? {
        switch self {
        case let .missing(path): "behavior asset missing: \(path)"
        case let .invalid(path): "unreadable Havok packfile: \(path)"
        case let .noGraph(path): "no hkbBehaviorGraph in \(path)"
        case let .noSkeleton(path): "no hkaSkeleton in \(path)"
        }
    }
}

/// The player's running graph and the rig it poses, loaded together because a
/// pose is meaningless without the skeleton whose parent chain composes it.
nonisolated public struct PlayerBehaviorGraph {
    public static let behaviorPath = "meshes\\actors\\character\\behaviors\\0_master.hkx"
    public static let skeletonPath = "meshes\\actors\\character\\character assets\\skeleton.hkx"
    /// The first-person set: its own `0_master.hkx`, 99-bone rig and NIF skeleton. Paths
    /// come from the install's archive listing (`openskycli vfs ls _1stperson`). The folder
    /// is `characterassets`, with no space, unlike the third-person `character assets`.
    public static let firstPersonBehaviorPath =
        "meshes\\actors\\character\\_1stperson\\behaviors\\0_master.hkx"
    public static let firstPersonSkeletonPath =
        "meshes\\actors\\character\\_1stperson\\characterassets\\skeletonfirst.hkx"
    /// The NIF rig the first-person arm meshes skin against. RACE names only
    /// the third-person skeleton (ANAM), so this one is a constant here — the
    /// install ships exactly one and no record points at it.
    public static let firstPersonRigPath = "meshes\\actors\\character\\_1stperson\\skeleton.nif"

    public let instance: BehaviorGraphInstance
    /// The Havok rig, kept rather than only its `BehaviorSkeleton` projection:
    /// composing a pose to world matrices needs the parent chain, which
    /// `BehaviorSkeleton` deliberately does not carry.
    public let skeleton: HKASkeleton
    public let clips: InstallBehaviorClipSource
    /// Where the graph's `hkbBehaviorReferenceGenerator` names resolve. Held so
    /// a readout can report how many behavior files the folder offered.
    public let referenceSource: InstallBehaviorReferenceSource

    /// Loads a player graph and its rig; defaults name the third-person set. Throws on a
    /// missing or malformed `0_master.hkx`, because running without a graph would look
    /// like an animation bug, not a load failure. A `clipWorker` reads clips off the caller.
    public static func load(
        fileSystem: any GameFileSource,
        behaviorPath: String = Self.behaviorPath,
        skeletonPath: String = Self.skeletonPath,
        clipWorker: (any AssetLoadWorking<String, SplineBehaviorClip>)? = nil
    ) throws -> PlayerBehaviorGraph {
        let files = try PlayerBehaviorGraphFiles.decode(
            fileSystem: fileSystem, behaviorPath: behaviorPath, skeletonPath: skeletonPath
        )
        return build(files, fileSystem: fileSystem, clipWorker: clipWorker)
    }

    /// Builds the running instance from decoded files. The decode can run off
    /// the main actor; this step cannot, because the instance is not `Sendable`.
    public static func build(
        _ files: PlayerBehaviorGraphFiles,
        fileSystem: any GameFileSource,
        clipWorker: (any AssetLoadWorking<String, SplineBehaviorClip>)? = nil
    ) -> PlayerBehaviorGraph {
        let clips = clipWorker.map {
            InstallBehaviorClipSource(paths: files.clipPaths, worker: $0)
        } ?? InstallBehaviorClipSource(fileSystem: fileSystem, paths: files.clipPaths)
        let references = InstallBehaviorReferenceSource(
            fileSystem: fileSystem, rootPath: files.behaviorPath
        )
        let instance = BehaviorGraphInstance(
            graph: files.behavior,
            in: files.objectGraph,
            skeleton: BehaviorSkeleton(files.rig),
            clips: clips
        )
        // `0_master.hkx` is a shell: the locomotion states live in the behavior
        // files it references by name, so without this the graph can only reach
        // its jump branch (docs/engine/behavior-clips.md, "Behavior references").
        instance.references = references
        instance.activate()
        instance.prefetchReachableClips()
        return PlayerBehaviorGraph(
            instance: instance, skeleton: files.rig, clips: clips, referenceSource: references
        )
    }
}

/// One player graph's decoded behavior file, rig, and clip list.
nonisolated public struct PlayerBehaviorGraphFiles: Sendable {
    let behaviorPath: String
    let objectGraph: HKXObjectGraph
    let behavior: HKBBehaviorGraph
    let rig: HKASkeleton
    let clipPaths: [String]

    public static func decode(
        fileSystem: any GameFileSource,
        behaviorPath: String = PlayerBehaviorGraph.behaviorPath,
        skeletonPath: String = PlayerBehaviorGraph.skeletonPath
    ) throws(PlayerBehaviorGraphError) -> PlayerBehaviorGraphFiles {
        let behaviorFile = try read(behaviorPath, from: fileSystem)
        guard let objectGraph = try? HKXObjectGraph(file: behaviorFile) else {
            throw PlayerBehaviorGraphError.invalid(behaviorPath)
        }
        guard let behavior = HKBBehaviorGraph.graphs(in: objectGraph).first else {
            throw PlayerBehaviorGraphError.noGraph(behaviorPath)
        }
        let rigFile = try read(skeletonPath, from: fileSystem)
        guard
            let skeletons = try? HKASkeleton.skeletons(in: rigFile),
            let rig = skeletons.first
        else {
            throw PlayerBehaviorGraphError.noSkeleton(skeletonPath)
        }
        return PlayerBehaviorGraphFiles(
            behaviorPath: behaviorPath,
            objectGraph: objectGraph,
            behavior: behavior,
            rig: rig,
            clipPaths: InstallBehaviorClipSource.animationPaths(
                in: fileSystem,
                folder: InstallBehaviorClipSource.animationFolder(forBehaviorPath: behaviorPath)
            )
        )
    }

    private static func read(
        _ path: String,
        from fileSystem: any GameFileSource
    ) throws(PlayerBehaviorGraphError) -> HKXFile {
        guard let data = try? fileSystem.contents(forPath: path) else {
            throw PlayerBehaviorGraphError.missing(path)
        }
        guard let file = try? HKXFile(data: data) else {
            throw PlayerBehaviorGraphError.invalid(path)
        }
        return file
    }
}
