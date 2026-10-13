// `gaps`: what the install's data uses that the engine does not implement yet,
// per area, with how much is done and what is left. Progress goes to stderr, so
// stdout holds only the report.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsESM
import OpenSkyGameData

enum GapsCommand {
    static func run(context: CLIContext, arguments: GapsArguments) throws {
        let gatherer = GapsGatherer(context: context)
        var sections: [GapSection] = []
        for key in arguments.sections {
            let started = Date()
            progress("[INFO] gaps: \(key)...")
            sections += try gatherer.sections(for: key)
            progress("[INFO] gaps: \(key) took \(Int(Date().timeIntervalSince(started))) s")
        }
        let lines = GapsReport.summary(sections)
            + sections.flatMap { GapsReport.lines($0, limit: arguments.limit) }
        print(lines.joined(separator: "\n"))
    }

    private static func progress(_ line: String) {
        FileHandle.standardError.write(Data((line + "\n").utf8))
    }
}

/// Builds the sections of one area. Each reads the install on demand and keeps
/// the plugins open between areas.
final class GapsGatherer {
    let context: CLIContext
    private(set) lazy var fileSystem = context.makeFileSystem()
    private(set) lazy var plugins = LoadOrderPlugins(ActivePluginFiles.load(root: context.root))

    init(context: CLIContext) {
        self.context = context
    }

    func sections(for key: String) throws -> [GapSection] {
        switch key {
        case "papyrus": try [papyrus()]
        case "conditions": try [conditions()]
        case "records": try [records()]
        case "magic": try [magic()]
        case "perks": try perks()
        case "behavior": behavior()
        case "swf": swf()
        default: throw CLIError.usage("unknown section \(key)")
        }
    }

    /// The active plugins, or a failure when none opened.
    func requirePlugins() throws -> LoadOrderPlugins {
        guard !plugins.plugins.isEmpty else {
            throw CLIError.failure("no active plugin could be opened")
        }
        return plugins
    }
}
