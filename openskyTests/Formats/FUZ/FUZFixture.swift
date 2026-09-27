// Synthetic `.fuz` byte builder for the voice-container framing tests.
// Fixtures are built in code — never extracted game audio (AGENTS.md "Legal &
// IP boundary"). The lip bytes are counter values, not lip-sync data, and the
// audio payload comes from `XWMFixture`.
//
// Layout follows xEdit dev-4.1.6 `dfFUZ` in Core/wbDataFormatMisc.pas; see
// docs/formats/fuz.md.

import Foundation
@testable import opensky

enum FUZFixture {
    static let magic = "FUZE"
    static let version: UInt32 = 1

    /// Lip bytes tagged by index so a test can assert the blob was sliced at
    /// the right boundary.
    static func lip(byteCount: Int) -> Data {
        Data((0 ..< byteCount).map { UInt8(truncatingIfNeeded: $0) })
    }

    /// A `.fuz` file: header, `lipByteCount` bytes of lip blob, then `audio`.
    /// `declaredLipSize` overrides the header field so a test can claim more
    /// lip bytes than the buffer holds.
    static func file(
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
