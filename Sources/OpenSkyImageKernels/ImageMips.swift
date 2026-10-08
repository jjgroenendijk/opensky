// Box-filtered mip chains for pictures painted on the CPU.

nonisolated public enum ImageMips {
    /// The full chain down to 1 x 1, starting with `image` itself.
    public static func chain(_ image: DecodedImage) -> [DecodedImage] {
        var levels = [image]
        while let last = levels.last, last.width > 1 || last.height > 1 {
            levels.append(halved(last))
        }
        return levels
    }

    private static func halved(_ image: DecodedImage) -> DecodedImage {
        let width = max(1, image.width / 2)
        let height = max(1, image.height / 2)
        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        for row in 0 ..< height {
            for column in 0 ..< width {
                for channel in 0 ..< 4 {
                    var sum = 0
                    for (dy, dx) in [(0, 0), (0, 1), (1, 0), (1, 1)] {
                        let sourceRow = min(row * 2 + dy, image.height - 1)
                        let sourceColumn = min(column * 2 + dx, image.width - 1)
                        sum +=
                            Int(image.rgba[(sourceRow * image.width + sourceColumn) * 4 + channel])
                    }
                    rgba[(row * width + column) * 4 + channel] = UInt8(sum / 4)
                }
            }
        }
        return DecodedImage(width: width, height: height, rgba: rgba)
    }
}
