// SOUN, SNDR, and SNCT records, and SOUN -> SNDR -> audio-file resolution.
// Track paths become VFS keys, so callers skip the path rules.

import Foundation
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyGameData

nonisolated public enum SoundResolveError: Error, Equatable {
    case soundNotFound(FormID)
    case descriptorNotFound(FormID, sound: FormID)
}

nonisolated public struct ResolvedSound: Sendable {
    public let sound: SoundMarker
    public let descriptor: SoundDescriptor
    public let audioCategory: AudioCategory?
    public let filePaths: [String]
}

nonisolated public final class SoundRecordStore {
    public let sounds: [UInt32: SoundMarker]
    public let descriptors: [UInt32: SoundDescriptor]
    public let categories: [UInt32: SoundCategory]
    public let skippedRecords: SkippedRecords

    public init(file: ESMFile) {
        var skipped = SkippedRecords()
        sounds = file.indexRecords(of: "SOUN", skipped: &skipped) { try SoundMarker(record: $0) }
        descriptors = file.indexRecords(of: "SNDR", skipped: &skipped) {
            try SoundDescriptor(record: $0)
        }
        let localized = (try? file.pluginHeader().isLocalized) ?? false
        categories = file.indexRecords(of: "SNCT", skipped: &skipped) {
            try SoundCategory(record: $0, localized: localized)
        }
        skippedRecords = skipped
    }

    public func sound(_ id: FormID) -> SoundMarker? {
        sounds[id.rawValue]
    }

    public func descriptor(_ id: FormID) -> SoundDescriptor? {
        descriptors[id.rawValue]
    }

    public func category(_ id: FormID) -> SoundCategory? {
        categories[id.rawValue]
    }

    public func resolve(sound id: FormID) throws -> ResolvedSound {
        guard let sound = sound(id) else {
            throw SoundResolveError.soundNotFound(id)
        }
        let descriptorID = sound.descriptor ?? FormID(0)
        guard let descriptor = descriptor(descriptorID) else {
            throw SoundResolveError.descriptorNotFound(descriptorID, sound: id)
        }
        return resolved(sound: sound, descriptor: descriptor)
    }

    /// Resolves a FormID that names either a SNDR or a SOUN marker. Activator,
    /// door, and container sound fields do not say which. Throws `soundNotFound`
    /// for anything else.
    public func resolveAny(_ id: FormID) throws -> ResolvedSound {
        // A direct SNDR gets a synthetic marker, so both paths return one shape.
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
    public func audioCategory(for descriptor: SoundDescriptor) -> AudioCategory? {
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

    /// Normalizes an SNDR ANAM filename into a `sound\...` VFS key. A leading
    /// separator is stripped; a `:` names a drive and is rejected.
    private static func canonicalSoundPath(_ track: String) -> String? {
        guard let normalized = try? VirtualFileSystem.normalize(track) else {
            return nil
        }
        guard !normalized.contains(":") else {
            return nil
        }
        // VFS keys are relative to Data, so a `data\` prefix goes.
        if normalized.hasPrefix("data\\sound\\") {
            return String(normalized.dropFirst("data\\".count))
        }
        if normalized.hasPrefix("sound\\") {
            return normalized
        }
        return try? VirtualFileSystem.normalize("sound\\\(normalized)")
    }
}
