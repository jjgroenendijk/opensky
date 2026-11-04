// Finds the bytes of one voice line. Vanilla ships `.fuz` files; mods often ship the
// loose `.xwm` or `.wav` and `.lip` the Creation Kit joins into one. See docs/formats/fuz.md.

import Foundation
import OpenSkyFormatsAudio

nonisolated public enum VoiceLineFiles {
    /// The `.fuz` at `path`, or one joined from the loose `.xwm` (else `.wav`) and
    /// optional `.lip` beside it when the `.fuz` is missing. Otherwise the `.fuz` read's own error.
    public static func contents(
        forPath path: String,
        exists: (String) -> Bool,
        read: (String) throws -> Data
    ) throws -> Data {
        guard path.hasSuffix(".fuz"), !exists(path) else { return try read(path) }
        let stem = String(path.dropLast("fuz".count))
        let lipPath = stem + "lip"
        guard let audioPath = [stem + "xwm", stem + "wav"].first(where: exists) else {
            return try read(path)
        }
        let lip = exists(lipPath) ? try read(lipPath) : nil
        return try FUZFile.pack(lip: lip, audio: read(audioPath))
    }
}
