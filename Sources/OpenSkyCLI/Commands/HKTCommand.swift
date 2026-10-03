// `hkt <key>` decodes one Havok binary tagfile; `hkt sweep` decodes every
// archived `.hkt` and tallies classes, cloth classes, and skeleton bones.
// See docs/formats/hkt-tagfile.md.

import Foundation
import OpenSkyFormatsAnimation
import OpenSkyGameData

enum HKTCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let target = try scanner.positional("key or sweep")
        try scanner.finish()
        let fileSystem = context.makeFileSystem()
        if target == "sweep" {
            try sweep(fileSystem)
            return
        }
        let census = try decode(target, fileSystem)
        print("version: \(census.version), end tag: \(census.hasEndTag)")
        for definition in census.definitions {
            let objects = census.objectCounts[definition.name] ?? 0
            print("class \(definition.name) v\(definition.version): \(objects) objects")
        }
        print("cloth classes: \(census.clothClasses.count)")
        print("skeleton bones: \(census.skeletonBones.joined(separator: ", "))")
    }

    private static func decode(
        _ path: String,
        _ fileSystem: VirtualFileSystem
    ) throws -> HKTCensus {
        do {
            return try HKTCensus(file: HKTagfile(data: fileSystem.contents(forPath: path)))
        } catch {
            throw CLIError.failure("cannot decode \(path): \(String(describing: error))")
        }
    }

    private static func sweep(_ fileSystem: VirtualFileSystem) throws {
        let paths = fileSystem.archiveEntries().map(\.path).filter { $0.hasSuffix(".hkt") }
        var classes: [HKTCensus.ClassVersion: Int] = [:]
        var failures = 0
        var objects = 0
        var cloth = 0
        var bones = 0
        for path in paths.sorted() {
            do {
                let census = try decode(path, fileSystem)
                objects += census.objectCount
                cloth += census.clothClasses.count
                bones += census.skeletonBones.count
                census.definitions.forEach { classes[$0, default: 0] += 1 }
                print("[INFO] \(path): v\(census.version), \(census.objectCount) objects, "
                    + "\(census.skeletonBones.count) bones, end tag \(census.hasEndTag)")
            } catch {
                failures += 1
                printError("[WARNING] \(error)")
            }
        }
        for key in classes.keys.sorted() {
            print("class \(key.name) v\(key.version): \(classes[key] ?? 0) files")
        }
        print("files: \(paths.count), failed: \(failures), objects: \(objects), "
            + "class versions: \(classes.count), cloth classes: \(cloth), bones: \(bones)")
        if failures > 0 {
            throw CLIError.failure("\(failures) tagfiles did not decode")
        }
    }
}
