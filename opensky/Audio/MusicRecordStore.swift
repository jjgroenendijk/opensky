// Music record index and MUSC -> MUST expansion. Track filenames become
// canonical VFS keys so callers can pass them straight to game-data lookup
// without reproducing record-specific path rules.
//
// Layout references live on the record decoders (MusicRecords.swift); the
// path policy is documented in docs/formats/music.md.

import Foundation

nonisolated enum MusicResolveError: Error, Equatable {
    case musicTypeNotFound(FormID)
}

nonisolated struct ResolvedMusicType {
    let musicType: MusicType
    /// MUST records named by TNAM, in authored order. FormIDs that resolve to
    /// nothing (null separators, records from an absent master) are dropped
    /// without reordering the survivors.
    let tracks: [MusicTrack]
}

nonisolated final class MusicRecordStore {
    let musicTypes: [UInt32: MusicType]
    let musicTracks: [UInt32: MusicTrack]

    init(file: ESMFile) {
        musicTypes = Self.index(file, type: "MUSC") { try? MusicType(record: $0) }
        musicTracks = Self.index(file, type: "MUST") { try? MusicTrack(record: $0) }
    }

    func musicType(_ id: FormID) -> MusicType? {
        musicTypes[id.rawValue]
    }

    func musicTrack(_ id: FormID) -> MusicTrack? {
        musicTracks[id.rawValue]
    }

    func resolve(musicType id: FormID) throws -> ResolvedMusicType {
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
    func audioPaths(for track: MusicTrack) -> [String] {
        [track.trackFileName, track.finaleFileName]
            .compactMap(\.self)
            .compactMap(Self.canonicalMusicPath)
    }

    private static func index<Value>(
        _ file: ESMFile,
        type: FourCC,
        decode: (ESMRecord) -> Value?
    ) -> [UInt32: Value] {
        var values: [UInt32: Value] = [:]
        guard let group = file.topGroup(of: type), let children = try? group.children() else {
            return values
        }
        for case let .record(record) in children where record.type == type {
            if let value = decode(record) {
                values[record.formID] = value
            }
        }
        return values
    }

    /// Normalizes a MUST ANAM/BNAM filename into a VFS key. Music assets live
    /// under `music\...` (not `sound\...` like SNDR tracks), and the Creation
    /// Kit writes both the bare and the `Data\`-rooted form. Absolute paths and
    /// paths carrying a drive/volume separator are rejected outright.
    static func canonicalMusicPath(_ track: String) -> String? {
        guard let normalized = try? VirtualFileSystem.normalize(track) else {
            return nil
        }
        guard
            !track.hasPrefix("/"),
            !track.hasPrefix("\\"),
            !normalized.contains(":")
        else {
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
}
