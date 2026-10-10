// `NiControllerSequence` blocks: which interpolators a controller manager's
// sequence feeds to each controller. Only the parts an emitter controller needs
// are kept. Layout: docs/formats/nif-particles.md#controller-manager-sequences.

import Foundation
import OpenSkyFormatsCore

/// One sequence's interpolators for one controller, by interpolator ID.
nonisolated struct SequenceFeed: Equatable {
    let sequenceName: String?
    let timing: ControllerTiming
    /// nif.xml `GetInterpolatorID()` -> interpolator block ref.
    var interpolators: [String: Int32] = [:]
}

nonisolated enum NIFControllerSequenceDecoder {
    static let sequenceType = "NiControllerSequence"

    /// The default sequence's feed for each controller, keyed by controller block index.
    /// Only the sequences that feed a controller compete for it.
    static func defaultFeeds(file: NIFFile) throws -> [Int32: SequenceFeed] {
        let sequences = try file.blocks.indices
            .filter { file.blocks[$0].typeName == sequenceType }
            .map { try sequence(file.blocks[$0], file: file) }
        var feeds: [Int32: SequenceFeed] = [:]
        for controller in Set(sequences.flatMap(\.feeds.keys)) {
            let candidates = sequences.filter { $0.feeds[controller] != nil }
            feeds[controller] = defaultSequence(candidates)?.feeds[controller]
        }
        return feeds
    }

    /// A mesh names no default, and the game starts sequences from animation events. So
    /// this is an OpenSky policy: an idle by name, else the first loop, else the first.
    static func defaultSequence(_ sequences: [DecodedSequence]) -> DecodedSequence? {
        sequences.first { $0.name?.lowercased().hasSuffix("idle") == true }
            ?? sequences.first { $0.cycle == .loop }
            ?? sequences.first
    }

    struct DecodedSequence: Equatable {
        let name: String?
        let cycle: ControllerCycle
        let feeds: [Int32: SequenceFeed]
    }

    /// nif.xml `NiSequence` then `NiControllerSequence` for 20.2.0.7: name,
    /// controlled blocks, weight, text keys, cycle, frequency, start, stop.
    private static func sequence(
        _ block: NIFFile.Block,
        file: NIFFile
    ) throws -> DecodedSequence {
        var reader = BinaryReader(block.data)
        let name = try string(&reader, file)
        let count = try Int(reader.readUInt32())
        reader.skip(4) // array grow by
        guard count <= reader.bytesRemaining / blockSize else {
            throw NIFError.malformed("sequence has \(count) controlled blocks, too many")
        }
        var interpolatorsByController: [Int32: [String: Int32]] = [:]
        for _ in 0 ..< count {
            let interpolator = try Int32(bitPattern: reader.readUInt32())
            let controller = try Int32(bitPattern: reader.readUInt32())
            reader.skip(1 + 4 * 4) // priority, node, property, controller type, controller ID
            guard let id = try string(&reader, file), controller >= 0, interpolator >= 0 else {
                continue
            }
            interpolatorsByController[controller, default: [:]][id] = interpolator
        }
        reader.skip(4 + 4) // weight, text keys
        let cycle = try reader.readUInt32()
        let timing = try ControllerTiming(
            cycle: ControllerCycle(rawValue: UInt16(truncatingIfNeeded: cycle)) ?? .clamp,
            frequency: reader.readFloat32(),
            phase: 0,
            startTime: reader.readFloat32(),
            stopTime: reader.readFloat32()
        )
        let feeds = interpolatorsByController.mapValues {
            SequenceFeed(sequenceName: name, timing: timing, interpolators: $0)
        }
        return DecodedSequence(name: name, cycle: timing.cycle, feeds: feeds)
    }

    /// Interpolator, controller, priority byte, five string indices.
    private static let blockSize = 4 + 4 + 1 + 5 * 4

    private static func string(_ reader: inout BinaryReader, _ file: NIFFile) throws -> String? {
        let index = try reader.readUInt32()
        return index != .max && Int(index) < file.header.strings.count
            ? file.header.strings[Int(index)] : nil
    }
}
