// Builds the real cells around the first render cell, for suites that look for
// placed objects of one kind near Whiterun.

import Foundation
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld

struct WhiterunCellSweep {
    let file: ESMFile
    let builder: CellSceneBuilder

    init() throws {
        guard let device = RealDataEnvironment.device, let root = RealDataEnvironment.dataRoot
        else { throw ESMError.malformed("no render device or data root") }
        let vfs = VirtualFileSystem(root: root)
        file = try ESMFile(url: root.dataURL.appending(path: "Skyrim.esm"))
        let textures = try TextureLibrary(fileSystem: vfs, device: device)
        let meshes = MeshLibrary(fileSystem: vfs, device: device, textures: textures)
        builder = CellSceneBuilder(file: file, meshes: meshes, textures: textures, fileSystem: vfs)
    }

    /// Each cell that builds within `radius` of the first render cell, row by row.
    func scenes(radius: Int32) -> [CellScene] {
        (-radius ... radius).flatMap { x in
            (-radius ... radius).compactMap { y in
                try? builder.buildScene(
                    worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
                    gridX: FirstRenderCell.gridX + x,
                    gridY: FirstRenderCell.gridY + y
                )
            }
        }
    }
}
