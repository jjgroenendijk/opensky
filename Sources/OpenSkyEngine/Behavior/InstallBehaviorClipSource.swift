// The install-backed `BehaviorClipSource` (issues #187, #330, #189). Loads
// clips out of the user's own install on demand, so only the clips the running
// graph actually reaches are read, and caps the cache so a graph that reaches
// thousands of them cannot pull the whole animation set into memory.
//
// It started life beside the env-gated behavior tests. Item 14.6 moved it into
// the engine unchanged, because the running player graph needs exactly what
// those tests needed: a name-keyed lookup over the archived animation folder
// that resolves lazily. The tests keep using this one rather than a copy, so
// what the app plays and what the real-data tests assert on cannot diverge.
//
// Read-only external input: nothing it touches enters the repository
// (AGENTS.md "Legal & IP boundary").

import Foundation

/// Loads clips out of the install on demand, so only the clips the graphs
/// actually reach are read. Capped, because a graph that reaches thousands of
/// clips would otherwise pull the whole animation set into memory.
///
/// `@unchecked Sendable` because the mutable cache is guarded by use rather than
/// by a lock: one instance belongs to one graph instance, and a graph instance
/// is stepped from one thread (the main thread, for the player).
nonisolated final class InstallBehaviorClipSource: BehaviorClipSource, @unchecked Sendable {
    /// Where clips live in the archives. The player graph names its animations
    /// relative to this folder.
    static let animationPrefix = "meshes\\actors\\character\\animations\\"

    private let fileSystem: VirtualFileSystem
    /// Lowercased file name -> archive path, for every clip under the character
    /// animation folders.
    private let pathsByName: [String: String]
    private let limit: Int
    private var cache: [String: (any BehaviorClip)?] = [:]
    private(set) var loadedCount = 0
    private(set) var missCount = 0

    init(fileSystem: VirtualFileSystem, paths: [String], limit: Int = 512) {
        self.fileSystem = fileSystem
        self.limit = limit
        var byName: [String: String] = [:]
        for path in paths {
            guard let name = path.split(separator: "\\").last else { continue }
            let key = String(name).lowercased()
            if byName[key] == nil {
                byName[key] = path
            }
        }
        pathsByName = byName
    }

    /// Indexes every archived character animation, which is the path list the
    /// running player graph needs when nothing narrower is supplied.
    convenience init(fileSystem: VirtualFileSystem, limit: Int = 512) {
        self.init(
            fileSystem: fileSystem,
            paths: Self.animationPaths(in: fileSystem),
            limit: limit
        )
    }

    /// Every archived character animation, by archive path.
    static func animationPaths(in fileSystem: VirtualFileSystem) -> [String] {
        fileSystem.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(animationPrefix) && $0.hasSuffix(".hkx") }
    }

    func clip(named name: String?, bindingIndex _: Int) -> (any BehaviorClip)? {
        guard let name else { return nil }
        let key = (name.split(separator: "\\").last.map(String.init) ?? name).lowercased()
        if let cached = cache[key] {
            return cached
        }
        guard cache.count < limit, let path = pathsByName[key] else {
            missCount += 1
            return nil
        }
        let clip = load(path)
        cache[key] = clip
        if clip != nil {
            loadedCount += 1
        } else {
            missCount += 1
        }
        return clip
    }

    private func load(_ path: String) -> (any BehaviorClip)? {
        guard
            let data = try? fileSystem.contents(forPath: path),
            let file = try? HKXFile(data: data),
            let binding = (try? HKAAnimationBinding.bindings(in: file))?.first,
            let animations = try? HKASplineCompressedAnimation.animations(in: file)
        else {
            return nil
        }
        let animation = animations.first {
            binding.animationTarget == HKXPointerTarget(
                sectionIndex: $0.objectSectionIndex, dataOffset: $0.objectDataOffset
            )
        } ?? animations.first
        guard
            let animation,
            (try? binding.boneIndices(transformTrackCount: animation.transformTrackCount))
            != nil
        else {
            return nil
        }
        return SplineBehaviorClip(animation: animation, binding: binding)
    }
}
