// A run directory under `.logs/<name>/<UTC time>/`, with `latest` pointing at it: the
// layout of `tools/run-dir.sh` (docs/tools/run-output.md).

import Foundation

enum RunDirectory {
    static func create(_ name: String) throws -> URL {
        let current = URL(
            filePath: FileManager.default.currentDirectoryPath,
            directoryHint: .isDirectory
        )
        let stamp = Date()
            .formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
                .timeSeparator(.omitted).dateSeparator(.omitted))
        let base = current.appending(path: ".logs/\(name)")
        let run = base.appending(path: stamp, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        let latest = base.appending(path: "latest")
        try? FileManager.default.removeItem(at: latest)
        try? FileManager.default.createSymbolicLink(
            atPath: latest.path(percentEncoded: false),
            withDestinationPath: stamp
        )
        return run
    }
}
