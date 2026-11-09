// Writes a fake for every port in OpenSkySessionInterface into the folder given.
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
for port in ports.sorted() {
    let lineage = index.lineage(of: port)
    let defaults = lineage.reduce(into: Set<String>()) { keys, info in
        keys.formUnion(index.defaults[info.name]?[info.module] ?? [])
    }
    let writer = FakeWriter(
        port: port, lineage: lineage, defaults: defaults, ports: ports,
        typeModules: index.typeModules, visible: visible,
        mainActorFakes: mainActorFakes
    )
    try writer.source().write(
        to: output.appendingPathComponent("\(writer.fakeName).swift"), atomically: true,
        encoding: .utf8
    )
}
print("[ OK ] \(ports.count) fakes written to \(output.path)")
