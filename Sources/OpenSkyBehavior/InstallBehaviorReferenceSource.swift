// The install-backed `BehaviorReferenceSource`. A reference resolves by file name,
// case-insensitively, in the root behavior's own folder, so first- and third-person
// sets stay apart. Read-only external input (AGENTS.md "Legal & IP boundary").

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyGameData

nonisolated public final class InstallBehaviorReferenceSource: BehaviorReferenceSource {
    private let fileSystem: any GameFileSource
    /// Lowercased file name -> archive path, for every behavior file in the
    /// folder the root behavior came from.
    private let pathsByName: [String: String]
    /// Each file decoded once, so every actor of a race shares one decode.
    private var decoded: [String: DecodedBehavior?] = [:]

    private struct DecodedBehavior {
        let objectGraph: HKXObjectGraph
        let graph: HKBBehaviorGraph
        let objects: SharedBehaviorObjectSource
    }

    /// Indexes the behavior folder `rootPath` lives in.
    public convenience init(fileSystem: any GameFileSource, rootPath: String) {
        self.init(fileSystem: fileSystem, pathsByName: Self.index(fileSystem, rootPath: rootPath))
    }

    /// Takes an index `index(_:rootPath:)` built earlier, such as off the main actor.
    public init(fileSystem: any GameFileSource, pathsByName: [String: String]) {
        self.fileSystem = fileSystem
        self.pathsByName = pathsByName
    }

    /// Lowercased file name to archive path, for every behaviour file beside `rootPath`.
    public static func index(_ fileSystem: any GameFileSource, rootPath: String)
        -> [String: String]
    {
        let folder = folder(of: rootPath)
        var byName: [String: String] = [:]
        for entry in fileSystem.archiveEntries() {
            let path = entry.path
            let lowered = path.lowercased()
            guard
                lowered.hasPrefix(folder),
                lowered.hasSuffix(".hkx") || lowered.hasSuffix(".hkt"),
                let name = lowered.split(separator: "\\").last
            else { continue }
            // A graph names a tagfile behaviour with `.hkx`, as for a packfile.
            let key = String(name.dropLast(4)) + ".hkx"
            if byName[key] == nil || lowered.hasSuffix(".hkx") {
                byName[key] = path
            }
        }
        return byName
    }

    /// How many behavior files the folder offered, so a run can report that the
    /// index is empty rather than that every reference happened to miss.
    public var indexedCount: Int {
        pathsByName.count
    }

    public func behavior(
        named name: String,
        skeleton: BehaviorSkeleton,
        clips: any BehaviorClipSource
    ) -> BehaviorGraphInstance? {
        let key = BehaviorGraphInstance.referenceKey(name)
        guard
            let path = pathsByName[key] ?? pathsByName[key + ".hkx"],
            let file = decode(path)
        else { return nil }
        return BehaviorGraphInstance(
            graph: file.graph, in: file.objectGraph, skeleton: skeleton, clips: clips,
            objects: file.objects
        )
    }

    private func decode(_ path: String) -> DecodedBehavior? {
        if let cached = decoded[path] {
            return cached
        }
        let result: DecodedBehavior? = (try? fileSystem.contents(forPath: path))
            .flatMap { try? HKXObjectGraph.decode($0) }
            .flatMap { objectGraph in
                HKBBehaviorGraph.graphs(in: objectGraph).first.map {
                    DecodedBehavior(
                        objectGraph: objectGraph, graph: $0,
                        objects: SharedBehaviorObjectSource(graph: objectGraph)
                    )
                }
            }
        decoded[path] = .some(result)
        return result
    }

    /// The archive folder a path lives in, lowercased and trailing-separated.
    private static func folder(of path: String) -> String {
        let lowered = path.lowercased()
        guard let separator = lowered.lastIndex(of: "\\") else { return lowered }
        return String(lowered[...separator])
    }
}
