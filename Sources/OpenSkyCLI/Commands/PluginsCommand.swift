// `plugins`: the resolved load order and its plugins.txt. Point
// OPENSKY_PLUGINS_TXT at a file to check a load order without the game.

import Foundation
import OpenSkyGameData

enum PluginsCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        try scanner.finish()
        let report = PluginLoadOrderReport(
            resolution: PluginLoadOrder.resolve(root: context.root)
        )
        print("plugins.txt: \(report.pluginsTextPath)")
        print("[INFO] \(report.sourceNote)")
        if let problem = report.problem {
            print("[WARNING] \(problem)")
        }
        for row in report.rows {
            let note = row.note.isEmpty ? "" : " — \(row.note)"
            print("\(row.position)\t\(row.name) [\(row.origin)]\(note)")
        }
        print("[INFO] \(report.summary)")
    }
}
