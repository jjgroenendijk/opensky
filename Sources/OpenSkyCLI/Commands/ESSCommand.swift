// `ess`: inspect a Skyrim `.ess` save read-only, or list a saves folder. With a data
// root the inspection also runs the import against the current load order.

import Foundation
import OpenSkyFormatsESS
import OpenSkyGameData
import OpenSkySave

enum ESSCommand {
    static func run(dataRoot: String?, scanner: inout ArgumentScanner) async throws {
        let target = try scanner.positional("<save.ess> or list <folder>")
        if target == "list" {
            let folder = try scanner.positional("<folder>")
            try scanner.finish()
            try list(URL(filePath: folder))
            return
        }
        let offline = scanner.flag("--offline")
        try scanner.finish()
        let file = try await ESSSaveFolder.readFile(at: URL(filePath: target))
        guard !offline else {
            print(ESSInspection(file: file, currentPlugins: []).text)
            return
        }
        let context = try CLIContext.resolve(dataRootOverride: dataRoot)
        let records = await ESSPluginRecords(index: ESSPluginIndex.load(
            for: file,
            root: context.root
        ))
        print(ESSInspection(file: file, currentPlugins: records.loadOrder, records: records).text)
        print("[INFO] inventory counts are read against an empty baseline in the CLI")
    }

    private static func list(_ folder: URL) throws {
        let status = ESSSaveFolder.status(of: folder)
        print("[INFO] \(status.message)")
        guard case .ready = status else { return }
        for listing in try ESSSaveFolder(directory: folder).listings() {
            if let header = listing.summary?.header {
                print(
                    "\(listing.name)\t\(header.playerName)\tlevel \(header.playerLevel)"
                        + "\t\(header.playerLocation)"
                )
            } else {
                print("\(listing.name)\t[ERROR] \(listing.error ?? "unreadable")")
            }
        }
    }
}
