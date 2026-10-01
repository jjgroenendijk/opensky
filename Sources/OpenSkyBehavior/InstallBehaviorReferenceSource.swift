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

    /// Indexes the behavior folder `rootPath` lives in.
    public init(fileSystem: any GameFileSource, rootPath: String) {
        self.fileSystem = fileSystem
        let folder = Self.folder(of: rootPath)
        var byName: [String: String] = [:]
        for entry in fileSystem.archiveEntries() {
            let path = entry.path
            guard
                path.lowercased().hasPrefix(folder),
                path.hasSuffix(".hkx"),
                let name = path.split(separator: "\\").last
            else { continue }
            let key = String(name).lowercased()
            if byName[key] == nil {
                byName[key] = path
            }
        }
        pathsByName = byName
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
            let data = try? fileSystem.contents(forPath: path),
            let file = try? HKXFile(data: data),
            let objectGraph = try? HKXObjectGraph(file: file),
            let graph = HKBBehaviorGraph.graphs(in: objectGraph).first
        else { return nil }
        return BehaviorGraphInstance(
            graph: graph, in: objectGraph, skeleton: skeleton, clips: clips
        )
    }

    /// The archive folder a path lives in, lowercased and trailing-separated.
    private static func folder(of path: String) -> String {
        let lowered = path.lowercased()
        guard let separator = lowered.lastIndex(of: "\\") else { return lowered }
        return String(lowered[...separator])
    }
}
