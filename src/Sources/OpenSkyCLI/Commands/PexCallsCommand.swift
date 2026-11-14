// `pex-calls`: every call of one function in the install's archived scripts, with the
// caller and the constant arguments. It shows which vanilla scripts drive a native.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsPEX
import OpenSkyScriptingInterface

enum PexCallsCommand {
    static func run(context: CLIContext, arguments: PexCallsArguments) throws {
        let loader = PexScriptLoader(fileSystem: context.makeFileSystem())
        let paths = loader.scriptPaths()
        var parsed = 0
        var sites = 0
        var callers = 0
        for path in paths {
            guard let file = try? loader.load(path) else { continue }
            parsed += 1
            let found = PexCallSites.find(arguments.function, in: file)
            guard !found.isEmpty else { continue }
            callers += 1
            sites += found.count
            for site in found {
                print(PexCallSites.line(site))
            }
        }
        FileHandle.standardError.write(Data(
            ("[INFO] \(sites) calls of \(arguments.function) in \(callers) scripts; "
                + "\(parsed) of \(paths.count) archived scripts parsed\n").utf8
        ))
    }
}
