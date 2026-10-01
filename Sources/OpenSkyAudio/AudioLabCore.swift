// The pure rules behind the World > Audio pickers and triggers. The shell is
// `AudioCoordinator` in OpenSkyWorld (docs/engine/coordinators.md).

import Foundation
import OpenSkyGameData
import simd

/// Picker lists, trigger placement, and readout lines for the audio panel.
nonisolated public enum AudioLabCore {
    /// A popup is unusable past a few hundred entries, so the filter is the real navigation.
    public static let voicePickerLimit = 200
    /// About 10 m ahead of the camera, so turning or strafing makes the panning obvious.
    public static let triggerOffsetUnits: Float = 700
    /// A voice-type directory, so the picker is useful before the user types.
    public static let defaultVoiceFilter = "sound\\voice\\skyrim.esm\\femaleeventoned\\"

    /// Vanilla holds 269 `.xwm` files, all music.
    public static func musicPaths(in entries: [VFSEntry]) -> [String] {
        entries.map(\.path)
            .filter { $0.lowercased().hasSuffix(".xwm") }
            .sorted()
    }

    public static func voicePaths(in entries: [VFSEntry]) -> [String] {
        entries.map(\.path)
            .filter { $0.hasSuffix(".fuz") }
            .sorted()
    }

    /// Matches on the canonical VFS key: lowercase, backslash separators.
    public static func voiceMatches(in paths: [String], filter: String) -> [String] {
        let needle = filter.lowercased().replacingOccurrences(of: "/", with: "\\")
        return needle.isEmpty ? paths : paths.filter { $0.contains(needle) }
    }

    public static func triggerPosition(camera: SIMD3<Float>, yaw: Float) -> SIMD3<Float> {
        camera + AudioSpace.worldForward(yaw: yaw, pitch: 0) * triggerOffsetUnits
    }

    /// Voice-type directory plus file name: the part that names the line in a panel column.
    public static func shortVoiceName(_ path: String) -> String {
        path.split(separator: "\\").suffix(2).joined(separator: "\\")
    }

    public static func voiceDescription(path: String, playback: VoicePlayback) -> String {
        let lip = playback.lipData.map { "\($0.count) lip bytes" } ?? "no lip data"
        let length = playback.duration.map { String(format: "%.2f s", $0) } ?? "unknown length"
        return "\(shortVoiceName(path)) — \(length), \(lip)"
    }

    /// `position` is nil once the engine retired the source.
    public static func playbackDescription(
        playback: VoicePlayback,
        finished: Bool,
        position: Double?
    ) -> String {
        let total = playback.duration.map { String(format: "%.2f", $0) } ?? "?"
        guard !finished else {
            return "Position: finished at \(total) s"
        }
        guard let position else {
            return "Position: no reading (source retired or not yet rendering)"
        }
        return String(format: "Position: %.2f / %@ s", position, total)
    }
}
