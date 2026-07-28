// Sound record index and SOUN -> SNDR -> audio-file resolution. Track paths
// become canonical VFS keys so callers can pass them directly to game-data
// lookup without reproducing record-specific path rules.

import Foundation

nonisolated enum SoundResolveError: Error, Equatable {
    case soundNotFound(FormID)
    case descriptorNotFound(FormID, sound: FormID)
}

nonisolated struct ResolvedSound {
    let sound: SoundMarker
    let descriptor: SoundDescriptor
    let audioCategory: AudioCategory?
    let filePaths: [String]
}

nonisolated final class SoundRecordStore {
    let sounds: [UInt32: SoundMarker]
    let descriptors: [UInt32: SoundDescriptor]
    let categories: [UInt32: SoundCategory]

    init(file: ESMFile) {
        sounds = Self.index(file, type: "SOUN") { try? SoundMarker(record: $0) }
        descriptors = Self.index(file, type: "SNDR") {
            try? SoundDescriptor(record: $0)
        }
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        categories = Self.index(file, type: "SNCT") {
            try? SoundCategory(record: $0, localized: localized)
        }
    }

    func sound(_ id: FormID) -> SoundMarker? {
        sounds[id.rawValue]
    }

    func descriptor(_ id: FormID) -> SoundDescriptor? {
        descriptors[id.rawValue]
    }

    func category(_ id: FormID) -> SoundCategory? {
        categories[id.rawValue]
    }

    func resolve(sound id: FormID) throws -> ResolvedSound {
        guard let sound = sound(id) else {
            throw SoundResolveError.soundNotFound(id)
        }
        let descriptorID = sound.descriptor ?? FormID(0)
        guard let descriptor = descriptor(descriptorID) else {
            throw SoundResolveError.descriptorNotFound(descriptorID, sound: id)
        }
        return resolved(sound: sound, descriptor: descriptor)
    }

    /// Resolves a sound reference that may target a SNDR directly or reach it
    /// via a SOUN legacy marker. activator/door/container sound fields store
    /// raw FormIDs whose target type the decoder does not pin, so runtime
    /// consumers route them through here. Throws `soundNotFound` when the
    /// reference is neither a SOUN nor a SNDR.
    func resolveAny(_ id: FormID) throws -> ResolvedSound {
        // Direct SNDR hit: synthesize a marker so the public shape stays
        // consistent with the SOUN path.
        if let descriptor = descriptors[id.rawValue] {
            return resolved(
                sound: SoundMarker(formID: id, editorID: nil, descriptor: id),
                descriptor: descriptor
            )
        }
        return try resolve(sound: id)
    }

    /// Walks SNCT.PNAM until it reaches one of vanilla's four menu categories.
    /// A visited set makes malformed mod cycles terminate without inventing a
    /// category; callers choose their own fallback.
    func audioCategory(for descriptor: SoundDescriptor) -> AudioCategory? {
        var current = descriptor.category
        var visited: Set<UInt32> = []
        while let id = current, visited.insert(id.rawValue).inserted {
            guard let category = category(id) else { return nil }
            if
                category.flags.contains(.shouldAppearOnMenu),
                let audioCategory = AudioCategory(
                    soundCategoryEditorID: category.editorID
                )
            {
                return audioCategory
            }
            current = category.parent
        }
        return nil
    }

    private func resolved(
        sound: SoundMarker,
        descriptor: SoundDescriptor
    ) -> ResolvedSound {
        ResolvedSound(
            sound: sound,
            descriptor: descriptor,
            audioCategory: audioCategory(for: descriptor),
            filePaths: descriptor.tracks.compactMap(Self.canonicalSoundPath)
        )
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

    private static func canonicalSoundPath(_ track: String) -> String? {
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
        // The Creation Kit writes both Sound\... and Data\Sound\... ANAM
        // forms; VFS keys are relative to Data, so discard that outer root.
        if normalized.hasPrefix("data\\sound\\") {
            return String(normalized.dropFirst("data\\".count))
        }
        if normalized.hasPrefix("sound\\") {
            return normalized
        }
        return try? VirtualFileSystem.normalize("sound\\\(normalized)")
    }
}
