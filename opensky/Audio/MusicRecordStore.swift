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
    /// Kit writes the bare form, the `Data\`-rooted form, and the separator-led
    /// `\Data\Music\...` form. That leading separator is a Windows root-relative
    /// marker, not a volume, so it is stripped rather than treated as an escape:
    /// on the shipped `Skyrim.esm` 209 of the 242 distinct track filenames are
    /// authored that way, and rejecting them dropped most of the vanilla
    /// playlists. A path still carrying a `:` after normalization names a
    /// drive or volume and is rejected outright; `VirtualFileSystem.normalize`
    /// rejects `.` and `..` components, so nothing can leave the data root.
    static func canonicalMusicPath(_ track: String) -> String? {
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
    static let shippedMusicExtension = "xwm"

    /// Same directory and stem as `path` with the extension replaced by `.xwm`,
    /// or nil when `path` already names an `.xwm` or carries no extension at
    /// all. Only the final component is considered, so a directory containing a
    /// dot cannot be mistaken for an extension.
    static func shippedAudioSibling(of path: String) -> String? {
        guard let dot = path.lastIndex(of: ".") else { return nil }
        let ext = path[path.index(after: dot)...]
        guard !ext.isEmpty, !ext.contains("\\") else { return nil }
        guard ext.lowercased() != shippedMusicExtension else { return nil }
        return path[..<dot] + ".\(shippedMusicExtension)"
    }

    /// Loads one canonical music path through `load`, which is the caller's
    /// reach into the VFS (`VirtualFileSystem.contents(forPath:)` in
    /// production, a stub in tests). Returns the key that actually loaded
    /// alongside its bytes, so a caller can report the real file rather than
    /// the authored name.
    ///
    /// The fallback lives here, at the load site, rather than in
    /// `canonicalMusicPath`: the canonical rule is a pure string transform with
    /// no way to tell an authored name that exists from one that does not, so
    /// rewriting the extension there would be a blind guess applied to every
    /// track. Here the authored name is tried first and the `.xwm` sibling only
    /// when the authored one is absent. That fallback exists because of
    /// observed archive contents: on the shipped install every `MUST ANAM`
    /// names a `.wav` while `music\` holds `.xwm` files only, so the authored
    /// name never resolves for vanilla music (issue #246). A track that exists
    /// under neither name rethrows the authored path's own error, so a
    /// genuinely missing file is still reported as missing.
    static func loadAudioFile(
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
