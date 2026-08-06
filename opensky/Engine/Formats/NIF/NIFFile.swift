// NIF container walk: slices every block's payload by the header's recorded
// size and reads the footer roots. No block content is decoded here — that
// keeps unknown/unneeded block types skippable by construction; typed
// decoders (2.3 scene graph, 2.4 materials) consume `Block.data` later.
//
// Reference: NifTools nif.xml (struct Footer; header block-size array).
//   https://github.com/niftools/nifxml/blob/develop/nif.xml
// Layout documented in docs/formats/nif.md.

import Foundation

nonisolated struct NIFFile {
    /// One block: type name from the header table + raw payload bytes.
    struct Block {
        let typeName: String
        let data: Data
    }

    let header: NIFHeader
    /// Every block in file order, header's size array as the slice widths.
    let blocks: [Block]
    /// Footer root refs: block indices; -1 = null ref. Not validated here —
    /// ref resolution is the scene-graph layer's job.
    let roots: [Int32]

    init(data: Data) throws {
        var reader = BinaryReader(data)
        header = try NIFHeader(reader: &reader)

        var blocks: [Block] = []
        for index in 0 ..< header.blockCount {
            let size = header.blockSizes[index]
            let typeName = header.blockTypes[header.blockTypeIndices[index]]
            guard size >= 0, let payload = try? reader.read(count: size) else {
                throw NIFError.malformed(
                    "block \(index) (\(typeName), \(size) bytes) extends past end of file"
                )
            }
            blocks.append(Block(typeName: typeName, data: payload))
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
    func blockTypeCounts() -> [String: Int] {
        var counts: [String: Int] = [:]
        for block in blocks {
            counts[block.typeName, default: 0] += 1
        }
        return counts
    }
}
