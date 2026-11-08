// A fresh folder for save slots, removed by the caller with `defer`.

import Foundation

enum TemporarySaveDirectory {
    static func make() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "opensky-saves-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }
}
