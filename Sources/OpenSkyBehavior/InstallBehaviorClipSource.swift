// The install-backed `BehaviorClipSource`. The app and the real-data tests
// share it, so what the app plays and what the tests check cannot differ.
// Read-only external input: nothing it touches enters the repository.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyGameData

/// Loads clips on demand, so only the clips a graph reaches are read. Capped,
/// because a graph that reaches thousands of clips would otherwise pull the
/// whole animation set into memory. With a worker, reads run off the main actor.
nonisolated public final class InstallBehaviorClipSource: BehaviorClipSource {
    /// Where clips live in the archives. The player graph names its animations
    /// relative to this folder.
    public static let animationPrefix = "meshes\\actors\\character\\animations\\"

    private enum Loading {
        case immediate(any GameFileSource)
        case worker(any AssetLoadWorking<String, SplineBehaviorClip>)
    }

    private let loading: Loading
    /// Lowercased file name -> archive path, for every clip under the character
    /// animation folders.
    private let pathsByName: [String: String]
    private let limit: Int
    private var cache: [String: (any BehaviorClip)?] = [:]
    private var inFlight: Set<String> = []
    public private(set) var loadedCount = 0
    public private(set) var missCount = 0

    /// Reads each clip inside the request, on the caller's thread.
    public convenience init(fileSystem: any GameFileSource, paths: [String], limit: Int = 512) {
        self.init(loading: .immediate(fileSystem), paths: paths, limit: limit)
    }

    /// Reads clips on `worker`; a requested clip arrives at a later `drain()`.
    public convenience init(
        paths: [String],
        limit: Int = 512,
        worker: any AssetLoadWorking<String, SplineBehaviorClip>
    ) {
        self.init(loading: .worker(worker), paths: paths, limit: limit)
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

    private init(loading: Loading, paths: [String], limit: Int) {
        self.loading = loading
        self.limit = limit
        var byName: [String: String] = [:]
        for path in paths {
            let key = Self.key(path)
            if byName[key] == nil {
                byName[key] = path
            }
        }
        pathsByName = byName
    }

    /// Every archived character animation, by archive path.
    public static func animationPaths(in fileSystem: any GameFileSource) -> [String] {
        fileSystem.archiveEntries()
            .map(\.path)
            .filter { $0.hasPrefix(animationPrefix) && $0.hasSuffix(".hkx") }
    }

    /// The read a worker runs: one archive path to one decoded clip.
    public static func load(
        fileSystem: any GameFileSource
    ) -> @Sendable (String) throws -> SplineBehaviorClip {
        { path in
            guard let clip = try decode(fileSystem.contents(forPath: path)) else {
                throw AssetLoadFailure(reason: "no usable clip in \(path)")
            }
            return clip
        }
    }

    public func clip(named name: String?, bindingIndex _: Int) -> (any BehaviorClip)? {
        guard let name else { return nil }
        let key = Self.key(name)
        if let cached = cache[key] {
            return cached
        }
        guard !inFlight.contains(key) else { return nil }
        guard cache.count + inFlight.count < limit, let path = pathsByName[key] else {
            missCount += 1
            return nil
        }
        switch loading {
        case let .immediate(fileSystem):
            let clip = (try? fileSystem.contents(forPath: path)).flatMap(Self.decode)
            store(clip, for: key)
            return clip
        case let .worker(worker):
            inFlight.insert(key)
            worker.submit(path, priority: .needed)
            return nil
        }
    }

    public func isLoading(named name: String?, bindingIndex _: Int) -> Bool {
        name.map { inFlight.contains(Self.key($0)) } ?? false
    }

    public func prefetch(named name: String) {
        let key = Self.key(name)
        guard
            case let .worker(worker) = loading,
            cache[key] == nil, !inFlight.contains(key),
            cache.count + inFlight.count < limit,
            let path = pathsByName[key]
        else { return }
        inFlight.insert(key)
        worker.submit(path, priority: .prefetch)
    }

    /// Moves finished worker loads into the cache. Returns how many arrived.
    @discardableResult
    public func drain() -> Int {
        guard case let .worker(worker) = loading else { return 0 }
        let finished = worker.takeFinished()
        for completion in finished {
            let key = Self.key(completion.key)
            inFlight.remove(key)
            store(try? completion.result.get(), for: key)
        }
        return finished.count
    }

    private func store(_ clip: (any BehaviorClip)?, for key: String) {
        cache[key] = clip
        if clip != nil {
            loadedCount += 1
        } else {
            missCount += 1
        }
    }

    /// The lowercased file name, the spelling both a generator and a path reduce to.
    private static func key(_ name: String) -> String {
        (name.split(separator: "\\").last.map(String.init) ?? name).lowercased()
    }

    private static func decode(_ data: Data) -> SplineBehaviorClip? {
        guard
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
