// The install-backed `BehaviorReferenceSource` (issue #189): resolves the
// behavior-file names `0_master.hkx` references to the archived files beside
// it, and builds one graph instance per name on demand.
//
// The names a reference carries are the ones the behavior project spells —
// `mt_behavior.hkx`, `1hm_behavior.hkx`, sometimes with a folder in front and
// mixed separators — so lookup is on the file name alone, case-insensitively,
// against the folder the root behavior was loaded from. That keeps the
// first-person set (`_1stperson\behaviors\`) and the third-person set apart
// without either one having to be named: whichever folder the root came from is
// the folder its references resolve in, which is what item 14.7 needs when it
// runs both at once.
//
// Read-only external input: nothing it touches enters the repository
// (AGENTS.md "Legal & IP boundary").

import Foundation

nonisolated final class InstallBehaviorReferenceSource: BehaviorReferenceSource {
    private let fileSystem: VirtualFileSystem
    /// Lowercased file name -> archive path, for every behavior file in the
    /// folder the root behavior came from.
    private let pathsByName: [String: String]

    /// Indexes the behavior folder `rootPath` lives in.
    init(fileSystem: VirtualFileSystem, rootPath: String) {
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
    var indexedCount: Int {
        pathsByName.count
    }

    func behavior(
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
