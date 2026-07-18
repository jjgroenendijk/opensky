// `lod [--worldspace]`: parse lodsettings + defensively sweep every terrain
// and object LOD NIF for one worldspace through production decoders.

import Foundation

enum LODCommand {
    static func run(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let worldspace = try (scanner.option("--worldspace")
            ?? FirstRenderCell.worldspaceEditorID).lowercased()
        try scanner.finish()
        let vfs = context.makeFileSystem()
        let settingsPath = "lodsettings\\\(worldspace).lod"
        let settings = try LODSettings(data: vfs.contents(forPath: settingsPath))
        print(
            "[INFO] \(worldspace): origin (\(settings.origin.x),\(settings.origin.y)), "
                + "stride \(settings.stride), levels "
                + settings.levels.map(String.init).joined(separator: "/")
        )

        let terrainPrefix = "meshes\\terrain\\\(worldspace)\\"
        let objectPrefix = terrainPrefix + "objects\\"
        let entries = vfs.archiveEntries().map(\.path).filter {
            ($0.hasPrefix(terrainPrefix) && $0.hasSuffix(".btr"))
                || ($0.hasPrefix(objectPrefix) && $0.hasSuffix(".bto"))
        }
        var failed: [(String, String)] = []
        var terrainCount = 0
        var objectCount = 0
        for path in entries {
            do {
                let file = try NIFFile(data: vfs.contents(forPath: path))
                try validateLODBlocks(file)
                _ = try file.model()
                if path.hasSuffix(".btr") {
                    terrainCount += 1
                } else {
                    objectCount += 1
                }
            } catch {
                failed.append((path, String(describing: error)))
            }
        }
        for failure in failed.prefix(20) {
            printError("[ERROR] \(failure.0): \(failure.1)")
        }
        guard failed.isEmpty else {
            throw CLIError.failure("LOD sweep failed for \(failed.count) of \(entries.count) files")
        }
        print("[INFO] LOD sweep: \(terrainCount) .btr + \(objectCount) .bto, 0 failed")
    }

    private static func validateLODBlocks(_ file: NIFFile) throws {
        for block in file.blocks {
            switch block.typeName {
            case "BSMultiBoundNode":
                _ = try NIFMultiBoundNode(data: block.data, header: file.header)
            case "BSMultiBound":
                _ = try NIFMultiBound(data: block.data)
            case "BSMultiBoundAABB":
                _ = try NIFMultiBoundAABB(data: block.data)
            case "BSSubIndexTriShape":
                _ = try NIFSubIndexTriShape(data: block.data, header: file.header)
            default:
                break
            }
        }
    }
}
