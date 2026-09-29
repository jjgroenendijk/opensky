// The payload and class-name table that HKXFixture.build() lays out. Tests read
// them to predict offsets. See HKXFixture.swift.

import FormatsCoreTesting
import Foundation

extension HKXFixture {
    /// Deterministic payload pattern so slice tests can assert exact bytes,
    /// or the caller's exact override.
    public var payloadBytes: Data {
        payloadOverride ?? Data((0 ..< dataPayloadSize).map { UInt8($0 & 0xFF) })
    }

    /// Class-name blob + each entry's section-local name-string offset
    /// (entry start + 5, matching HKXFile's `nameOffset` rule).
    public func classNameLayout() -> (blob: Data, nameOffsets: [Int]) {
        var blob = Data()
        var nameOffsets: [Int] = []
        for (index, entry) in classNames.enumerated() {
            nameOffsets.append(blob.count + 5)
            blob.appendUInt32(entry.signature)
            let separator: UInt8 = (badClassNameSeparator && index == 1) ? 0x00 : 0x09
            blob.append(separator)
            blob.append(Data(entry.name.utf8))
            blob.append(0) // zstring terminator
        }
        blob.appendUInt32(0xFFFF_FFFF) // sentinel ends the table
        while blob.count % 16 != 0 {
            blob.append(0xFF)
        } // 0xFF tail padding
        return (blob, nameOffsets)
    }

    public var classNamesBlob: Data {
        classNameLayout().blob
    }

    public func nameOffset(ofClass index: Int) -> Int {
        classNameLayout().nameOffsets[index]
    }

    public var rootNameOffset: Int {
        nameOffset(ofClass: rootClassIndex)
    }
}
