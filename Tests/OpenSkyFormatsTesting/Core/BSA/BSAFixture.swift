// Synthetic BSA v105 builder shared by parser and VFS tests. Fixtures are
// built in code — never extracted game files (AGENTS.md "Legal & IP boundary").

import Foundation

/// Builds a minimal spec-conformant BSA v105 byte blob.
public struct BSAFixture: Sendable {
    public struct File: Sendable {
        public let folder: String
        public let name: String
        /// Bytes stored in the data area, verbatim.
        public let stored: Data
        /// Toggle bit 30 of the size field (inverts archive default compression).
        public var toggleCompression = false

        public init(folder: String, name: String, stored: Data, toggleCompression: Bool = false) {
            self.folder = folder
            self.name = name
            self.stored = stored
            self.toggleCompression = toggleCompression
        }
    }

    public var flags: UInt32 = 0x3 // folder + file names present
    public var files: [File] = []

    public func build() -> Data {
        // Preserve first-seen folder order.
        var folders: [(name: String, files: [File])] = []
        for file in files {
            if let index = folders.firstIndex(where: { $0.name == file.folder }) {
                folders[index].files.append(file)
            } else {
                folders.append((file.folder, [file]))
            }
        }

        let headerSize = 36
        let folderRecordsSize = folders.count * 24
        let blocksSize = folders.reduce(0) { $0 + 2 + $1.name.count + 16 * $1.files.count }
        let namesSize = files.reduce(0) { $0 + $1.name.count + 1 }
        let totalFolderNameLength = folders.reduce(0) { $0 + $1.name.count + 1 }
        var dataOffset = headerSize + folderRecordsSize + blocksSize + namesSize

        var header = Data("BSA\0".utf8)
        header.appendUInt32(105)
        header.appendUInt32(UInt32(headerSize))
        header.appendUInt32(flags)
        header.appendUInt32(UInt32(folders.count))
        header.appendUInt32(UInt32(files.count))
        header.appendUInt32(UInt32(totalFolderNameLength))
        header.appendUInt32(UInt32(namesSize))
        header.appendUInt32(0) // fileFlags

        var records = Data()
        var blocks = Data()
        var names = Data()
        var payloads = Data()
        var blockOffset = headerSize + folderRecordsSize
        for (name, folderFiles) in folders {
            records.appendUInt64(0) // name hash — parser keys by names
            records.appendUInt32(UInt32(folderFiles.count))
            records.appendUInt32(0) // padding
            // Stored offset includes totalFileNameLength (format quirk).
            records.appendUInt64(UInt64(blockOffset + namesSize))

            blocks.append(UInt8(name.count + 1))
            blocks.append(Data(name.utf8))
            blocks.append(0)
            for file in folderFiles {
                var size = UInt32(file.stored.count)
                if file.toggleCompression {
                    size |= 0x4000_0000
                }
                blocks.appendUInt64(0) // name hash
                blocks.appendUInt32(size)
                blocks.appendUInt32(UInt32(dataOffset))
                payloads.append(file.stored)
                dataOffset += file.stored.count
                names.append(Data(file.name.utf8))
                names.append(0)
            }
            blockOffset += 2 + name.count + 16 * folderFiles.count
        }
        return header + records + blocks + names + payloads
    }

    public init(flags: UInt32 = 0x3, files: [File] = []) {
        self.flags = flags
        self.files = files
    }
}

extension Data {
    public mutating func appendUInt16(_ value: UInt16) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    public mutating func appendUInt32(_ value: UInt32) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    public mutating func appendUInt64(_ value: UInt64) {
        Swift.withUnsafeBytes(of: value.littleEndian) { append(contentsOf: $0) }
    }

    public mutating func appendFloat32(_ value: Float) {
        appendUInt32(value.bitPattern)
    }

    public mutating func appendFloat16(_ value: Float) {
        appendUInt16(Float16(value).bitPattern)
    }
}
