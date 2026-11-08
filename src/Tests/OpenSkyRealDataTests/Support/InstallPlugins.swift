// The plugin set the whole-install sweeps walk: the five masters, then the
// Creation Club plugins in name order.

import Foundation
@testable import OpenSkyGameData

enum InstallPlugins {
    static func names(root: GameDataRoot) throws -> [String] {
        let all = try FileManager.default.contentsOfDirectory(atPath: root.dataURL.path)
        let creationClub = all.filter { name in
            let lower = name.lowercased()
            return lower.hasPrefix("cc") && (lower.hasSuffix(".esm") || lower.hasSuffix(".esl"))
        }
        return VanillaMasters.names + creationClub.sorted()
    }
}
