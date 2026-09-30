// The install-backed `BehaviorClipSource`. The app and the real-data tests
// share it, so what the app plays and what the tests check cannot differ.
// Read-only external input: nothing it touches enters the repository.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyGameData

/// Loads clips on demand, so only the clips a graph reaches are read. Capped,
/// because a graph that reaches thousands of clips would otherwise pull the
/// whole animation set into memory.
nonisolated public final class InstallBehaviorClipSource: BehaviorClipSource {
    /// Where clips live in the archives. The player graph names its animations
    /// relative to this folder.
    public static let animationPrefix = "meshes\\actors\\character\\animations\\"

    private let fileSystem: any GameFileSource
    /// Lowercased file name -> archive path, for every clip under the character
    /// animation folders.
    private let pathsByName: [String: String]
    private let limit: Int
    private var cache: [String: (any BehaviorClip)?] = [:]
    public private(set) var loadedCount = 0
    public private(set) var missCount = 0

    public init(fileSystem: any GameFileSource, paths: [String], limit: Int = 512) {
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
    public convenience init(fileSystem: any GameFileSource, limit: Int = 512) {
        self.init(
            fileSystem: fileSystem,
            paths: Self.animationPaths(in: fileSystem),
            limit: limit
        )
    }

    /// Every archived character animation, by archive path.
    public static func animationPaths(in fileSystem: any GameFileSource) -> [String] {
        fileSystem.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(animationPrefix) && $0.hasSuffix(".hkx") }
    }

    public func clip(named name: String?, bindingIndex _: Int) -> (any BehaviorClip)? {
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
