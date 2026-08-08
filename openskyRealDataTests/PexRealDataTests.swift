// Env-gated census of every compiled Papyrus script the user's own install
// exposes through the VFS. Game bytes remain read-only external input; only
// aggregate counts and call names are written to gitignored logs/.

import Foundation
@testable import opensky
import Testing

struct PexRealDataTests {
    private static let dataRoot: GameDataRoot? = {
        let environment = ProcessInfo.processInfo.environment
        guard let path = environment[GameDataLocator.environmentKey], !path.isEmpty
        else { return nil }
        return try? GameDataLocator.locate()
    }()

    @Test(.enabled(if: Self.dataRoot != nil))
    func sweepsEveryScript() throws {
        let root = try #require(Self.dataRoot)
        let fileSystem = VirtualFileSystem(root: root)
        let loader = PexScriptLoader(fileSystem: fileSystem)
        let paths = loader.scriptPaths()
        var inventory = PexInventory()

        for path in paths {
            do {
                try inventory.record(loader.load(path))
            } catch {
                inventory.noteDecodeFailure(path: path)
            }
        }

        #expect(paths.count > 10000, "expected the base game and DLC script surface")
        #expect(inventory.scriptTotal == paths.count, "some PEX files did not decode")
        #expect(inventory.decodeFailureTotal == 0, "PEX decode failures are in the report")
        #expect(inventory.unknownOpcodeTotal == 0, "unknown opcode count changed")
        #expect(inventory.instructionTotal > 100_000, "instruction census is implausibly small")
        #expect(inventory.externalCallTotal > 10000, "external-call census is implausibly small")

        let report = Self.report(paths: paths, inventory: inventory)
        print(report)
        try FileManager.default.createDirectory(
            at: logsDirectory,
            withIntermediateDirectories: true
        )
        try report.write(to: logURL, atomically: true, encoding: .utf8)
    }

    private static func report(paths: [String], inventory: PexInventory) -> String {
        let opcodes = inventory.rankedOpcodes
            .map { "\($0.count)\t\($0.name)" }
            .joined(separator: "\n")
        let calls = inventory.rankedExternalCalls.prefix(200)
            .map { "\($0.count)\t\($0.name)" }
            .joined(separator: "\n")
        let failures = inventory.rankedDecodeFailures
            .map { "\($0.count)\t\($0.name)" }
            .joined(separator: "\n")
        return """
        PEX census observed 2026-07-30
        scripts\t\(paths.count)
        decoded\t\(inventory.scriptTotal)
        functions\t\(inventory.functionTotal)
        instructions\t\(inventory.instructionTotal)
        external calls\t\(inventory.externalCallTotal)
        unknown opcodes\t\(inventory.unknownOpcodeTotal)
        decode failures\t\(inventory.decodeFailureTotal)

        Opcode frequency
        \(opcodes)

        Top external call targets
        \(calls)

        Decode failures
        \(failures)
        """
    }

    private var logURL: URL {
        logsDirectory.appending(path: "pex-census.log")
    }

    private var logsDirectory: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: "logs")
    }
}
