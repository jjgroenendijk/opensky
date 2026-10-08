// `swf action-list`: print every action record of one movie, one per line, with
// constant-pool names resolved. It shows which movie fields gate a menu row.
// The listing names game code, so redirect it into `.logs/`, never the repo.

import Foundation
import OpenSkyCLIArguments
import OpenSkyFormatsSWF
import OpenSkyGameData

enum SWFActionListCommand {
    static func run(context: CLIContext, arguments: SWFArguments.ActionList) throws {
        let filter = arguments.movie.lowercased()
        let vfs = context.makeFileSystem()
        let loader = SWFMovieLoader(fileSystem: vfs)
        let paths = loader.moviePaths().filter { $0.contains(filter) }
        guard paths.count == 1, let path = paths.first else {
            throw CLIError.failure("--movie must match one movie; it matched \(paths.count)")
        }
        let movie = try SWFMovie(file: SWFFile(data: vfs.contents(forPath: path)))
        for (index, block) in movie.actionBlocks.enumerated() {
            print("== block \(index)")
            var pool: [String] = []
            for record in block.records {
                if case let .constantPool(names) = record.operands {
                    pool = names
                    continue
                }
                print("\(record.offset) \(record.name ?? "0x\(record.code)") "
                    + describe(record.operands, pool: pool))
            }
        }
    }

    private static func describe(_ operands: SWFActionOperands, pool: [String]) -> String {
        switch operands {
        case let .push(values):
            values.map { describe($0, pool: pool) }.joined(separator: ", ")
        case let .branch(offset):
            "\(offset)"
        case let .storeRegister(register):
            "r\(register)"
        case let .defineFunction(function):
            "\(function.name)(\(function.parameterNames.joined(separator: ", "))) "
                + "\(function.bodySize) bytes"
        case let .goToLabel(label):
            label
        default:
            ""
        }
    }

    private static func describe(_ value: SWFActionValue, pool: [String]) -> String {
        switch value {
        case let .string(text): "\"\(text)\""
        case let .constant8(index): pool.indices.contains(Int(index)) ? pool[Int(index)] : "?"
        case let .constant16(index): pool.indices.contains(Int(index)) ? pool[Int(index)] : "?"
        case let .register(register): "r\(register)"
        case let .integer(number): "\(number)"
        case let .double(number): "\(number)"
        case let .float(number): "\(number)"
        case let .boolean(flag): "\(flag)"
        case .null: "null"
        case .undefined: "undefined"
        }
    }
}
