// `NiStringExtraData`: a named string attached to a block. Prop meshes name
// their parent bone in one called `Prn`. Layout: docs/formats/nif.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct NIFStringExtraData: Equatable, Sendable {
    public static let typeName = "NiStringExtraData"
    /// The extra data that names the bone a prop or weapon rides.
    public static let parentBoneName = "Prn"

    public let name: String?
    public let value: String?

    /// Two string-table indices: the name, then the value. -1 is none.
    public init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        name = try Self.string(reader.readUInt32(), header)
        value = try Self.string(reader.readUInt32(), header)
    }

    /// Every string extra data block in the file, in block order. A short
    /// block is skipped.
    public static func all(in file: NIFFile) -> [NIFStringExtraData] {
        file.blocks.filter { $0.typeName == typeName }
            .compactMap { try? NIFStringExtraData(data: $0.data, header: file.header) }
    }

    /// The `Prn` value, or nil when the file names no parent bone.
    public static func parentBone(in file: NIFFile) -> String? {
        all(in: file).first { $0.name == parentBoneName }?.value
    }

    private static func string(_ index: UInt32, _ header: NIFHeader) -> String? {
        index != .max && Int(index) < header.strings.count ? header.strings[Int(index)] : nil
    }
}
