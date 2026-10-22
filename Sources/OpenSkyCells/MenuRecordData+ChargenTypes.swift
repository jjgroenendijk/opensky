// The race menu's type ranges come from the chargen TRI of each race and sex, read
// once while the world loads. See docs/engine/race-menu.md.

import Foundation
import OpenSkyFormatsMesh
import OpenSkyGameData

nonisolated extension MenuRecordData {
    /// The highest `NoseType`, `EyesType`, and `LipType` target in each chargen TRI. A
    /// TRI that cannot be read leaves its race and sex out, so the menu keeps its default.
    func readChargenTypes(fileSystem: any GameFileSource) -> [ChargenTypeKey: [Int: Int]] {
        var byPath: [String: [Int: Int]?] = [:]
        var types: [ChargenTypeKey: [Int: Int]] = [:]
        for (key, path) in chargenTRIPaths {
            let counts = byPath[path] ?? Self.chargenTypes(path: path, fileSystem: fileSystem)
            byPath[path] = counts
            types[key] = counts
        }
        return types
    }

    private static func chargenTypes(path: String, fileSystem: any GameFileSource) -> [Int: Int]? {
        let key = path.lowercased().hasPrefix("meshes\\") ? path : "meshes\\\(path)"
        guard let tri = try? TRIFile(data: fileSystem.contents(forPath: key)) else { return nil }
        let names = tri.morphTargets.map(\.name)
        return Dictionary(uniqueKeysWithValues: FaceMorphCounts.groups.map {
            ($0.partIndex, FaceMorphCounts.highestType($0.targetPrefix, in: names))
        })
    }
}
