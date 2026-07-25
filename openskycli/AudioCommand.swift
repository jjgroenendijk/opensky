// `audio info <path>` inspects one `.xwm` file through the production
// `XWMFile` container parser; `audio sweep` frames and WMA-decodes every
// `.xwm` the install provides (milestones 9.1.2 + 9.1.3, gated in
// tools/probe.sh).

import Foundation

enum AudioCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        guard let sub = scanner.next() else {
            throw CLIError.usage("audio: missing subcommand (info|sweep)")
        }
        switch sub {
        case "info":
            let path = try scanner.positional("path")
            try scanner.finish()
            try runInfo(context: context, path: path)
        case "sweep":
            try scanner.finish()
            try AudioSweep.run(context: context)
        default:
            throw CLIError.usage("audio: unknown subcommand \(sub)")
        }
    }

    private static func runInfo(context: CLIContext, path: String) throws {
        let vfs = context.makeFileSystem()
        let file = try XWMFile(data: vfs.contents(forPath: path))
        print("[INFO] \(path): \(summaryLine(for: file))")
        let codec = file.codec
        print("  wFormatTag         0x\(String(format: "%04X", codec.formatTag)) (WMAv2)")
        print("  nChannels          \(codec.channelCount)")
        print("  nSamplesPerSec     \(codec.sampleRate)")
        print("  nAvgBytesPerSec    \(codec.averageBytesPerSecond) (\(codec.bitRate) bit/s)")
        print("  nBlockAlign        \(codec.blockAlign)")
        print("  wBitsPerSample     \(codec.bitsPerSample)")
        print("  cbSize             \(codec.extraData.count)")
        print("  data payload       \(file.payloadByteCount) bytes, \(file.packetCount) packets")
        print("  dpds entries       \(file.packetCumulativeDecodedBytes.count)")
        if let decoded = file.declaredDecodedByteCount {
            print("  decoded bytes      \(decoded)")
        }
        if let samples = file.declaredSampleCount {
            print("  sample frames      \(samples)")
        }
        print("  packet table       \(file.isPacketTableConsistent ? "consistent" : "MISMATCH")")
    }

    /// Shared one-line summary, also used by the sweep.
    static func summaryLine(for file: XWMFile) -> String {
        let codec = file.codec
        let duration = file.declaredDuration.map { String(format: "%.2fs", $0) } ?? "unknown"
        return "\(codec.channelCount)ch \(codec.sampleRate)Hz, "
            + "block \(codec.blockAlign), \(file.packetCount) packets, "
            + "\(file.payloadByteCount) payload bytes, duration \(duration)"
    }
}
