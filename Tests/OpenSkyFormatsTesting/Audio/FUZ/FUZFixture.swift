// Synthetic `.fuz` builder for the voice-container tests. Lip bytes are
// counters; the audio comes from `XWMFixture`. Layout: docs/formats/fuz.md.

import Foundation

public enum FUZFixture: Sendable {
    public static let magic = "FUZE"
    public static let version: UInt32 = 1

    /// Lip bytes tagged by index so a test can assert the blob was sliced at
    /// the right boundary.
    public static func lip(byteCount: Int) -> Data {
        Data((0 ..< byteCount).map { UInt8(truncatingIfNeeded: $0) })
    }

    /// A `.fuz` file: header, `lipByteCount` bytes of lip blob, then `audio`.
    /// `declaredLipSize` overrides the header field so a test can claim more
    /// lip bytes than the buffer holds.
    public static func file(
        magic: String = magic,
        version: UInt32 = version,
        lipByteCount: Int = 16,
        declaredLipSize: UInt32? = nil,
        audio: Data = XWMFixture.file(packetCount: 2)
    ) -> Data {
        var out = Data(magic.utf8)
        out.appendUInt32(version)
        out.appendUInt32(declaredLipSize ?? UInt32(lipByteCount))
        out.append(lip(byteCount: lipByteCount))
        out.append(audio)
        return out
    }
}
