// A plugin's FormID index as bytes, so a session can read it back instead of
// walking every record header again. Layout: docs/formats/esm.md#saved-formid-index.

import Foundation
import OpenSkyFormatsCore

/// Where saved FormID indexes live. The asset cache folder is the app's store.
nonisolated public protocol FormIDIndexStore: Sendable {
    func savedIndex(for stamp: ESMFileStamp) -> Data?
    func save(_ index: Data, for stamp: ESMFileStamp)
}

nonisolated extension ESMFormIDIndex {
    static let savedMagic: FourCC = "OSRI"
    static let savedVersion: UInt32 = 1
    private static let headerSize = 12
    private static let entrySize = 16

    public func saved() -> Data {
        var writer = BinaryWriter()
        writer.writeUInt32(Self.savedMagic.rawValue)
        writer.writeUInt32(Self.savedVersion)
        writer.writeUInt32(UInt32(entries.count))
        for entry in entries {
            writer.writeUInt32(entry.formID)
            writer.writeUInt32(entry.offset)
            writer.writeUInt32(entry.cell)
            writer.writeUInt32(entry.world)
        }
        return writer.data
    }

    /// Nil when the bytes are not a saved index of this version, or do not fit `file`.
    public init?(file: ESMFile, saved: Data) {
        guard saved.count >= Self.headerSize else { return nil }
        var reader = BinaryReader(saved)
        guard
            let magic = try? reader.readUInt32(), magic == Self.savedMagic.rawValue,
            let version = try? reader.readUInt32(), version == Self.savedVersion,
            let count = try? Int(reader.readUInt32()),
            saved.count == Self.headerSize + count * Self.entrySize
        else { return nil }
        var entries: [Entry] = []
        entries.reserveCapacity(count)
        let limit = file.data.count - ESMRecord.Header.size
        for _ in 0 ..< count {
            guard
                let formID = try? reader.readUInt32(), let offset = try? reader.readUInt32(),
                let cell = try? reader.readUInt32(), let world = try? reader.readUInt32(),
                Int(offset) <= limit, formID >= entries.last?.formID ?? 0
            else { return nil }
            entries.append(Entry(formID: formID, offset: offset, cell: cell, world: world))
        }
        self.init(data: file.data, entries: entries)
    }

    /// The saved index when `store` has one for this file, else a new walk, saved.
    public static func loading(file: ESMFile, store: (any FormIDIndexStore)?) -> Self {
        guard let store, let stamp = file.stamp else { return Self(file: file) }
        if let saved = store.savedIndex(for: stamp), let index = Self(file: file, saved: saved) {
            return index
        }
        let index = Self(file: file)
        store.save(index.saved(), for: stamp)
        return index
    }
}
