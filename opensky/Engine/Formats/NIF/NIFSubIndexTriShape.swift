// BSSubIndexTriShape: SSE BSTriShape plus triangle segment metadata used by
// object LOD .bto files. Segment fields follow NifTools nif.xml
// (BSSubIndexTriShape, BSGeometrySegmentData, BS stream 100).

import Foundation

nonisolated struct NIFSubIndexTriShape {
    struct Segment: Equatable {
        let flags: UInt8
        /// First index in BSTriShape's flat triangle-index array.
        let startIndex: UInt32
        let primitiveCount: UInt32
    }

    let shape: NIFTriShape
    let segments: [Segment]

    init(data: Data, header: NIFHeader) throws {
        guard header.bsStream?.version == 100 else {
            throw NIFError.unsupported("BSSubIndexTriShape outside an SSE stream (BS 100)")
        }
        var reader = BinaryReader(data)
        shape = try NIFTriShape(reader: &reader, header: header)
        let count = try Int(reader.readUInt32())
        guard count <= reader.bytesRemaining / 9 else {
            throw NIFError.malformed("segment count \(count) exceeds block size")
        }
        var segments: [Segment] = []
        segments.reserveCapacity(count)
        for _ in 0 ..< count {
            let segment = try Segment(
                flags: reader.readUInt8(),
                startIndex: reader.readUInt32(),
                primitiveCount: reader.readUInt32()
            )
            let end = UInt64(segment.startIndex) + UInt64(segment.primitiveCount) * 3
            guard end <= UInt64(shape.indices.count) else {
                throw NIFError.malformed(
                    "segment range \(segment.startIndex)..<\(end) exceeds "
                        + "\(shape.indices.count) indices"
                )
            }
            segments.append(segment)
        }
        self.segments = segments
    }
}
