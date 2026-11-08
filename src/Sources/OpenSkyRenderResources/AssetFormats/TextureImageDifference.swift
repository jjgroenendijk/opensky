// How far a converted texture is from its source, measured on 8-bit RGBA
// pixels in the stored (not linearized) values.

import Foundation
import simd

/// One mip level as 8-bit RGBA, four bytes per pixel, rows packed.
nonisolated public struct TexturePixels: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let rgba: [UInt8]

    public init(width: Int, height: Int, rgba: [UInt8]) {
        self.width = width
        self.height = height
        self.rgba = rgba
    }
}

nonisolated public enum TextureImageDifferenceError: Error, Equatable, Sendable {
    case sizeMismatch(reference: [Int], candidate: [Int])
}

nonisolated public struct TextureImageDifference: Codable, Equatable, Sendable {
    /// The PSNR reported for identical pixels, so the value stays a finite JSON number.
    public static let losslessPSNR = 100.0

    /// Peak signal-to-noise ratio over R, G, and B, in dB. Higher is closer.
    public let rgbPSNR: Double
    public let alphaPSNR: Double
    /// The largest difference of one channel of one pixel, 0 to 255.
    public let maxChannelError: Int
    /// Mean angle between source and candidate normals, for tangent-space normal maps.
    public let meanNormalAngleDegrees: Double?

    public init(
        rgbPSNR: Double,
        alphaPSNR: Double,
        maxChannelError: Int,
        meanNormalAngleDegrees: Double? = nil
    ) {
        self.rgbPSNR = rgbPSNR
        self.alphaPSNR = alphaPSNR
        self.maxChannelError = maxChannelError
        self.meanNormalAngleDegrees = meanNormalAngleDegrees
    }

    /// Compares two same-size images. `normals` decodes RGB as `rgb * 2 - 1` vectors.
    public static func compare(
        reference: TexturePixels,
        candidate: TexturePixels,
        normals: Bool
    ) throws -> Self {
        guard
            reference.width == candidate.width, reference.height == candidate.height,
            reference.rgba.count == candidate.rgba.count
        else {
            throw TextureImageDifferenceError.sizeMismatch(
                reference: [reference.width, reference.height],
                candidate: [candidate.width, candidate.height]
            )
        }
        var sums = ErrorSums()
        let lhs = reference.rgba
        let rhs = candidate.rgba
        for pixel in stride(from: 0, to: lhs.count, by: 4) {
            sums.add(lhs[pixel ..< pixel + 4], rhs[pixel ..< pixel + 4], normals: normals)
        }
        let pixels = max(1, lhs.count / 4)
        return Self(
            rgbPSNR: psnr(squaredError: sums.rgb, samples: pixels * 3),
            alphaPSNR: psnr(squaredError: sums.alpha, samples: pixels),
            maxChannelError: sums.maxError,
            meanNormalAngleDegrees: normals ? sums.angleDegrees / Double(pixels) : nil
        )
    }

    static func psnr(squaredError: Double, samples: Int) -> Double {
        guard squaredError > 0, samples > 0 else { return losslessPSNR }
        let mse = squaredError / Double(samples)
        return min(losslessPSNR, 10 * log10(255 * 255 / mse))
    }
}

nonisolated private struct ErrorSums {
    var rgb = 0.0
    var alpha = 0.0
    var maxError = 0
    var angleDegrees = 0.0

    mutating func add(_ lhs: ArraySlice<UInt8>, _ rhs: ArraySlice<UInt8>, normals: Bool) {
        for channel in 0 ..< 4 {
            let error = Int(lhs[lhs.startIndex + channel]) - Int(rhs[rhs.startIndex + channel])
            maxError = max(maxError, abs(error))
            if channel == 3 {
                alpha += Double(error * error)
            } else {
                rgb += Double(error * error)
            }
        }
        if normals {
            let cosine = simd_dot(Self.normal(lhs), Self.normal(rhs))
            angleDegrees += acos(min(1, max(-1, cosine))) * 180 / .pi
        }
    }

    private static func normal(_ pixel: ArraySlice<UInt8>) -> SIMD3<Double> {
        let base = pixel.startIndex
        let vector = SIMD3<Double>(
            Double(pixel[base]), Double(pixel[base + 1]), Double(pixel[base + 2])
        ) / 255 * 2 - 1
        let length = simd_length(vector)
        return length > 0 ? vector / length : SIMD3(0, 0, 1)
    }
}
