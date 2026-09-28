// `nif <key>` / `dds <key>`: fetch one asset through the VFS and dump what
// the engine parsers see — NIF container stats + flattened model summary,
// DDS header + mip chain. Same code paths the renderer uses, so a parse
// failure here reproduces a renderer skip exactly.

import Foundation

enum AssetCommand {
    static func runNIF(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let key = try scanner.positional("key")
        try scanner.finish()
        let file: NIFFile
        do {
            file = try NIFFile(data: context.makeFileSystem().contents(forPath: key))
        } catch {
            throw CLIError.failure("cannot parse \(key): \(String(describing: error))")
        }

        let header = file.header
        print("[INFO] \(header.versionLine), user version \(header.userVersion), "
            + "BS stream \(header.bsStream.map { String($0.version) } ?? "-")")
        let counts = file.blockTypeCounts().sorted { ($0.value, $1.key) > ($1.value, $0.key) }
        print("blocks: \(file.blocks.count) — "
            + counts.map { "\($0.key) \($0.value)" }.joined(separator: ", "))
        for (index, block) in file.blocks.enumerated() {
            if let node = decodedNode(block, header: file.header) {
                print("block \(index): \(block.typeName) \(node.object.name ?? "-") "
                    + "children \(node.children)")
            } else if let shape = decodedShape(block, header: file.header) {
                print("block \(index): \(block.typeName) \(shape.object.name ?? "-") "
                    + "\(shape.positions.count) vertices, \(shape.indices.count / 3) triangles")
            }
        }
        printModelSummary(file: file, key: key)
    }

    private static func decodedNode(_ block: NIFFile.Block, header: NIFHeader) -> NIFNode? {
        guard NIFNode.traversedTypes.contains(block.typeName) else { return nil }
        return try? NIFNode(data: block.data, header: header)
    }

    private static func decodedShape(
        _ block: NIFFile.Block,
        header: NIFHeader
    ) -> NIFTriShape? {
        guard ["BSTriShape", "BSSubIndexTriShape"].contains(block.typeName) else { return nil }
        return try? NIFTriShape(data: block.data, header: header)
    }

    /// Flattened engine-model view (drawable meshes + resolved materials).
    private static func printModelSummary(file: NIFFile, key: String) {
        let model: Model
        do {
            model = try file.model()
        } catch {
            printError("[WARNING] scene graph flatten failed: \(String(describing: error))")
            return
        }
        let vertexCount = model.meshes.reduce(0) { $0 + $1.positions.count }
        let triangleCount = model.meshes.reduce(0) { $0 + $1.indices.count / 3 }
        print("model: \(model.meshes.count) drawable meshes "
            + "(\(model.skippedShapeCount) skipped), \(vertexCount) vertices, "
            + "\(triangleCount) triangles")
        if let bounds = ModelBounds.containing(model: model) {
            print("bounds: min (\(bounds.min.x), \(bounds.min.y), \(bounds.min.z)) "
                + "max (\(bounds.max.x), \(bounds.max.y), \(bounds.max.z))")
        }
        for (index, material) in model.materials.enumerated() {
            print("material \(index): diffuse \(material.diffuseTexture ?? "-"), "
                + "normal \(material.normalTexture ?? "-")"
                + (material.alphaTestThreshold != nil ? ", alpha-test" : "")
                + (material.doubleSided ? ", double-sided" : ""))
        }
    }

    static func runDDS(context: CLIContext, scanner: inout ArgumentScanner) throws {
        let key = try scanner.positional("key")
        try scanner.finish()
        let data: Data
        let file: DDSFile
        do {
            data = try context.makeFileSystem().contents(forPath: key)
            file = try DDSFile(data: data)
        } catch {
            throw CLIError.failure("cannot parse \(key): \(String(describing: error))")
        }

        print("[INFO] \(file.width)x\(file.height) \(file.format), "
            + "\(file.mipCount) mips, declares sRGB: \(file.declaresSRGB), "
            + "\(data.count) bytes total")
        for level in 0 ..< file.mipCount {
            print("  mip \(level): \(file.width(level: level))x\(file.height(level: level)), "
                + "\(file.mipData(level: level).count) bytes")
        }
    }
}
