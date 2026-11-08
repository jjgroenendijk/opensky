// `install`: prints the game folder check. `--data-root` is checked as given,
// so a folder the locator rejects still gets its problems listed.

import Foundation
import OpenSkyGameData
import OpenSkyLaunch

enum InstallCommand {
    static func run(dataRoot: String?) throws {
        let install: URL
        if let dataRoot {
            let path = NSString(string: dataRoot).expandingTildeInPath
            let url = URL(filePath: path, directoryHint: .isDirectory)
            install = url.lastPathComponent.lowercased() == "data"
                ? url.deletingLastPathComponent() : url
        } else {
            install = try GameDataLocator.locate().installURL
        }
        let summary = GameInstallCheck.run(installURL: install)
        print("Folder: \(install.path(percentEncoded: false))")
        print("[INFO] \(summary.headline)")
        print("[INFO] \(summary.countLine)")
        for dlc in summary.dlc {
            print("DLC: \(dlc.title)")
        }
        for line in summary.problemLines {
            print("[WARNING] \(line)")
        }
        guard summary.isComplete else {
            throw CLIError.failure("\(summary.problems.count) install problems")
        }
    }
}
