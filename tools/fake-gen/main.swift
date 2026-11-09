// Writes a fake of each OpenSkySessionInterface port a test names into the folder given.
// Usage: fake-gen <repository root> <output folder>.

import Foundation

let arguments = CommandLine.arguments
guard arguments.count == 3 else {
    print("usage: fake-gen <repository root> <output folder>")
    exit(2)
}
let root = URL(fileURLWithPath: arguments[1])
let output = URL(fileURLWithPath: arguments[2])
let interface = root.appendingPathComponent("src/Sources/OpenSkySessionInterface").path + "/"
let index = try ProtocolIndex(sources: root.appendingPathComponent("src/Sources"))
/// The session interface and the modules it may use, read from the imports of its files.
let visible = Set(index.protocols.values.filter { $0.file.hasPrefix(interface) }.flatMap(\.imports))
    .union(["OpenSkySessionInterface"])
let ports = Set(index.protocols.values.filter { $0.file.hasPrefix(interface) }.map(\.name))
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for old in try FileManager.default.contentsOfDirectory(atPath: output.path)
    where old.hasPrefix("Fake") && old.hasSuffix(".swift")
{
    try FileManager.default.removeItem(at: output.appendingPathComponent(old))
}
let mainActorFakes = Set(ports.filter { port in
    index.lineage(of: port).contains { $0.inherited.contains("Sendable") }
}.map { "Fake\($0)" })
/// The ports a test names as `Fake<Port>`, outside the library itself. A fake no test uses
/// would be dead code, so the library holds only these and the fakes they build.
func namedPorts(in tests: URL, skipping library: String) throws -> Set<String> {
    var found: Set<String> = []
    let files = FileManager.default.enumerator(at: tests, includingPropertiesForKeys: nil)
    while let file = files?.nextObject() as? URL {
        guard file.pathExtension == "swift", !file.path.hasPrefix(library) else { continue }
        found.formUnion(fakeNames(in: try String(contentsOf: file, encoding: .utf8)))
    }
    return found.intersection(ports)
}

func fakeNames(in text: String) -> Set<String> {
    Set(text.matches(of: #/\bFake([A-Z]\w*)\b/#).map { String($0.1) })
}

func writer(for port: String) -> FakeWriter {
    let lineage = index.lineage(of: port)
    let defaults = lineage.reduce(into: Set<String>()) { keys, info in
        keys.formUnion(index.defaults[info.name]?[info.module] ?? [])
    }
    return FakeWriter(
        port: port, lineage: lineage, defaults: defaults, ports: ports,
        typeModules: index.typeModules, visible: visible,
        mainActorFakes: mainActorFakes
    )
}

let library = root.appendingPathComponent("src/Tests/OpenSkySessionTesting").path + "/"
var pending = try namedPorts(in: root.appendingPathComponent("src/Tests"), skipping: library)
var written: Set<String> = []
while let port = pending.popFirst() {
    written.insert(port)
    for file in writer(for: port).files() {
        try file.text.write(
            to: output.appendingPathComponent(file.name), atomically: true, encoding: .utf8
        )
        pending.formUnion(fakeNames(in: file.text).intersection(ports).subtracting(written))
    }
}
print("[ OK ] \(written.count) fakes written to \(output.path)")
