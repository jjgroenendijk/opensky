// `BSBehaviorGraphExtraData`: names the Havok behaviour project that animates an
// object mesh, such as a trap or a door. Layout: docs/formats/nif.md.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct NIFBehaviorGraphExtraData: Equatable, Sendable {
    public static let typeName = "BSBehaviorGraphExtraData"

    public let name: String?
    /// The project path, relative to `meshes\`, as the file spells it.
    public let graphFile: String?
    /// Whether the graph also drives the mesh's own skeleton root.
    public let controlsBaseSkeleton: Bool

    /// Two string-table indices (name, graph file), then one byte. -1 is none.
    public init(data: Data, header: NIFHeader) throws {
        var reader = BinaryReader(data)
        name = try Self.string(reader.readUInt32(), header)
        graphFile = try Self.string(reader.readUInt32(), header)
        controlsBaseSkeleton = try reader.readUInt8() != 0
    }

    /// The first behaviour graph block in the file, or nil. A short block is skipped.
    public static func first(in file: NIFFile) -> NIFBehaviorGraphExtraData? {
        file.blocks.lazy.filter { $0.typeName == typeName }
            .compactMap { try? NIFBehaviorGraphExtraData(data: $0.data, header: file.header) }
            .first
    }

    /// The project path normalised under `meshes\`, or nil when the file names none.
    public static func projectPath(in file: NIFFile) -> String? {
        guard let raw = first(in: file)?.graphFile, !raw.isEmpty else { return nil }
        let path = raw.replacingOccurrences(of: "/", with: "\\").lowercased()
        return path.hasPrefix("meshes\\") ? path : "meshes\\" + path
    }

    private static func string(_ index: UInt32, _ header: NIFHeader) -> String? {
        index != .max && Int(index) < header.strings.count ? header.strings[Int(index)] : nil
    }
}
