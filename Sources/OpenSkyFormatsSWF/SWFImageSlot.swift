// Engine pictures a movie loads by an `img://` URL, such as a save's screenshot.
// A slot is a blank bitmap plus a rectangle shape filled with it; the renderer
// writes the pixels later. See docs/rendering/swf-layer.md.

import Foundation

nonisolated public struct SWFImageSlot: Equatable, Sendable {
    public let bitmapId: UInt16
    public let shapeId: UInt16
    public let width: Int
    public let height: Int
}

nonisolated extension SWFMovieScene {
    /// The scene with one more image slot. Unchanged when the name is taken, the size
    /// is empty, or the character ids run out.
    public func addingImageSlot(_ name: String, width: Int, height: Int) -> SWFMovieScene {
        var movie = movie
        let next = Int(movie.characters.keys.max() ?? 0) + 1
        guard
            movie.imageSlots[name] == nil, width > 0, height > 0,
            width * height <= SWFBitmapDecoder.maxPixelCount, next + 1 <= Int(UInt16.max)
        else { return self }
        let slot = SWFImageSlot(
            bitmapId: UInt16(next), shapeId: UInt16(next + 1), width: width, height: height
        )
        movie.characters[slot.bitmapId] = .bitmap(SWFBitmap(
            characterId: slot.bitmapId, width: width, height: height,
            pixels: Data(count: width * height * 4), premultipliedAlpha: false,
            sourceFormat: .lossless32, jpegDeblockParam: nil
        ))
        movie.characters[slot.shapeId] = .shape(Self.pictureShape(slot))
        movie.imageSlots[name] = slot
        return SWFMovieScene(
            movie: movie, externalFonts: externalFonts, unresolvedFontNames: unresolvedFontNames
        )
    }

    /// One bitmap pixel per screen pixel: shapes are in twips, 20 to a pixel.
    private static func pictureShape(_ slot: SWFImageSlot) -> SWFShapeDefinition {
        let right = Int32(slot.width * 20)
        let bottom = Int32(slot.height * 20)
        let corners: [(Int32, Int32)] = [(0, 0), (right, 0), (right, bottom), (0, bottom), (0, 0)]
        let segments = zip(corners, corners.dropFirst()).map { from, to in
            SWFShapeSegment(
                fromX: from.0, fromY: from.1, edge: .line(toX: to.0, toY: to.1),
                fillStyle0: 0, fillStyle1: 1, lineStyle: 0
            )
        }
        return SWFShapeDefinition(
            characterId: slot.shapeId,
            bounds: SWFRect(xMin: 0, xMax: right, yMin: 0, yMax: bottom),
            edgeBounds: nil,
            usesFillWindingRule: false,
            fillStyles: [.bitmap(
                characterId: slot.bitmapId, matrix: SWFMatrix(scaleX: 20, scaleY: 20),
                tiled: false, smoothed: true
            )],
            lineStyles: [],
            segments: segments
        )
    }
}
