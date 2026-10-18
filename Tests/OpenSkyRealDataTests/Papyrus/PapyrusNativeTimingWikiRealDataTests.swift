// Mirror-gated check of the native timing table against the Creation Kit wiki's
// "Non-delayed Native Function" and "Latent Functions" categories. Only names and
// labels are read; the report goes to gitignored .logs/.

import Foundation
@testable import OpenSkyScripting
import OpenSkyTagsTesting
import Testing

@Suite(.tags(.smoke))
@MainActor
struct PapyrusNativeTimingWikiRealDataTests {
    @Test(.enabled(if: CreationKitWikiMirror.isAvailable))
    func everyBoundNativeHasTheWikiTiming() throws {
        let mirror = try #require(CreationKitWikiMirror.directory)
        let pages = try Self.functionPages(in: mirror)
        let registry = PapyrusNativeRegistry.standard(context: PapyrusNativeContext())

        var unlabelled: [String] = []
        var checked = 0
        for (script, function) in registry.registeredNames {
            let key = PapyrusNativeKey(scriptName: script, functionName: function)
            guard let wiki = pages[key] else {
                unlabelled.append("\(script).\(function)")
                continue
            }
            checked += 1
            let ours = PapyrusNativeTimingTable.timing(of: key)
            #expect(ours == wiki, "\(script).\(function) is \(ours), the wiki says \(wiki)")
        }
        for key in PapyrusNativeTimingTable.nonDelayed.union(PapyrusNativeTimingTable.latent) {
            let ours = PapyrusNativeTimingTable.timing(of: key)
            let name = "\(key.scriptName).\(key.functionName)"
            #expect(pages[key] == ours, "\(name) is \(ours) in the table but not on the wiki")
        }

        let lines = [
            "Bound natives: \(registry.count)",
            "Checked against the wiki: \(checked)",
            "No wiki page (\(unlabelled.count)):"
        ] + unlabelled.map { "  " + $0 }
        let logs = try RepositoryLogs.createdDirectory("native-timing")
        try lines.joined(separator: "\n").write(
            to: logs.appending(path: "report.txt"), atomically: true, encoding: .utf8
        )
        print(lines.prefix(3).joined(separator: "\n"))
        #expect(checked > 0)
    }

    /// Every "Function - Script" page with its timing class. A page in neither category
    /// is delayed.
    private static func functionPages(in mirror: URL) throws
        -> [PapyrusNativeKey: PapyrusNativeTiming]
    {
        var pages: [PapyrusNativeKey: PapyrusNativeTiming] = [:]
        let files = try FileManager.default.contentsOfDirectory(atPath: mirror.path)
        for file in files where file.hasSuffix(".md") {
            let title = file.dropLast(3)
            let parts = title.components(separatedBy: " - ")
            guard parts.count == 2, !parts[0].contains(" "), !parts[1].contains(" ") else {
                continue
            }
            let key = PapyrusNativeKey(scriptName: parts[1], functionName: parts[0])
            let text = try String(contentsOf: mirror.appending(path: file), encoding: .utf8)
            let categories = text.split(separator: "\n").first { $0.hasPrefix("categories:") } ?? ""
            pages[key] = if categories.contains("\"Non-delayed Native Function\"") {
                .nonDelayed
            } else if categories.contains("\"Latent Functions\"") {
                .latent
            } else {
                .delayed
            }
        }
        return pages
    }
}
