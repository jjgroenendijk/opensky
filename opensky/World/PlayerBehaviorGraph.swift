// Loading the player's own behavior graph out of the install (issue #189).
//
// `0_master.hkx` is the entry point all three vanilla character files
// (`defaultmale.hkx`, `defaultfemale.hkx`, `default.hkx`) name, so it is the
// graph the player runs. Item 14.5 (#188) drove it from an env-gated test; this
// is the same recipe, moved into the engine so the running app plays what that
// test asserts against.
//
// Nothing here caches globally. One call produces one instance over one decode,
// which is what item 14.7 needs when it puts a first-person graph beside this
// one (docs/engine/behavior-runtime.md).

import Foundation

nonisolated enum PlayerBehaviorGraphError: LocalizedError, Equatable {
    case missing(String)
    case invalid(String)
    case noGraph(String)
    case noSkeleton(String)

    var errorDescription: String? {
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
nonisolated struct PlayerBehaviorGraph {
    static let behaviorPath = "meshes\\actors\\character\\behaviors\\0_master.hkx"
    static let skeletonPath = "meshes\\actors\\character\\character assets\\skeleton.hkx"
    /// The first-person set (issue #190). A peer of the third-person one rather
    /// than a subset: its own `0_master.hkx` over its own 17 behavior files,
    /// its own 99-bone rig, and its own NIF skeleton for the arm meshes to skin
    /// against. All three paths are read off the install's own archive listing
    /// (`openskycli vfs ls _1stperson`), never spelled from memory, and the
    /// folder is `characterassets` with no space where the third-person one is
    /// `character assets` with one.
    static let firstPersonBehaviorPath =
        "meshes\\actors\\character\\_1stperson\\behaviors\\0_master.hkx"
    static let firstPersonSkeletonPath =
        "meshes\\actors\\character\\_1stperson\\characterassets\\skeletonfirst.hkx"
    /// The NIF rig the first-person arm meshes skin against. RACE names only
    /// the third-person skeleton (ANAM), so this one is a constant here — the
    /// install ships exactly one and no record points at it.
    static let firstPersonRigPath = "meshes\\actors\\character\\_1stperson\\skeleton.nif"

    let instance: BehaviorGraphInstance
    /// The Havok rig, kept rather than only its `BehaviorSkeleton` projection:
    /// composing a pose to world matrices needs the parent chain, which
    /// `BehaviorSkeleton` deliberately does not carry.
    let skeleton: HKASkeleton
    let clips: InstallBehaviorClipSource
    /// Where the graph's `hkbBehaviorReferenceGenerator` names resolve. Held so
    /// a readout can report how many behavior files the folder offered.
    let referenceSource: InstallBehaviorReferenceSource

    /// Loads a player graph and the rig it poses. Defaults name the
    /// third-person set; item 14.7 passes the `_1stperson` pair, and the two
    /// calls produce two instances that share nothing (see the file comment).
    ///
    /// Throws rather than degrading: a missing or malformed `0_master.hkx` is a
    /// fact about the install the caller has to report, and silently running
    /// with no graph would look like an animation bug rather than a load
    /// failure (AGENTS.md "Missing -> fail loud").
    static func load(
        fileSystem: VirtualFileSystem,
        behaviorPath: String = Self.behaviorPath,
        skeletonPath: String = Self.skeletonPath
    ) throws -> PlayerBehaviorGraph {
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
        let clips = InstallBehaviorClipSource(fileSystem: fileSystem)
        let references = InstallBehaviorReferenceSource(
            fileSystem: fileSystem, rootPath: behaviorPath
        )
        let instance = BehaviorGraphInstance(
            graph: behavior,
            in: objectGraph,
            skeleton: BehaviorSkeleton(rig),
            clips: clips
        )
        // `0_master.hkx` is a shell: the locomotion states live in the behavior
        // files it references by name, so without this the graph can only reach
        // its jump branch (docs/engine/behavior-runtime.md).
        instance.references = references
        instance.activate()
        return PlayerBehaviorGraph(
            instance: instance, skeleton: rig, clips: clips, referenceSource: references
        )
    }

    private static func read(
        _ path: String,
        from fileSystem: VirtualFileSystem
    ) throws -> HKXFile {
        guard let data = try? fileSystem.contents(forPath: path) else {
            throw PlayerBehaviorGraphError.missing(path)
        }
        guard let file = try? HKXFile(data: data) else {
            throw PlayerBehaviorGraphError.invalid(path)
        }
        return file
    }
}
