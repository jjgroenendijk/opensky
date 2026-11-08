// Loads the player's behavior graph from the install. `0_master.hkx` is the entry all
// three vanilla character files name. Nothing caches globally: one call is one instance
// over one decode, so a first-person graph can run beside it.
// See docs/engine/behavior-runtime.md.

import Foundation
public import OpenSkyBehavior
public import OpenSkyFormatsAnimation
import OpenSkyFormatsCore
public import OpenSkyGameData
public import OpenSkyWorldInterface

/// The player's running graph and the rig it poses, loaded together because a
/// pose is meaningless without the skeleton whose parent chain composes it.
nonisolated public struct PlayerBehaviorGraph {
    public static let behaviorPath = "meshes\\actors\\character\\behaviors\\0_master.hkx"
    public static let skeletonPath = "meshes\\actors\\character\\character assets\\skeleton.hkx"
    public static let characterPath = "meshes\\actors\\character\\characters\\defaultmale.hkx"
    /// The project the character graphs come from; a female player runs its sibling.
    public static let characterProjectPath = "meshes\\actors\\character\\defaultmale.hkx"

    /// True for a project in the human character folder, such as `defaultfemale.hkx`.
    public static func isCharacterProject(_ project: String) -> Bool {
        project.lowercased().hasPrefix("meshes\\actors\\character\\")
    }

    /// The first-person set: its own `0_master.hkx`, 99-bone rig and NIF skeleton. Paths
    /// come from the install's archive listing (`openskycli vfs ls _1stperson`). The folder
    /// is `characterassets`, with no space, unlike the third-person `character assets`.
    public static let firstPersonBehaviorPath =
        "meshes\\actors\\character\\_1stperson\\behaviors\\0_master.hkx"
    public static let firstPersonSkeletonPath =
        "meshes\\actors\\character\\_1stperson\\characterassets\\skeletonfirst.hkx"
    /// Its own character file: 37 properties, where the third-person one has 39.
    public static let firstPersonCharacterPath =
        "meshes\\actors\\character\\_1stperson\\characters\\firstperson.hkx"
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
            skeleton: BehaviorSkeleton(files.rig, ragdoll: files.ragdoll),
            clips: clips
        )
        // `0_master.hkx` is a shell: the locomotion states live in the behavior
        // files it references by name, so without this the graph can only reach
        // its jump branch (docs/engine/behavior-clips.md, "Behavior references").
        instance.references = references
        instance.characterProperties = files.characterProperties
        instance.speedSamples = files.speedSamples
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
    let ragdoll: HKASkeleton?
    let clipPaths: [String]
    var characterProperties = BehaviorCharacterProperties.empty
    var speedSamples: SpeedSampleProject?

    public static func decode(
        fileSystem: any GameFileSource,
        behaviorPath: String = PlayerBehaviorGraph.behaviorPath,
        skeletonPath: String = PlayerBehaviorGraph.skeletonPath,
        characterPath: String = PlayerBehaviorGraph.characterPath
    ) throws(PlayerBehaviorGraphError) -> PlayerBehaviorGraphFiles {
        let behaviorFile = try read(behaviorPath, from: fileSystem)
        guard let objectGraph = attempt({ try HKXObjectGraph(file: behaviorFile) }) else {
            throw PlayerBehaviorGraphError.invalid(behaviorPath)
        }
        guard let behavior = HKBBehaviorGraph.graphs(in: objectGraph).first else {
            throw PlayerBehaviorGraphError.noGraph(behaviorPath)
        }
        let rigFile = try read(skeletonPath, from: fileSystem)
        guard
            let skeletons = attempt({ try HKASkeleton.skeletons(in: rigFile) }),
            let rig = skeletons.first
        else {
            throw PlayerBehaviorGraphError.noSkeleton(skeletonPath)
        }
        let characterGraph = attempt { try read(characterPath, from: fileSystem) }
            .flatMap { element in attempt { try HKXObjectGraph(file: element) } }
        return PlayerBehaviorGraphFiles(
            behaviorPath: behaviorPath,
            objectGraph: objectGraph,
            behavior: behavior,
            rig: rig,
            ragdoll: skeletons.dropFirst().first,
            clipPaths: InstallBehaviorClipSource.animationPaths(
                in: fileSystem,
                folder: InstallBehaviorClipSource.animationFolder(forBehaviorPath: behaviorPath)
            ),
            characterProperties: characterGraph.flatMap { graph in
                BehaviorProjectAsset.character(in: graph).map {
                    BehaviorCharacterProperties(character: $0, in: graph)
                }
            } ?? .empty,
            speedSamples: SpeedSampleProject.load(forProject: characterPath, from: fileSystem)
        )
    }

    /// A race's own project, such as the werewolf's `WerewolfBeastProject.hkx`: the graph and
    /// rig its character names, with every clip of its `animations` folder.
    public static func decode(
        fileSystem: any GameFileSource, projectPath: String
    ) throws(PlayerBehaviorGraphError) -> PlayerBehaviorGraphFiles {
        let asset: BehaviorProjectAsset
        do {
            asset = try BehaviorProjectAsset.load(
                fileSystem: fileSystem, projectPath: projectPath, folderClips: true
            )
        } catch let error as BehaviorProjectAssetError {
            throw projectError(error)
        } catch {
            throw PlayerBehaviorGraphError.invalid(projectPath)
        }
        return PlayerBehaviorGraphFiles(
            behaviorPath: asset.behaviorPath, objectGraph: asset.objectGraph,
            behavior: asset.behavior, rig: asset.skeleton, ragdoll: asset.ragdollSkeleton,
            clipPaths: asset.clipPaths,
            characterProperties: asset.characterProperties,
            speedSamples: SpeedSampleProject.load(forProject: projectPath, from: fileSystem)
        )
    }

    private static func projectError(
        _ error: BehaviorProjectAssetError
    ) -> PlayerBehaviorGraphError {
        switch error {
        case let .missing(path): .missing(path)
        case let .invalid(path), let .noCharacter(path): .invalid(path)
        case let .noGraph(path): .noGraph(path)
        case let .noSkeleton(path): .noSkeleton(path)
        }
    }

    private static func read(
        _ path: String,
        from fileSystem: any GameFileSource
    ) throws(PlayerBehaviorGraphError) -> HKXFile {
        guard let data = attempt({ try fileSystem.contents(forPath: path) }) else {
            throw PlayerBehaviorGraphError.missing(path)
        }
        guard let file = attempt({ try HKXFile(data: data) }) else {
            throw PlayerBehaviorGraphError.invalid(path)
        }
        return file
    }
}
