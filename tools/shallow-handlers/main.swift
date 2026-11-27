// Lists the Papyrus natives and condition functions the engine registers, and whether each
// body is shallow: it answers a constant and does nothing else (docs/tools/gaps.md).
// Usage: shallow-handlers <repo> <out>, or shallow-handlers --self-check.
// Writes one row per handler: area, name, `works`, `shallow` or `on-purpose`, and the
// constant or the reason.

import Foundation
import SwiftParser
import SwiftSyntax

/// A shallow native, a stub table row, a working native, an on-purpose one, and a condition
/// function that always fails must each be judged so.
func selfCheck() -> Bool {
    let source = """
    registry.register(PapyrusNativeFunction(scriptName: "Game", functionName: "Shake") { call, context in
        context.log.append("Stubbed")
        return .returned(.none)
    })
    scriptState("Sound", "Play", into: &registry) { call, bridge, sound in
        guard let play = bridge.play else { return failure(call, "no world") }
        return .returned(.integer(play(sound)))
    }
    reference("GetDistance") { call, bridge in .returned(.float(0)) }
    // Matches the game: the release build ignores it.
    native("Debug", "ToggleAI") { _, _ in .returned(.none) }
    private static let stubs = [TrapStub("Cell", "IsAttached", .boolean(true))]
    func install() { register { _, _ in .deviated(stub.answer, .stubbed) } }
    registry.register(ConditionFunction(index: 7, name: "GetVATSValue") { _ in
        .failure(.unavailableData(.camera))
    })
    """
    let rows = handlers(in: Parser.parse(source: source)).map(\.row)
    return rows == [
        "native\tGame.Shake\tshallow\t.returned(.none)",
        "native\tSound.Play\tworks\t",
        "native\t*.GetDistance\tshallow\t.returned(.float(0))",
        "native\tDebug.ToggleAI\ton-purpose\tthe release build ignores it.",
        "condition\tGetVATSValue\tshallow\t.failure(.unavailableData(.camera))",
        "native\tCell.IsAttached\tshallow\tstub table: .boolean(true)"
    ]
}

let arguments = CommandLine.arguments.dropFirst()
guard selfCheck() else {
    print("[FAIL] shallow-handlers self-check: a handler was judged wrong")
    exit(1)
}
if arguments.first == "--self-check" {
    print("[ OK ] shallow-handlers self-check")
    exit(0)
}
guard arguments.count == 2 else {
    print("usage: shallow-handlers <repo> <out>")
    exit(2)
}
let sources = URL(fileURLWithPath: arguments.first!).appendingPathComponent("src/Sources")
var rows: [String] = []
let files = FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil)
while let file = files?.nextObject() as? URL {
    guard file.pathExtension == "swift", let text = try? String(contentsOf: file, encoding: .utf8)
    else { continue }
    let natives = file.path.contains("/OpenSkyScripting") || file.path.contains("/OpenSkyScriptAdapters")
    rows += handlers(in: Parser.parse(source: text))
        .filter { natives || $0.area == .condition }
        .map(\.row)
}
let unique = Array(Set(rows)).sorted()
try unique.map { $0 + "\n" }.joined().write(toFile: arguments.last!, atomically: true, encoding: .utf8)
let shallow = unique.filter { $0.split(separator: "\t")[2] == "shallow" }.count
print("[INFO] shallow handlers: \(shallow) of \(unique.count); list in \(arguments.last!)")
