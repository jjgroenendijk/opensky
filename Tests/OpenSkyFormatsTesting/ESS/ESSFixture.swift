// Synthetic Skyrim saves built in code. A real save holds the user's game data, so no
// test ever reads one from the repo (docs/formats/ess.md).

import Foundation
import OpenSkyFormatsCore

public struct ESSFixtureChangeForm {
    public var kind: UInt8
    public var value: UInt32
    public var flags: UInt32
    public var typeIndex: UInt8
    public var version: UInt8 = 74
    public var data: Data
    public var compressed = false

    public init(
        kind: UInt8, value: UInt32, flags: UInt32, typeIndex: UInt8, data: Data,
        compressed: Bool = false
    ) {
        self.kind = kind
        self.value = value
        self.flags = flags
        self.typeIndex = typeIndex
        self.data = data
        self.compressed = compressed
    }
}

public struct ESSFixture {
    public var version: UInt32 = 12
    public var formVersion: UInt8 = 78
    /// 0 none, 1 zlib, 2 LZ4.
    public var compression: UInt16 = 2
    public var playerName = "Prisoner"
    public var playerLevel: UInt32 = 3
    public var playerLocation = "Helgen Keep"
    public var gameDate = "Sundas, 17th of Last Seed, 4E 201"
    public var raceEditorID = "NordRace"
    public var isFemale = false
    public var experience: Float = 12.5
    public var nextLevelExperience: Float = 175
    public var fileTime: UInt64 = 133_000_000_000_000_000
    public var screenshotSize = (width: 2, height: 1)
    public var plugins = ["Skyrim.esm", "Update.esm"]
    public var lightPlugins: [String] = []
    public var globalData1: [(type: UInt32, data: Data)] = []
    public var globalData2: [(type: UInt32, data: Data)] = []
    public var globalData3: [(type: UInt32, data: Data)] = []
    public var changeForms: [ESSFixtureChangeForm] = []
    public var formIDArray: [UInt32] = []
    public var visitedWorldspaces: [UInt32] = [0x3C]
    /// Added to every location table offset, to build out-of-range tables.
    public var offsetSkew: [Int: Int] = [:]

    public init() {}

    public func build() -> Data {
        let header = headerBytes()
        var file = BinaryWriter()
        file.write(Data("TESV_SAVEGAME".utf8))
        file.writeUInt32(UInt32(header.count))
        file.write(header)
        let bytesPerPixel = version >= 12 ? 4 : 3
        let pixels = screenshotSize.width * screenshotSize.height
        file.write(Data((0 ..< pixels * bytesPerPixel).map { UInt8($0 & 0xFF) }))
        let lengthsSize = version >= 12 && compression != 0 ? 8 : 0
        let body = bodyBytes(base: file.count + lengthsSize)
        guard lengthsSize > 0 else {
            file.write(body)
            return file.data
        }
        let packed = compression == 1 ? ZlibFixture.stream(body) : ESSBytes.lz4LiteralBlock(body)
        file.writeUInt32(UInt32(body.count))
        file.writeUInt32(UInt32(packed.count))
        file.write(packed)
        return file.data
    }

    private func headerBytes() -> Data {
        ESSBytes.build { writer in
            writer.writeUInt32(version)
            writer.writeUInt32(7)
            ESSBytes.wstring(playerName, into: &writer)
            writer.writeUInt32(playerLevel)
            ESSBytes.wstring(playerLocation, into: &writer)
            ESSBytes.wstring(gameDate, into: &writer)
            ESSBytes.wstring(raceEditorID, into: &writer)
            writer.writeUInt16(isFemale ? 1 : 0)
            writer.writeFloat32(experience)
            writer.writeFloat32(nextLevelExperience)
            writer.writeUInt64(fileTime)
            writer.writeUInt32(UInt32(screenshotSize.width))
            writer.writeUInt32(UInt32(screenshotSize.height))
            if version >= 12 {
                writer.writeUInt16(compression)
            }
        }
    }

    /// `base` is the file offset the body would start at uncompressed.
    private func bodyBytes(base: Int) -> Data {
        let lists = pluginBytes()
        let tableStart = 1 + 4 + lists.count
        let sections = [
            tables(globalData1), tables(globalData2), changeFormBytes(), tables(globalData3),
            idArrays(), Data([0, 0, 0, 0])
        ]
        var offsets: [Int] = []
        var position = tableStart + 100
        for section in sections {
            offsets.append(position)
            position += section.count
        }
        var writer = BinaryWriter()
        writer.writeUInt8(formVersion)
        writer.writeUInt32(UInt32(lists.count))
        writer.write(lists)
        for index in [4, 5, 0, 1, 2, 3] {
            writer.writeUInt32(UInt32(base + offsets[index] + (offsetSkew[index] ?? 0)))
        }
        for count in [globalData1.count, globalData2.count, max(0, globalData3.count - 1)] {
            writer.writeUInt32(UInt32(count))
        }
        writer.writeUInt32(UInt32(changeForms.count))
        writer.write(Data(count: 60))
        sections.forEach { writer.write($0) }
        return writer.data
    }

    private func pluginBytes() -> Data {
        ESSBytes.build { writer in
            writer.writeUInt8(UInt8(plugins.count))
            plugins.forEach { ESSBytes.wstring($0, into: &writer) }
            if version >= 12, formVersion >= 78 {
                writer.writeUInt16(UInt16(lightPlugins.count))
                lightPlugins.forEach { ESSBytes.wstring($0, into: &writer) }
            }
        }
    }

    private func tables(_ entries: [(type: UInt32, data: Data)]) -> Data {
        ESSBytes.build { writer in
            for entry in entries {
                writer.writeUInt32(entry.type)
                writer.writeUInt32(UInt32(entry.data.count))
                writer.write(entry.data)
            }
        }
    }

    private func changeFormBytes() -> Data {
        ESSBytes.build { writer in
            for form in changeForms {
                ESSBytes.refID(kind: form.kind, value: form.value, into: &writer)
                writer.writeUInt32(form.flags)
                writer.writeUInt8(2 << 6 | form.typeIndex)
                writer.writeUInt8(form.version)
                let stored = form.compressed ? ZlibFixture.stream(form.data) : form.data
                writer.writeUInt32(UInt32(stored.count))
                writer.writeUInt32(form.compressed ? UInt32(form.data.count) : 0)
                writer.write(stored)
            }
        }
    }

    private func idArrays() -> Data {
        ESSBytes.build { writer in
            writer.writeUInt32(UInt32(formIDArray.count))
            formIDArray.forEach { writer.writeUInt32($0) }
            writer.writeUInt32(UInt32(visitedWorldspaces.count))
            visitedWorldspaces.forEach { writer.writeUInt32($0) }
        }
    }
}
