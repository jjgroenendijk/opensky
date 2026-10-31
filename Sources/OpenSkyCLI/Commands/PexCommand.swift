// `pex`: one compiled script from the install, printed as text by `PexDisassembly`. It
// shows which natives a vanilla script calls and with which arguments.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsPEX
import OpenSkyGameData

enum PexCommand {
    static func run(context: CLIContext, arguments: PexArguments) throws {
        let file: PexFile
        do {
            file = try PexScriptLoader(fileSystem: context.makeFileSystem())
                .load(arguments.script)
        } catch {
            throw CLIError.failure(
                "cannot read script \(arguments.script): \(String(describing: error))"
            )
        }
        for line in PexDisassembly.lines(of: file, function: arguments.function) {
            print(line)
        }
    }
}
