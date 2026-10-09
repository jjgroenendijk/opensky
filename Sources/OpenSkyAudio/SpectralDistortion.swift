// Objective stand-in for a listening check of a lossy copy: band spectral
// distortion against the original, judged by the Paliwal-Atal transparency
// rule. See docs/engine/asset-cache-audio.md.

import Accelerate
import Foundation

nonisolated public struct SpectralDistortion: Equatable, Sendable {
    /// Mean over the measured frames, in dB.
    public let meanDB: Double
    public let over2DBShare: Double
    public let over4DBShare: Double
    public let frames: Int
    /// The shift of the candidate that correlates best with the reference. Not
    /// applied: the decoder trims the AAC priming, and periodic sounds give
    /// false peaks. A non-zero value on a noise-like sound flags a timing fault.
    public let bestLag: Int

    /// Paliwal and Atal (1993): mean under 1 dB, under 2 % of frames from 2 to
    /// 4 dB, and no frame over 4 dB. A sound with no loud frame passes.
    public var isTransparent: Bool {
        frames == 0 || (meanDB < 1 && over2DBShare - over4DBShare < 0.02 && over4DBShare == 0)
    }
}

nonisolated public enum SpectralDistortionMeter {
    static let frameLength = 1024
    static let hop = 512
    /// Frames of the reference quieter than this RMS level (dBFS) are not measured.
    static let silenceDB: Float = -50
    /// A band this far below the loudest band of its frame is masked; it is
    /// clamped to that floor in both signals.
    static let maskDepthDB: Float = 60
    /// Bark critical band edges in Hz (Zwicker 1961).
    static let barkEdges: [Float] = [
        0, 100, 200, 300, 400, 510, 630, 770, 920, 1080, 1270, 1480, 1720, 2000, 2320, 2700,
        3150, 3700, 4400, 5300, 6400, 7700, 9500, 12000, 15500
    ]
    /// AAC encoder delay is 2112 samples at most, so the lag search covers it.
    static let maximumLag = 2112

    public static func measure(
        reference: DecodedAudio, candidate: DecodedAudio
    ) -> SpectralDistortion {
        let analyzer = SpectrumAnalyzer(length: frameLength)
        let original = mono(reference)
        let lossy = mono(candidate)
        let aligned = padded(lossy, to: original.count)
        let bands = bandBins(sampleRate: reference.sampleRate)
        var distortions: [Double] = []
        var start = 0
        while start + frameLength <= original.count {
            let window = original[start ..< start + frameLength]
            if rmsDB(window) >= silenceDB {
                let referenceBands = bandEnergies(window, bands: bands, analyzer: analyzer)
                let candidateBands = bandEnergies(
                    aligned[start ..< start + frameLength], bands: bands, analyzer: analyzer
                )
                distortions.append(frameDistortion(referenceBands, candidateBands))
            }
            start += hop
        }
        let count = Double(max(1, distortions.count))
        return SpectralDistortion(
            meanDB: distortions.reduce(0, +) / count,
            over2DBShare: Double(distortions.count { $0 > 2 }) / count,
            over4DBShare: Double(distortions.count { $0 > 4 }) / count,
            frames: distortions.count,
            bestLag: bestLag(original, lossy)
        )
    }

    static func mono(_ audio: DecodedAudio) -> [Float] {
        let channels = max(1, audio.channelCount)
        return (0 ..< audio.frameCount).map { frame in
            var sum: Float = 0
            for channel in 0 ..< channels {
                sum += audio.samples[frame * channels + channel]
            }
            return sum / Float(channels)
        }
    }

    /// The shift of `candidate` that best correlates with `reference` over its
    /// first second. Lag 0 wins a tie, so silence reports 0.
    static func bestLag(_ reference: [Float], _ candidate: [Float]) -> Int {
        let span = min(reference.count, 44100)
        var best = (lag: 0, score: correlation(reference, candidate, lag: 0, span: span))
        for lag in -maximumLag ... maximumLag where lag != 0 {
            let score = correlation(reference, candidate, lag: lag, span: span)
            if score > best.score {
                best = (lag, score)
            }
        }
        return best.lag
    }

    private static func correlation(
        _ reference: [Float], _ candidate: [Float], lag: Int, span: Int
    ) -> Float {
        let first = max(0, -lag)
        let end = min(span, candidate.count - lag)
        guard first < end else { return 0 }
        return vDSP.dot(reference[first ..< end], candidate[(first + lag) ..< (end + lag)])
    }

    private static func padded(_ samples: [Float], to count: Int) -> [Float] {
        (0 ..< count).map { $0 < samples.count ? samples[$0] : 0 }
    }

    private static func rmsDB(_ window: ArraySlice<Float>) -> Float {
        let power = window.reduce(0) { $0 + $1 * $1 } / Float(window.count)
        return 10 * log10(max(power, 1e-12))
    }

    /// FFT bin ranges of the Bark bands below the Nyquist frequency.
    private static func bandBins(sampleRate: Int) -> [Range<Int>] {
        let binHz = Float(sampleRate) / Float(frameLength)
        let nyquist = Float(sampleRate) / 2
        return zip(barkEdges, barkEdges.dropFirst()).compactMap { low, high in
            guard high <= nyquist else { return nil }
            let first = max(1, Int((low / binHz).rounded(.up)))
            let end = Int((high / binHz).rounded(.up))
            return first < end ? first ..< end : nil
        }
    }

    private static func bandEnergies(
        _ window: ArraySlice<Float>, bands: [Range<Int>], analyzer: SpectrumAnalyzer
    ) -> [Float] {
        let power = analyzer.power(Array(window))
        return bands.map { band in band.reduce(0) { $0 + power[$1] } }
    }

    /// Root mean square of the per-band level differences, in dB.
    private static func frameDistortion(_ reference: [Float], _ candidate: [Float]) -> Double {
        let floor = max((reference.max() ?? 0) * pow(10, -maskDepthDB / 10), 1e-20)
        let squares = zip(reference, candidate).map { original, lossy in
            let difference = 10 * log10(max(original, floor) / max(lossy, floor))
            return Double(difference * difference)
        }
        return (squares.reduce(0, +) / Double(max(1, squares.count))).squareRoot()
    }
}

/// Hann-windowed power spectrum of one frame, with the FFT set up once.
nonisolated private struct SpectrumAnalyzer {
    let length: Int
    let window: [Float]
    let fft: vDSP.FFT<DSPSplitComplex>?

    init(length: Int) {
        self.length = length
        window = vDSP.window(
            ofType: Float.self, usingSequence: .hanningDenormalized, count: length,
            isHalfWindow: false
        )
        fft = vDSP.FFT(
            log2n: vDSP_Length(length.trailingZeroBitCount), radix: .radix2,
            ofType: DSPSplitComplex.self
        )
    }

    /// Squared magnitude of bins 0 ..< length / 2 (bin 0 holds DC and Nyquist packed).
    func power(_ samples: [Float]) -> [Float] {
        let half = length / 2
        let windowed = vDSP.multiply(samples, window)
        var real = [Float](repeating: 0, count: half)
        var imaginary = [Float](repeating: 0, count: half)
        var power = [Float](repeating: 0, count: half)
        guard let fft else { return power }
        real.withUnsafeMutableBufferPointer { realBuffer in
            imaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard
                    let realBase = realBuffer.baseAddress,
                    let imaginaryBase = imaginaryBuffer.baseAddress else { return }
                var split = DSPSplitComplex(realp: realBase, imagp: imaginaryBase)
                windowed.withUnsafeBytes { raw in
                    vDSP.convert(
                        interleavedComplexVector: Array(raw.bindMemory(to: DSPComplex.self)),
                        toSplitComplexVector: &split
                    )
                }
                fft.forward(input: split, output: &split)
                vDSP.squareMagnitudes(split, result: &power)
            }
        }
        return power
    }
}
