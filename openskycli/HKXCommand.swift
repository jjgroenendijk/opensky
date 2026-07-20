// `hkx <key>`: fetch one Havok packfile through the VFS and dump its
// container inventory — header layout, section table, class-name table, and
// the fixup-derived object list. Same parser the engine uses (todo 6.1), so a
// parse failure here reproduces what later animation/skeleton loading sees.

import Foundation

enum HKXCommand {
    /// First N objects listed verbatim; the rest collapse into a truncation
    /// note so a big packfile stays greppable, not a wall of offsets.
    private static let objectListLimit = 8

    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let key = try scanner.positional("key")
        try scanner.finish()
        let file: HKXFile
        do {
            file = try HKXFile(data: context.makeFileSystem().contents(forPath: key))
        } catch {
            throw CLIError.failure("cannot parse \(key): \(String(describing: error))")
        }

        printHeader(file)
        printSections(file)
        printClassNames(file)
        printObjects(file)
    }

    /// Header line + root-class resolution (unresolved -> stderr warning, not
    /// a hard failure: malformed contents pointer still leaves the file
    /// inspectable).
    private static func printHeader(_ file: HKXFile) {
        let header = file.header
        let rootClass = file.rootClassName?.name ?? "<unresolved>"
        print("[INFO] \(header.versionString), fileVersion \(header.fileVersion), "
            + "\(header.pointerSize)-byte pointers, \(header.sectionCount) sections, "
            + "root class \(rootClass)")
        if file.rootClassName == nil {
            printError("[WARNING] root class name unresolved "
                + "(contents offset \(file.header.contentsClassNameOffset))")
        }
    }

    private static func printSections(_ file: HKXFile) {
        for (index, section) in file.sections.enumerated() {
            let head = section.header
            print("section \(index): \(head.name) — data start \(head.dataStart), "
                + "data size \(head.dataSize), fixups \(section.localFixups.count) local / "
                + "\(section.globalFixups.count) global / \(section.virtualFixups.count) virtual")
        }
    }

    private static func printClassNames(_ file: HKXFile) {
        print("class names: \(file.classNames.count)")
        for entry in file.classNames {
            print("  0x\(String(format: "%08x", entry.signature)) \(entry.name)")
        }
    }

    /// Object summary: total, per-class histogram (count desc, name asc), then
    /// the first `objectListLimit` objects as offset/class rows.
    private static func printObjects(_ file: HKXFile) {
        let objects = file.objects
        print("objects: \(objects.count)")
        let histogram = Dictionary(grouping: objects) { $0.className ?? "<unresolved>" }
            .map { (name: $0.key, count: $0.value.count) }
            .sorted { ($0.count, $1.name) > ($1.count, $0.name) }
        for entry in histogram {
            print("  \(entry.name) \(entry.count)")
        }
        for object in objects.prefix(objectListLimit) {
            let name = object.className ?? "<unresolved>"
            print("  offset 0x\(String(format: "%x", object.dataOffset)) \(name)")
        }
        let hidden = objects.count - min(objects.count, objectListLimit)
        if hidden > 0 {
            print("  ... \(hidden) more objects")
        }
    }
}
