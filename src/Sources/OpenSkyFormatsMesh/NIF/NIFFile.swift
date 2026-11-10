// NIF container walk: slices each block by the header's size array and reads
// the footer roots. It decodes no block, so unknown block types can always be
// skipped. Layout: docs/formats/nif.md.

public import Foundation
import OpenSkyFormatsCore

/// One block: type name from the header table + raw payload bytes.
nonisolated public struct NIFBlock: Sendable {
    public let typeName: String
    public let data: Data
}

nonisolated public struct NIFFile: Sendable {
    public let header: NIFHeader
    /// Every block in file order, header's size array as the slice widths.
    public let blocks: [NIFBlock]
    /// Footer root refs: block indices; -1 = null ref. Not validated here —
    /// ref resolution is the scene-graph layer's job.
    public let roots: [Int32]

    public init(data: Data) throws {
        var reader = BinaryReader(data)
        header = try NIFHeader(reader: &reader)

        var blocks: [NIFBlock] = []
        for index in 0 ..< header.blockCount {
            let size = header.blockSizes[index]
            let typeName = header.blockTypes[header.blockTypeIndices[index]]
            guard size >= 0, let payload = attempt({ try reader.read(count: size) }) else {
                throw NIFError.malformed(
                    "block \(index) (\(typeName), \(size) bytes) extends past end of file"
                )
            }
            blocks.append(NIFBlock(typeName: typeName, data: payload))
        }
        self.blocks = blocks

        do {
            let rootCount = try Int(reader.readUInt32())
            var roots: [Int32] = []
            for _ in 0 ..< rootCount {
                try roots.append(Int32(bitPattern: reader.readUInt32()))
            }
            self.roots = roots
        } catch {
            throw NIFError.malformed("truncated footer")
        }
    }

    /// Block-type histogram, for probes and coverage decisions.
    public func blockTypeCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for block in blocks {
            counts[block.typeName, default: 0] += 1
        }
        return counts
    }
}
