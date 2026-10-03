// Env-gated native census over the trap and trigger scripts the install ships.
// Every native they call is implemented or a traced stub, so a trap script never
// stops on a missing native. See docs/engine/traps.md.

import Foundation
@testable import OpenSkyFormatsPEX
@testable import OpenSkyGameData
@testable import OpenSkyScripting
import Testing

@MainActor
struct TrapScriptCensusRealDataTests {
    @Test(.enabled(if: RealDataEnvironment.hasDataRoot))
    func everyTrapNativeIsRegistered() throws {
        let root = try #require(RealDataEnvironment.dataRoot)
        let loader = PexScriptLoader(fileSystem: VirtualFileSystem(root: root))
        let files = try loader.scriptPaths().map(loader.load)
        let names = files.flatMap(\.objects).map(\.name)
        let callers = Set(names.filter(TrapScriptFamily.contains).map { $0.lowercased() })
        let census = PexNativeCensus(files: files, callers: callers)
        let registry = PapyrusNativeRegistry.standard
        let missing = census.rankedReferences.filter { reference in
            let parts = reference.name.split(separator: ".", maxSplits: 1).map(String.init)
            return parts.count == 2
                && !registry.contains(scriptName: parts[0], functionName: parts[1])
        }
        let report = (["trap scripts: \(callers.count)"]
            + census.rankedReferences.map { "\($0.name) \($0.count)" }
            + ["missing:"] + missing.map { "\($0.name) \($0.count)" })
            .joined(separator: "\n")
        print(report)
        try FileManager.default.createDirectory(
            at: RepositoryLogs.directory(), withIntermediateDirectories: true
        )
        try report.write(
            to: RepositoryLogs.directory().appending(path: "trap-native-census.log"),
            atomically: true,
            encoding: .utf8
        )
        #expect(callers.count > 40)
        #expect(missing.isEmpty, "missing natives: \(missing.map(\.name))")
    }
}
