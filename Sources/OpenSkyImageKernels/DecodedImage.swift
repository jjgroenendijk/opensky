// Pixel kernels the engine runs on the CPU: block decode, tint paint, and mip
// halving. The module builds optimized in Debug too, because unoptimized pixel
// loops are about 100 times slower. See docs/tools/modules.md.

/// Top mip level as straight RGBA8, row-major from the top-left texel.
nonisolated public struct DecodedImage: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public var rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}
