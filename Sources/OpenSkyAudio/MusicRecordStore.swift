// MUSC and MUST records, and MUSC -> MUST expansion. Track filenames become
// VFS keys, so callers skip the path rules (docs/formats/music.md).

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public enum MusicResolveError: Error, Equatable {
    case musicTypeNotFound(FormID)
}

nonisolated public struct ResolvedMusicType: Sendable {
    public let musicType: MusicType
    /// MUST records named by TNAM, in authored order. FormIDs that resolve to
    /// nothing are dropped.
    public let tracks: [MusicTrack]
}

nonisolated public final class MusicRecordStore {
    public let musicTypes: [UInt32: MusicType]
    public let musicTracks: [UInt32: MusicTrack]
    public let skippedRecords: SkippedRecords

    public convenience init(file: ESMFile) {
        self.init(loadOrder: LoadOrderPlugins(file: file))
    }

    public init(loadOrder: LoadOrderPlugins) {
        var skipped = SkippedRecords()
        musicTypes = loadOrder
            .indexRecords(of: "MUSC", skipped: &skipped) { try MusicType(record: $0) }
        musicTracks = loadOrder.indexRecords(of: "MUST", skipped: &skipped) {
            try MusicTrack(record: $0)
        }
        skippedRecords = skipped
    }

    public func musicType(_ id: FormID) -> MusicType? {
        musicTypes[id.rawValue]
    }

    public func musicTrack(_ id: FormID) -> MusicTrack? {
        musicTracks[id.rawValue]
    }

    public func resolve(musicType id: FormID) throws -> ResolvedMusicType {
        guard let musicType = musicType(id) else {
            throw MusicResolveError.musicTypeNotFound(id)
        }
        return ResolvedMusicType(
            musicType: musicType,
            tracks: musicType.tracks.compactMap { musicTracks[$0.rawValue] }
        )
    }

    /// Canonical VFS keys for a track's audio files: the ANAM stream first,
    /// then the BNAM finale when present. Entries that fail the path rules are
    /// dropped rather than substituted.
    public func audioPaths(for track: MusicTrack) -> [String] {
        [track.trackFileName, track.finaleFileName]
            .compactMap(\.self)
            .compactMap(Self.canonicalMusicPath)
    }

    /// Normalizes a MUST ANAM/BNAM filename into a `music\...` VFS key. A leading
    /// `\Data\` is stripped (209 of 242 vanilla tracks use it); a `:` is rejected.
    public static func canonicalMusicPath(_ track: String) -> String? {
        guard let normalized = try? VirtualFileSystem.normalize(track) else {
            return nil
        }
        guard !normalized.contains(":") else {
            return nil
        }
        if normalized.hasPrefix("data\\music\\") {
            return String(normalized.dropFirst("data\\".count))
        }
        if normalized.hasPrefix("music\\") {
            return normalized
        }
        return try? VirtualFileSystem.normalize("music\\\(normalized)")
    }

    /// Extension every music asset in the shipped archives actually uses.
    public static let shippedMusicExtension = "xwm"

    /// `path` with its extension replaced by `.xwm`, or nil when it is already
    /// `.xwm` or has none. Only the last path component counts.
    public static func shippedAudioSibling(of path: String) -> String? {
        guard let dot = path.lastIndex(of: ".") else { return nil }
        let ext = path[path.index(after: dot)...]
        guard !ext.isEmpty, !ext.contains("\\") else { return nil }
        guard ext.lowercased() != shippedMusicExtension else { return nil }
        return path[..<dot] + ".\(shippedMusicExtension)"
    }

    /// Loads `path`, then its `.xwm` sibling: vanilla MUST ANAM names `.wav`, but
    /// the archives hold only `.xwm`. Returns the key that loaded. When both
    /// fail, it rethrows the error for `path`.
    public static func loadAudioFile(
        at path: String,
        load: (String) throws -> Data
    ) throws -> (key: String, data: Data) {
        do {
            return try (key: path, data: load(path))
        } catch {
            guard
                let sibling = shippedAudioSibling(of: path),
                let data = try? load(sibling)
            else {
                throw error
            }
            return (key: sibling, data: data)
        }
    }
}
