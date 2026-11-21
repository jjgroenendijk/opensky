// The colour ramp of one gradient fill: the GRADRECORD stops spread over 256 texels, padded
// at the ends. `linearRGB` mixes the stops in linear light, as Flash does. See
// docs/formats/swf-shapes.md#gradients.

import Foundation

nonisolated extension SWFGradient {
    /// `width` colours from ratio 0 to ratio 255.
    public func rampColors(width: Int = 256) -> [SWFColor] {
        let stops = records.sorted { $0.ratio < $1.ratio }
        let linear = interpolationMode == .linearRGB
        return (0 ..< width).map { texel in
            let ratio = width > 1 ? Float(texel) / Float(width - 1) * 255 : 0
            return Self.color(stops: stops, ratio: ratio, linear: linear)
        }
    }

    private static func color(stops: [SWFGradientRecord], ratio: Float, linear: Bool) -> SWFColor {
        guard let first = stops.first else {
            return SWFColor(red: 0, green: 0, blue: 0, alpha: 0)
        }
        var previous = first
        for stop in stops {
            if ratio <= Float(stop.ratio) {
                let span = Float(stop.ratio) - Float(previous.ratio)
                guard span > 0 else { return stop.color }
                let fraction = (ratio - Float(previous.ratio)) / span
                return mix(previous.color, stop.color, fraction: fraction, linear: linear)
            }
            previous = stop
        }
        return previous.color
    }

    /// Alpha always mixes straight; only the colour channels go through linear light.
    static func mix(_ from: SWFColor, _ to: SWFColor, fraction: Float, linear: Bool) -> SWFColor {
        func channel(_ start: UInt8, _ end: UInt8, linearLight: Bool) -> UInt8 {
            let low = Float(start) / 255, high = Float(end) / 255
            let mixed = linearLight
                ? encode(decode(low) + (decode(high) - decode(low)) * fraction)
                : low + (high - low) * fraction
            return UInt8(max(0, min(255, (mixed * 255).rounded())))
        }
        return SWFColor(
            red: channel(from.red, to.red, linearLight: linear),
            green: channel(from.green, to.green, linearLight: linear),
            blue: channel(from.blue, to.blue, linearLight: linear),
            alpha: channel(from.alpha, to.alpha, linearLight: false)
        )
    }

    /// The sRGB transfer curve, IEC 61966-2-1.
    static func decode(_ value: Float) -> Float {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }

    static func encode(_ value: Float) -> Float {
        value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1 / 2.4) - 0.055
    }
}
