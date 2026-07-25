// `audio sweep`: frame every `.xwm` the install's archives provide through
// the production `XWMFile` parser, decode each one to PCM through `WMADecoder`
// (streaming packet by packet), and print a grep-able tally (milestones 9.1.2
// and 9.1.3, gated in tools/probe.sh alongside the lod/swf sweeps).
//
// The sweep streams: one file's bytes are read, framed, decoded chunk by chunk
// (each chunk's PCM is counted and dropped) and released before the next path
// is opened, so the walk stays flat in memory over the whole corpus.

import Foundation

enum AudioSweep {
    static func run(context: CLIContext) throws {
        let vfs = context.makeFileSystem()
        let paths = vfs.archiveEntries().map(\.path)
            .filter { $0.lowercased().hasSuffix(".xwm") }
        var tally = AudioSweepTally()
        for path in paths {
            do {
                let file = try XWMFile(data: vfs.contents(forPath: path))
                print("[INFO] \(path): \(AudioCommand.summaryLine(for: file))")
                tally.record(file, path: path)
                try decodeStreaming(file, path: path, into: &tally)
            } catch let XWMError.unsupported(reason) {
                print("[INFO] \(path): unsupported (\(reason)), accounted")
                tally.unsupported += 1
            } catch {
                tally.failures.append((path, String(describing: error)))
            }
        }
        for failure in tally.failures.prefix(20) {
            printError("[ERROR] \(failure.0): \(failure.1)")
        }
        tally.printReport(total: paths.count)
        guard tally.failures.isEmpty else {
            throw CLIError.failure(
                "audio sweep failed: \(tally.failures.count) files did not frame or decode"
            )
        }
    }

    /// Decodes one framed file packet-by-packet, counting frames only (no PCM
    /// is retained). A frame count differing from the `dpds` declaration is
    /// reported as a mismatch, not a failure; a decode throw is a failure.
    private static func decodeStreaming(
        _ file: XWMFile, path: String, into tally: inout AudioSweepTally
    ) throws {
        let decoder = try WMADecoder(parameters: AudioCodecParameters(xwm: file.codec))
        let channels = max(file.codec.channelCount, 1)
        var frames = 0
        for index in 0 ..< file.packetCount {
            guard let packet = file.packet(at: index) else { break }
            frames += try decoder.decode(packet: packet).count / channels
        }
        frames += try decoder.flush().count / channels
        tally.decoded += 1
        tally.totalDecodedFrames += frames
        if let declared = file.declaredSampleCount, declared != frames {
            tally.decodeFrameMismatches.append("\(path) (declared \(declared), got \(frames))")
        }
    }
}

/// Accumulates one `audio sweep` run. Counts and histograms only — no file
/// bytes are retained, which is what keeps the sweep's footprint flat.
struct AudioSweepTally {
    var framed = 0
    var decoded = 0
    var totalDecodedFrames = 0
    var decodeFrameMismatches: [String] = []
    var unsupported = 0
    var failures: [(String, String)] = []
    var formatTags: [UInt16: Int] = [:]
    var channelCounts: [Int: Int] = [:]
    var sampleRates: [Int: Int] = [:]
    var blockAligns: [Int: Int] = [:]
    var extraDataSizes: [Int: Int] = [:]
    var withoutPacketTable: [String] = []
    var inconsistentPacketTable: [String] = []
    var partialFinalPacket: [String] = []
    var totalPayloadBytes = 0
    var totalDuration = 0.0

    mutating func record(_ file: XWMFile, path: String) {
        framed += 1
        let codec = file.codec
        formatTags[codec.formatTag, default: 0] += 1
        channelCounts[codec.channelCount, default: 0] += 1
        sampleRates[codec.sampleRate, default: 0] += 1
        blockAligns[codec.blockAlign, default: 0] += 1
        extraDataSizes[codec.extraData.count, default: 0] += 1
        totalPayloadBytes += file.payloadByteCount
        totalDuration += file.declaredDuration ?? 0
        if file.packetCumulativeDecodedBytes.isEmpty {
            withoutPacketTable.append(path)
        } else if !file.isPacketTableConsistent {
            inconsistentPacketTable.append(path)
        }
        if file.payloadByteCount % codec.blockAlign != 0 {
            partialFinalPacket.append(path)
        }
    }

    func printReport(total: Int) {
        print(
            "[INFO] audio sweep: \(total) files, \(framed) framed, \(decoded) decoded, "
                + "\(unsupported) unsupported, \(failures.count) failed"
        )
        print(
            "[INFO] audio sweep decode: \(totalDecodedFrames) frames, "
                + "\(decodeFrameMismatches.count) frame-count mismatches"
        )
        for note in decodeFrameMismatches.prefix(10) {
            print("[INFO]   decode note: \(note)")
        }
        print(
            "[INFO] audio sweep format: "
                + histogram(formatTags.mapKeys { "0x" + String(format: "%04X", $0) })
                + "; channels " + histogram(channelCounts.mapKeys(String.init))
                + "; rates " + histogram(sampleRates.mapKeys(String.init))
                + "; block align " + histogram(blockAligns.mapKeys(String.init))
                + "; cbSize " + histogram(extraDataSizes.mapKeys(String.init))
        )
        print(
            "[INFO] audio sweep packets: \(withoutPacketTable.count) without dpds, "
                + "\(inconsistentPacketTable.count) dpds/packet mismatches, "
                + "\(partialFinalPacket.count) with a partial final packet"
        )
        print(
            "[INFO] audio sweep payload: \(totalPayloadBytes) bytes, "
                + String(format: "%.1f", totalDuration / 60) + " minutes declared"
        )
        for path in (inconsistentPacketTable + partialFinalPacket).prefix(10) {
            print("[INFO]   packet-table note: \(path)")
        }
    }

    private func histogram(_ counts: [String: Int]) -> String {
        counts.sorted { $0.key < $1.key }
            .map { "\($0.key) x\($0.value)" }
            .joined(separator: ", ")
    }
}

extension Dictionary where Value == Int {
    /// Re-keys a histogram for printing; counts of duplicate keys are summed.
    fileprivate func mapKeys(_ transform: (Key) -> String) -> [String: Int] {
        reduce(into: [:]) { result, pair in
            result[transform(pair.key), default: 0] += pair.value
        }
    }
}
