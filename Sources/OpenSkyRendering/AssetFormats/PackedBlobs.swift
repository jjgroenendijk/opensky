// Several byte blobs stored back to back in one file, with their ranges kept
// beside it. The ready forms of meshes, collision, and animation use it.

import Foundation

nonisolated public enum PackedBlobsError: Error, Equatable, Sendable {
    case sourceTooShort(expected: Int, actual: Int)
}

nonisolated public struct PackedBlobs: Equatable, Sendable {
    public struct Range: Equatable, Sendable {
        public let offset: Int
        public let length: Int
    }

    public let ranges: [Range]
    public let bytes: Data

    public init(_ blobs: [Data]) {
        var ranges: [Range] = []
        var bytes = Data()
        for blob in blobs {
            ranges.append(Range(offset: bytes.count, length: blob.count))
            bytes.append(blob)
        }
        self.ranges = ranges
        self.bytes = bytes
    }

    /// Splits `source`, laid out like `bytes`, back into its blobs.
    public func blobs(from source: Data) throws -> [Data] {
        guard source.count >= bytes.count else {
            throw PackedBlobsError.sourceTooShort(expected: bytes.count, actual: source.count)
        }
        return ranges.map { range in
            let start = source.startIndex + range.offset
            return source.subdata(in: start ..< start + range.length)
        }
    }

    /// The raw memory of an array of plain values.
    public static func blob(_ values: [some Any]) -> Data {
        values.withUnsafeBytes { Data($0) }
    }

    /// Plain values back from a blob made by `blob(_:)`.
    public static func values<Element>(_ blob: Data, as _: Element.Type) -> [Element] {
        blob.withUnsafeBytes { raw in
            Array(raw.bindMemory(to: Element.self))
        }
    }
}
