// `gaps`: what the install's data uses that the engine does not implement yet,
// per area, with how much is done and what is left. Progress goes to stderr, so
// stdout holds only the report.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsESM
import OpenSkyGameData

enum GapsCommand {
    static func run(context: CLIContext, arguments: GapsArguments) throws {
        let gatherer = try GapsGatherer(context: context, fieldReadsPath: arguments.fieldReads)
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
        if let path = arguments.summaryOut {
            let table = GapsReport.markdownSummary(sections).joined(separator: "\n") + "\n"
            try Data(table.utf8).write(to: URL(fileURLWithPath: path))
        }
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
    /// The fields engine code reads, when the fields section runs.
    let fieldReads: RecordFieldReads?
    /// One sweep serves the records and fields sections.
    private(set) lazy var recordSweep: RecordCoverageSweep = {
        var sweep = RecordCoverageSweep(countingFields: fieldReads != nil)
        for plugin in plugins.plugins {
            sweep.sweep(plugin.file)
        }
        return sweep
    }()

    init(context: CLIContext, fieldReadsPath: String?) throws {
        self.context = context
        fieldReads = try fieldReadsPath.map(Self.loadFieldReads)
    }

    private static func loadFieldReads(path: String) throws -> RecordFieldReads {
        let text: String
        do {
            text = try String(contentsOfFile: path, encoding: .utf8)
        } catch {
            throw CLIError.failure("cannot read the field reads list \(path): \(error)")
        }
        do {
            return try RecordFieldReads(text: text)
        } catch let .malformedLine(line) {
            throw CLIError.failure("the field reads list \(path) is malformed at line \(line)")
        }
    }

    func sections(for key: String) throws -> [GapSection] {
        guard let build = builders[key] else { throw CLIError.usage("unknown section \(key)") }
        return try build()
    }

    /// One builder per section key in `GapsArguments.sectionKeys`.
    private var builders: [String: () throws -> [GapSection]] {
        [
            "papyrus": { try [self.papyrus()] }, "events": { [self.events()] },
            "conditions": { try [self.conditions()] }, "records": { try [self.records()] },
            "fields": { try [self.fields()] }, "settings": { try [self.settings()] },
            "magic": { try [self.magic()] },
            "perks": perks, "packages": packages, "behavior": behavior,
            "animations": animations, "meshes": assets.meshes, "textures": assets.textures,
            "audio": assets.audio, "swf": swf
        ]
    }

    /// The active plugins, or a failure when none opened.
    func requirePlugins() throws -> LoadOrderPlugins {
        guard !plugins.plugins.isEmpty else {
            throw CLIError.failure("no active plugin could be opened")
        }
        return plugins
    }
}
