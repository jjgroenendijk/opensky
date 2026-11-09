// Runs the structural rules over the files named on the command line, given as paths
// from the repository root, and prints each finding in the Xcode format.

import Foundation
import SwiftParser
import SwiftSyntax

var failed = false
for path in CommandLine.arguments.dropFirst() {
    let active = rules.filter { $0.applies(to: path) }
    guard !active.isEmpty else { continue }
    guard let text = try? String(contentsOfFile: path, encoding: .utf8) else {
        print("\(path):1:1: error: the file could not be read (syntax_rules)")
        failed = true
        continue
    }
    let tree = Parser.parse(source: text)
    let lines = SourceLocationConverter(fileName: path, tree: tree)
    for rule in active {
        for position in rule.find(tree) {
            let place = lines.location(for: position)
            print("\(path):\(place.line):\(place.column): error: \(rule.message) (\(rule.id))")
            failed = true
        }
    }
}
exit(failed ? 1 : 0)
