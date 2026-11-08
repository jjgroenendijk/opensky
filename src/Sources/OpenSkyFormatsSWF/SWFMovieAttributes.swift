// Movie-level tags with no display role: FileAttributes (69), Metadata (77), and
// DefineScalingGrid (78). Layout: docs/formats/swf.md, "Movie attributes".

import Foundation
import OpenSkyFormatsCore

/// A decoded FileAttributes (69) tag.
nonisolated public struct SWFFileAttributes: Equatable, Sendable {
    public static let tagCode: UInt16 = 69

    public var usesDirectBlit = false
    public var usesGPU = false
    public var hasMetadata = false
    /// The movie's code is ActionScript 3 (DoABC), which the AS2 runtime cannot run.
    public var isActionScript3 = false
    public var usesNetwork = false

    public init() {}

    public static func parse(tag: SWFTag) throws -> SWFFileAttributes {
        guard tag.code == tagCode else {
            throw SWFDisplayListError.unsupportedTag(tag.code)
        }
        var reader = BinaryReader(tag.body)
        let flags = try reader.readUInt8()
        var attributes = SWFFileAttributes()
        attributes.usesDirectBlit = flags & 0x40 != 0
        attributes.usesGPU = flags & 0x20 != 0
        attributes.hasMetadata = flags & 0x10 != 0
        attributes.isActionScript3 = flags & 0x08 != 0
        attributes.usesNetwork = flags & 0x01 != 0
        return attributes
    }
}

/// Metadata (77): one XML string, the authoring tool's RDF description.
nonisolated public enum SWFMetadata: Sendable {
    public static let tagCode: UInt16 = 77

    public static func parse(tag: SWFTag) throws -> String {
        guard tag.code == tagCode else {
            throw SWFDisplayListError.unsupportedTag(tag.code)
        }
        var reader = BinaryReader(tag.body)
        return try GameText.decode(reader.readZStringData())
    }
}

/// A decoded DefineScalingGrid (78) tag: the centre rectangle of a nine-slice
/// sprite, in the sprite's own twips.
nonisolated public struct SWFScalingGrid: Equatable, Sendable {
    public static let tagCode: UInt16 = 78

    public let characterId: UInt16
    public let splitter: SWFRect

    public init(characterId: UInt16, splitter: SWFRect) {
        self.characterId = characterId
        self.splitter = splitter
    }

    public static func parse(tag: SWFTag) throws -> SWFScalingGrid {
        guard tag.code == tagCode else {
            throw SWFDisplayListError.unsupportedTag(tag.code)
        }
        var bits = SWFBitReader(tag.body)
        let characterId = try bits.readAlignedUInt16()
        let splitter = try SWFShapeParser.parseRect(&bits)
        return SWFScalingGrid(characterId: characterId, splitter: splitter)
    }
}
