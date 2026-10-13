// Which sound file variants the install uses, by files, and which ones the engine
// cannot open or decode. A voice `.fuz` counts by the audio inside it; its lip data is
// handed back for the caller to check. Names and counts only.

import Foundation
import OpenSkyFormatsAudio
import OpenSkyFormatsCore

nonisolated public struct AudioGapCensus: Sendable {
    /// Variant, such as "xwm format 0x0161", or "fails: ..." -> files.
    public private(set) var variants = GapCounts()

    public init() {}

    public static func isRead(_ variant: String) -> Bool {
        !variant.hasPrefix(failurePrefix)
    }

    /// Records one `.wav`, `.xwm`, or `.fuz` file. Returns the lip data of a `.fuz`.
    @discardableResult
    public mutating func record(path: String, data: Data) -> Data? {
        let lower = path.lowercased()
        guard lower.hasSuffix(".fuz") else {
            variants.add(Self.variant(of: data, container: lower.hasSuffix(".wav") ? "wav" : "xwm"))
            return nil
        }
        do {
            let fuz = try FUZFile(data: data)
            variants.add(Self.variant(of: fuz.audioData, container: "fuz"))
            return fuz.lipData
        } catch {
            variants.add(Self.failure("fuz", error))
            return nil
        }
    }

    static let failurePrefix = "fails: "

    private static func variant(of data: Data, container: String) -> String {
        do {
            if WorldAudioEngine.isWAV(data) {
                let format = try WAVFile(data: data).format
                return "\(container) wav format \(hex(format.formatTag)) "
                    + "\(format.bitsPerSample)-bit"
            }
            let file = try XWMFile(data: data)
            _ = try WMADecoder(parameters: AudioCodecParameters(xwm: file.codec))
            return "\(container) xwm format \(hex(file.codec.formatTag))"
        } catch {
            return failure(container, error)
        }
    }

    private static func failure(_ container: String, _ error: any Error) -> String {
        failurePrefix + "\(container): " + GapCounts.failureKind(String(describing: error))
    }

    private static func hex(_ tag: UInt16) -> String {
        "0x" + String(tag, radix: 16, uppercase: true)
    }
}
