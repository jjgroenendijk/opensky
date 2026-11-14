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

// Which subtrees the particle walk drops: hidden objects and editor markers, as the mesh
// walk does. See docs/formats/nif-particles.md#from-scene-graph-to-particle-system.

/// Decides whether an object and its children are never drawn. One value serves one
/// file; it finds the animated names on the first hidden object only.
nonisolated struct NIFParticleVisibilityFilter {
    /// A `NiFloatExtraData` named with this prefix shows or hides the node it names.
    static let extraDataPrefix = "hkVis:"

    let file: NIFFile
    private var animatedNames: Set<String>?

    init(file: NIFFile) {
        self.file = file
    }

    /// True for an editor marker, and for a hidden object that nothing can show later.
    mutating func drops(_ object: NIFObjectPrefix) -> Bool {
        if object.isEditorMarker {
            return true
        }
        guard object.isHidden else { return false }
        if hasVisibilityController(from: object.controllerRef) {
            return false
        }
        guard let name = object.name else { return true }
        let names = animatedNames ?? namesWithAnimatedVisibility()
        animatedNames = names
        return !names.contains(name)
    }

    /// True when the controller chain from `ref` holds a `NiVisController`. The step limit
    /// stops a cyclic chain.
    private func hasVisibilityController(from ref: Int32) -> Bool {
        var current = ref
        var steps = 0
        while current >= 0, Int(current) < file.blocks.count, steps < 32 {
            let block = file.blocks[Int(current)]
            if block.typeName == NIFFile.ParticleControllerDecoder.visibilityControllerType {
                return true
            }
            var reader = BinaryReader(block.data)
            guard let base = attempt({ try NIFTimeController(reader: &reader) }) else {
                return false
            }
            current = base.nextControllerRef
            steps += 1
        }
        return false
    }

    /// The objects a sequence's visibility track names, and the ones a behaviour graph
    /// shows through an `hkVis:` extra data value.
    private func namesWithAnimatedVisibility() -> Set<String> {
        var names: Set<String> = []
        for sequence in attempt({ try file.sequences() }) ?? [] {
            for track in sequence.tracks {
                if case let .node(name) = track.target, case .visibility = track.channel {
                    names.insert(name)
                }
            }
        }
        let prefix = Self.extraDataPrefix
        for string in file.header.strings where string.hasPrefix(prefix) {
            names.insert(String(string.dropFirst(prefix.count)))
        }
        return names
    }
}
