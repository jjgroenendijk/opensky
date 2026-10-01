import Metal
@testable import OpenSkyFormatsESM
@testable import OpenSkyGameData
@testable import OpenSkyRendering
@testable import OpenSkyWorld
import Testing

/// `Skyrim.esm` and the texture and mesh libraries over the real install: the
/// loading every render suite starts with.
struct RealDataInstall {
    let device: any MTLDevice
    let root: GameDataRoot
    let fileSystem: VirtualFileSystem
    let file: ESMFile
    let textures: TextureLibrary
    let meshes: MeshLibrary

    static func load() throws -> Self {
        let device = try #require(RealDataEnvironment.device)
        let root = try #require(RealDataEnvironment.dataRoot)
        let fileSystem = VirtualFileSystem(root: root)
        let textures = try TextureLibrary(fileSystem: fileSystem, device: device)
        return try Self(
            device: device,
            root: root,
            fileSystem: fileSystem,
            file: ESMFile(url: root.dataURL.appending(path: "Skyrim.esm")),
            textures: textures,
            meshes: MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        )
    }

    /// With `readsLooseFiles`, the builder also resolves collision, actors, and strings.
    func sceneBuilder(readsLooseFiles: Bool = false) -> CellSceneBuilder {
        CellSceneBuilder(
            file: file,
            meshes: meshes,
            textures: textures,
            fileSystem: readsLooseFiles ? fileSystem : nil
        )
    }
}

extension CellSceneBuilder {
    func buildFirstRenderCell() throws -> CellScene {
        try buildScene(
            worldspaceEditorID: FirstRenderCell.worldspaceEditorID,
            gridX: FirstRenderCell.gridX,
            gridY: FirstRenderCell.gridY
        )
    }
}
