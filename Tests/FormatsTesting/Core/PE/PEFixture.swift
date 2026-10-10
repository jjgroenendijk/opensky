// A minimal Windows executable with one `.rsrc` section that holds a version
// resource, built in code. Layout: docs/formats/pe-version.md.

import Foundation

public struct PEFixture: Sendable {
    /// Major, minor, build, and revision.
    public var version: [UInt16] = [1, 6, 1170, 0]
    /// Another resource type listed before the version, such as 3 for icons.
    public var otherResourceType: UInt32?
    public var signature: UInt32 = 0xFEEF_04BD
    public var includesVersion = true

    private static let rawOffset = 0x200
    private static let virtualAddress: UInt32 = 0x1000

    public init() {}

    public func build() -> Data {
        var file = Data("MZ".utf8)
        file.append(Data(count: 0x3C - file.count))
        file.appendUInt32(0x40)
        file.append(Data("PE".utf8) + Data([0, 0]))
        file.appendUInt16(0x8664)
        file.appendUInt16(1)
        file.append(Data(count: 12))
        file.appendUInt16(0)
        file.appendUInt16(0x22)
        let section = resourceSection()
        file.append(Data(".rsrc".utf8) + Data(count: 3))
        file.appendUInt32(UInt32(section.count))
        file.appendUInt32(Self.virtualAddress)
        file.appendUInt32(UInt32(section.count))
        file.appendUInt32(UInt32(Self.rawOffset))
        file.append(Data(count: 16))
        file.append(Data(count: Self.rawOffset - file.count))
        return file + section
    }

    private func resourceSection() -> Data {
        var types: [(UInt32, UInt32)] = []
        if let otherResourceType {
            types.append((otherResourceType, 0x8000_0000 | 0x30))
        }
        if includesVersion {
            types.append((16, 0x8000_0000 | 0x30))
        }
        var section = directory(types)
        section.append(Data(count: 0x30 - section.count))
        section += directory([(1, 0x8000_0000 | 0x48)])
        section += directory([(1033, 0x60)])
        let info = versionInfo()
        section.appendUInt32(Self.virtualAddress + 0x70)
        section.appendUInt32(UInt32(info.count))
        section.append(Data(count: 8))
        section.append(Data(count: 0x70 - section.count))
        return section + info
    }

    private func directory(_ entries: [(UInt32, UInt32)]) -> Data {
        var data = Data(count: 12)
        data.appendUInt16(0)
        data.appendUInt16(UInt16(entries.count))
        for (id, target) in entries {
            data.appendUInt32(id)
            data.appendUInt32(target)
        }
        return data
    }

    private func versionInfo() -> Data {
        var info = Data()
        info.appendUInt16(0)
        info.appendUInt16(52)
        info.appendUInt16(0)
        for unit in "VS_VERSION_INFO".utf16 {
            info.appendUInt16(unit)
        }
        info.appendUInt16(0)
        info.append(Data(count: 2))
        info.appendUInt32(signature)
        info.appendUInt32(0x0001_0000)
        info.appendUInt32(UInt32(version[0]) << 16 | UInt32(version[1]))
        info.appendUInt32(UInt32(version[2]) << 16 | UInt32(version[3]))
        info.append(Data(count: 36))
        return info
    }
}
