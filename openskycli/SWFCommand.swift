// `swf sweep`: parse every archive/loose `Interface\*.swf` movie through the
// production SWFFile container decoder and report a known/unknown tag tally
// (milestone 8.2.1 gate). `swf info <path>` inspects a single movie.

import Foundation

enum SWFCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        guard let sub = scanner.next() else {
            throw CLIError.usage("swf: missing subcommand (sweep|info)")
        }
        switch sub {
        case "sweep":
            try scanner.finish()
            try runSweep(context: context)
        case "info":
            let path = try scanner.positional("path")
            try scanner.finish()
            try runInfo(context: context, path: path)
        default:
            throw CLIError.usage("swf: unknown subcommand \(sub)")
        }
    }

    private static func runInfo(context: CLIContext, path: String) throws {
        let vfs = context.makeFileSystem()
        let file = try SWFFile(data: vfs.contents(forPath: path))
        print("[INFO] \(path): \(summaryLine(for: file))")
        for tag in file.tags {
            let name = SWFTagName.name(forCode: tag.code) ?? "unknown"
            print("  tag \(tag.code) (\(name)): \(tag.body.count) bytes")
        }
    }

    /// Enumerates every `interface\*.swf` archive path, parses each through
    /// `SWFFile`, and tallies known/unknown tag codes. `ZWS` movies are
    /// counted as accounted-but-unsupported (`SWFError.unsupportedCompression`
    /// is the documented, expected outcome for LZMA bodies at this stage);
    /// any other thrown error is an unexpected failure and fails the sweep.
    private static func runSweep(context: CLIContext) throws {
        let vfs = context.makeFileSystem()
        let paths = vfs.archiveEntries().map(\.path)
            .filter { $0.hasPrefix("interface\\") && $0.hasSuffix(".swf") }
        var tally = SWFSweepTally()
        var unexpected: [(String, String)] = []
        for path in paths {
            do {
                let file = try SWFFile(data: vfs.contents(forPath: path))
                print("[INFO] \(path): \(summaryLine(for: file))")
                tally.record(file)
            } catch let SWFError.unsupportedCompression(signature) {
                print("[INFO] \(path): unsupported compression (\(signature)), accounted")
                tally.unsupported += 1
            } catch {
                unexpected.append((path, String(describing: error)))
            }
        }
        for failure in unexpected.prefix(20) {
            printError("[ERROR] \(failure.0): \(failure.1)")
        }
        printTally(tally, total: paths.count, unexpected: unexpected.count)
        guard unexpected.isEmpty else {
            throw CLIError.failure(
                "swf sweep failed for \(unexpected.count) of \(paths.count) files"
            )
        }
    }

    private static func summaryLine(for file: SWFFile) -> String {
        let compression = switch file.compression {
        case .none: "none"
        case .zlib: "zlib"
        }
        let widthPx = Double(file.frameSize.xMax - file.frameSize.xMin) / 20
        let heightPx = Double(file.frameSize.yMax - file.frameSize.yMin) / 20
        return "version \(file.version), compression \(compression), "
            + "frame \(Int(widthPx))x\(Int(heightPx))px, frames \(file.frameCount), "
            + "tags \(file.tags.count)"
    }

    private static func printTally(_ tally: SWFSweepTally, total: Int, unexpected: Int) {
        let parsed = total - unexpected - tally.unsupported
        print(
            "[INFO] swf sweep: \(total) files, \(parsed) parsed, "
                + "\(tally.unsupported) unsupported (ZWS), \(unexpected) failed"
        )
        print(
            "[INFO] swf sweep tags: \(tally.totalTags) total, "
                + "\(tally.knownTags) known, \(tally.unknownTags) unknown"
        )
        for (code, count) in tally.unknownCodes.sorted(by: { $0.key < $1.key }) {
            print("[INFO]   unknown tag \(code): \(count) occurrences")
        }
    }
}

/// Accumulates known/unknown tag counts across an `swf sweep` run.
private struct SWFSweepTally {
    var unsupported = 0
    var totalTags = 0
    var knownTags = 0
    var unknownTags = 0
    var unknownCodes: [UInt16: Int] = [:]

    mutating func record(_ file: SWFFile) {
        for tag in file.tags {
            totalTags += 1
            if SWFTagName.isKnown(tag.code) {
                knownTags += 1
            } else {
                unknownTags += 1
                unknownCodes[tag.code, default: 0] += 1
            }
        }
    }
}
