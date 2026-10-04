// A file source that books every read to `LoadPhase.archive`, so a benchmark
// can see archive time without the VFS knowing about benchmarks.

import Foundation

nonisolated public struct PhaseTimedFileSource: GameFileSource {
    public let base: any GameFileSource
    public let recorder: LoadPhaseRecorder

    public init(base: any GameFileSource, recorder: LoadPhaseRecorder) {
        self.base = base
        self.recorder = recorder
    }

    public func exists(_ path: String) -> Bool {
        recorder.measure(.archive) { base.exists(path) }
    }

    public func contents(forPath path: String) throws -> Data {
        try recorder.measure(.archive) { try base.contents(forPath: path) }
    }

    public func archiveEntries() -> [VFSEntry] {
        base.archiveEntries()
    }

    public func fileNames(inDirectory directory: String) -> [String] {
        base.fileNames(inDirectory: directory)
    }
}
