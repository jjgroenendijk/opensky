// `plugins`: the resolved plugin load order and the plugins.txt it came from
// (issue #73). The terminal half of the Library > Load Order panel, and the
// only way to check a load order on a machine where the game has never been
// launched: point OPENSKY_PLUGINS_TXT at a file and see what the engine makes
// of it.

import Foundation

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
