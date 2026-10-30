// One decoded movie picture as three 8-bit planes, YCbCr 4:2:0, the layout Bink
// video decodes to. The renderer turns it into colour on the GPU.

import Foundation

nonisolated public struct MoviePicture: Equatable, Sendable {
    public let width: Int
    public let height: Int
    /// `width` x `height` bytes, rows packed.
    public let luma: Data
    /// Each `chromaWidth` x `chromaHeight` bytes, rows packed.
    public let chromaBlue: Data
    public let chromaRed: Data
    /// True for 0 to 255 levels, false for 16 to 235 studio levels.
    public let isFullRange: Bool

    public var chromaWidth: Int {
        (width + 1) / 2
    }

    public var chromaHeight: Int {
        (height + 1) / 2
    }

    public init(
        width: Int, height: Int, luma: Data, chromaBlue: Data, chromaRed: Data,
        isFullRange: Bool
    ) {
        self.width = width
        self.height = height
        self.luma = luma
        self.chromaBlue = chromaBlue
        self.chromaRed = chromaRed
        self.isFullRange = isFullRange
    }

    /// The plane sizes match the picture size, so an upload cannot read past a plane.
    public var hasValidPlanes: Bool {
        width > 0 && height > 0 && luma.count == width * height
            && chromaBlue.count == chromaWidth * chromaHeight
            && chromaRed.count == chromaWidth * chromaHeight
    }
}
