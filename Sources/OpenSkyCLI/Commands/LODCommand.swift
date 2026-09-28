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
        let archivePaths = vfs.archiveEntries().map(\.path)
        let entries = archivePaths.filter {
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

        try sweepTreeLOD(
            worldspace: worldspace,
            terrainPrefix: terrainPrefix,
            archivePaths: archivePaths,
            fileSystem: vfs
        )
    }

    private static func sweepTreeLOD(
        worldspace: String,
        terrainPrefix: String,
        archivePaths: [String],
        fileSystem: VirtualFileSystem
    ) throws {
        let treePrefix = terrainPrefix + "trees\\"
        let listPath = treePrefix + worldspace + ".lst"
        guard archivePaths.contains(listPath) || fileSystem.exists(listPath) else {
            print("[INFO] tree LOD: no .lst; skipped")
            return
        }
        let list = try TreeLODList(data: fileSystem.contents(forPath: listPath))
        let treeBlocks = archivePaths.filter {
            $0.hasPrefix(treePrefix) && $0.hasSuffix(".btt")
        }
        var treeReferences = 0
        var treeFailures: [(String, String)] = []
        for path in treeBlocks {
            do {
                let block = try TreeLODBlock(
                    data: fileSystem.contents(forPath: path),
                    list: list
                )
                treeReferences += block.referenceCount
            } catch {
                treeFailures.append((path, String(describing: error)))
            }
        }
        for failure in treeFailures.prefix(20) {
            printError("[ERROR] \(failure.0): \(failure.1)")
        }
        guard treeFailures.isEmpty else {
            throw CLIError.failure(
                "tree LOD sweep failed for \(treeFailures.count) of \(treeBlocks.count) files"
            )
        }
        print(
            "[INFO] tree LOD: \(list.types.count) types + \(treeBlocks.count) .btt + "
                + "\(treeReferences) refs, 0 failed"
        )
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
