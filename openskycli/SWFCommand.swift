// `swf sweep`: parse every archive/loose `Interface\*.swf` movie through the
// production SWFFile container decoder and report a known/unknown tag tally
// (milestone 8.2.1 gate), then decode every shape and bitmap definition tag
// and tessellate the shapes (milestone 8.2.2 gate), every font and text tag
// (8.2.3), and every frame-1 display list (8.2.4). `swf render-sweep` renders
// those display lists on the GPU; `swf info <path>` inspects a single movie.

import Foundation

enum SWFCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        guard let sub = scanner.next() else {
            throw CLIError.usage("swf: missing subcommand (sweep|render-sweep|info)")
        }
        switch sub {
        case "sweep":
            try scanner.finish()
            try runSweep(context: context)
        case "render-sweep":
            try SWFRenderSweep.run(context: context, scanner: &scanner)
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
        var content = SWFContentTally()
        var fontText = SWFFontTextTally()
        var display = SWFDisplayTally()
        let fonts = SWFMovieLoader(fileSystem: vfs).fontEnvironment()
        var unexpected: [(String, String)] = []
        for path in paths {
            do {
                let file = try SWFFile(data: vfs.contents(forPath: path))
                print("[INFO] \(path): \(summaryLine(for: file))")
                tally.record(file)
                content.record(file, path: path)
                fontText.record(file, path: path)
                display.record(file, path: path, fonts: fonts)
            } catch let SWFError.unsupportedCompression(signature) {
                print("[INFO] \(path): unsupported compression (\(signature)), accounted")
                tally.unsupported += 1
            } catch {
                unexpected.append((path, String(describing: error)))
            }
        }
        let failed = unexpected + content.failures + fontText.failures + display.failures
        for failure in failed.prefix(20) {
            printError("[ERROR] \(failure.0): \(failure.1)")
        }
        printContentTally(content)
        fontText.printReport()
        display.printReport()
        SWFFontConfigReport.run(vfs: vfs)
        printTally(tally, total: paths.count, unexpected: unexpected.count)
        guard failed.isEmpty else {
            throw CLIError.failure(
                "swf sweep failed: \(unexpected.count) container, "
                    + "\(content.failures.count) shape/bitmap, "
                    + "\(fontText.failures.count) font/text, "
                    + "\(display.failures.count) display-list decode failures"
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

    private static func printContentTally(_ content: SWFContentTally) {
        let shapeBreakdown = content.shapeCountByTag.sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        print(
            "[INFO] swf sweep shapes: \(content.shapeCount) decoded (\(shapeBreakdown)), "
                + "\(content.triangleCount) triangles, \(content.shapeFailureCount) failed"
        )
        let bitmapBreakdown = content.bitmapCountByFormat.sorted { $0.key < $1.key }
            .map { "\($0.key) \($0.value)" }
            .joined(separator: ", ")
        print(
            "[INFO] swf sweep bitmaps: \(content.bitmapCount) decoded (\(bitmapBreakdown)), "
                + "\(content.bitmapFailureCount) failed"
        )
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

/// Decodes and tallies every shape and bitmap definition tag across an
/// `swf sweep` run (milestone 8.2.2 gate): shapes are parsed and tessellated,
/// bitmaps decoded to RGBA. Any decode failure on a vanilla movie is recorded
/// and fails the sweep.
private struct SWFContentTally {
    var shapeCount = 0
    var shapeCountByTag: [String: Int] = [:]
    var triangleCount = 0
    var shapeFailureCount = 0
    var bitmapCount = 0
    var bitmapCountByFormat: [String: Int] = [:]
    var bitmapFailureCount = 0
    var failures: [(String, String)] = []

    mutating func record(_ file: SWFFile, path: String) {
        // JPEGTables is movie-global context for DefineBits (tag 6).
        let jpegTables = file.tags
            .first { $0.code == SWFBitmapDecoder.jpegTablesTagCode }?.body
        for tag in file.tags {
            if SWFShapeDefinition.tagCodes.contains(tag.code) {
                recordShape(tag, path: path)
            } else if SWFBitmapDecoder.tagCodes.contains(tag.code) {
                recordBitmap(tag, path: path, jpegTables: jpegTables)
            }
        }
    }

    private mutating func recordShape(_ tag: SWFTag, path: String) {
        let name = SWFTagName.name(forCode: tag.code) ?? "tag \(tag.code)"
        do {
            let shape = try SWFShapeDefinition.parse(tag: tag)
            let mesh = SWFShapeTessellator.tessellate(shape)
            shapeCount += 1
            shapeCountByTag[name, default: 0] += 1
            triangleCount += mesh.triangleCount
        } catch {
            shapeFailureCount += 1
            failures.append(("\(path) \(name)", String(describing: error)))
        }
    }

    private mutating func recordBitmap(_ tag: SWFTag, path: String, jpegTables: Data?) {
        let name = SWFTagName.name(forCode: tag.code) ?? "tag \(tag.code)"
        do {
            let bitmap = try SWFBitmapDecoder.decode(tag: tag, jpegTables: jpegTables)
            bitmapCount += 1
            bitmapCountByFormat[bitmap.sourceFormat.rawValue, default: 0] += 1
        } catch {
            bitmapFailureCount += 1
            failures.append(("\(path) \(name)", String(describing: error)))
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
