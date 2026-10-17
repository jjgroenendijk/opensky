// Which texture variants the install's DDS files use, and which `DDSFile` does not
// read. Names and counts only.

import Foundation
import OpenSkyFormatsCore

nonisolated public struct DDSGapCensus: Sendable {
    /// Variant, such as "bc7 cubemap" or "unsupported: texture array of 6" -> files.
    public private(set) var variants = GapCounts()

    public init() {}

    /// A variant is done when `DDSFile` reads it.
    public static func isRead(_ variant: String) -> Bool {
        !variant.hasPrefix(unsupportedPrefix) && !variant.hasPrefix(malformedPrefix)
    }

    public mutating func record(data: Data) {
        variants.add(Self.variant(of: data))
    }

    static let unsupportedPrefix = "unsupported: "
    static let malformedPrefix = "malformed: "

    static func variant(of data: Data) -> String {
        do {
            let file = try DDSFile(data: data, allowsCubemap: true, allowsVolume: true)
            let shape = file.faceCount == 6 ? " cubemap" : file.depth > 1 ? " volume" : ""
            return "\(file.format)" + shape
        } catch let DDSError.unsupported(reason) {
            return unsupportedPrefix + reason
        } catch let DDSError.malformed(reason) {
            return malformedPrefix + GapCounts.failureKind(reason)
        } catch {
            return malformedPrefix + GapCounts.failureKind(String(describing: error))
        }
    }
}
