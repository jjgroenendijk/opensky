// Which SWF tags the interface movies hold, nested sprites included, and which ones a
// decoder reads. GFx extension names follow JPEXS Free Flash Decompiler's GFx tag
// classes. Names and counts only.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct SWFTagCensus: Sendable {
    /// "code name" -> tags.
    public private(set) var tags = GapCounts()
    /// Failure kind -> movies.
    public private(set) var failures = GapCounts()
    public private(set) var movieCount = 0

    public init() {}

    /// Tags `SWFMovieDecoder`, the timeline, or the font library read. End closes a
    /// stream, and the font companion tags hold hinting the glyph path does not need.
    public static let handledCodes: Set<UInt16> = SWFShapeDefinition.tagCodes
        .union(SWFBitmapDecoder.tagCodes)
        .union(SWFFontDefinition.tagCodes)
        .union(SWFTextDefinition.tagCodes)
        .union(SWFImportedAssets.tagCodes)
        .union([
            0, SWFBitmapDecoder.jpegTablesTagCode, SWFEditText.tagCode,
            SWFExportedAssets.tagCode, SWFFrameLabel.tagCode, SWFActionParser.doActionCode,
            SWFActionParser.doInitActionCode, SWFDisplayListParser.defineSpriteCode,
            SWFDisplayListParser.placeObjectCode, SWFDisplayListParser.placeObject2Code,
            SWFDisplayListParser.placeObject3Code, SWFDisplayListParser.removeObjectCode,
            SWFDisplayListParser.removeObject2Code, SWFDisplayListParser.setBackgroundColorCode,
            SWFDisplayListParser.showFrameCode, SWFButton.tagCode, SWFScalingGrid.tagCode,
            SWFFileAttributes.tagCode, SWFMetadata.tagCode, 73, 74, 88
        ])

    public static func isHandled(_ row: String) -> Bool {
        row.split(separator: " ").first.flatMap { UInt16($0) }.map(handledCodes.contains) ?? false
    }

    public mutating func record(data: Data) {
        movieCount += 1
        do {
            try record(tags: SWFFile(data: data).tags)
        } catch {
            failures.add("movie does not open: " + GapCounts.failureKind("\(error)"))
        }
    }

    private mutating func record(tags list: [SWFTag]) throws {
        for tag in list {
            tags.add("\(tag.code) " + Self.name(tag.code))
            guard tag.code == SWFDisplayListParser.defineSpriteCode else { continue }
            var reader = BinaryReader(tag.body)
            reader.skip(4)
            try record(tags: SWFFile.parseTags(&reader))
        }
    }

    static func name(_ code: UInt16) -> String {
        SWFTagName.name(forCode: code) ?? gfxNames[code] ?? "unknown"
    }

    private static let gfxNames: [UInt16: String] = [
        1000: "ExporterInfo", 1001: "DefineExternalImage", 1002: "FontTextureInfo",
        1003: "DefineExternalGradient", 1004: "DefineGradientMap", 1005: "DefineCompactedFont",
        1006: "DefineExternalSound", 1007: "DefineExternalStreamSound", 1008: "DefineSubImage",
        1009: "DefineExternalImage2"
    ]
}
