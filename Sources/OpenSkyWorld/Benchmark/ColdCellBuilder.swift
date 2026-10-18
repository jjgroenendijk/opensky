// A cell builder with empty caches over the install. The benchmark's cold load,
// `openskycli render`, and the preview renderer each build one.

import Foundation
import Metal
import OpenSkyCells
import OpenSkyFormatsESM
import OpenSkyGameData
import OpenSkyLoading
import OpenSkyRendering

public enum ColdCellBuilder {
    /// A builder with empty caches. A `recorder` gets every file read and asset phase.
    public static func makeBuilder(
        root: GameDataRoot, loadOrder: ActiveLoadOrder, files: any GameFileSource,
        device: MTLDevice, recorder: LoadPhaseRecorder?
    ) throws -> CellSceneBuilder {
        try makeBuilder(
            loadOrder: loadOrder, files: files, device: device, recorder: recorder,
            terrainLOD: terrainLODStore(root: root, settings: PlayerSettingsFile.savedData())
        )
    }

    /// The same builder off the main actor, with the terrain LOD settings read by the caller.
    nonisolated public static func makeBuilder(
        loadOrder: ActiveLoadOrder, files: any GameFileSource, device: MTLDevice,
        recorder: LoadPhaseRecorder?, terrainLOD: TerrainLODConfigurationStore
    ) throws -> CellSceneBuilder {
        let fileSystem: any GameFileSource = recorder
            .map { PhaseTimedFileSource(base: files, recorder: $0) } ?? files
        let textures = try TextureLibrary(fileSystem: fileSystem, device: device)
        let meshes = MeshLibrary(fileSystem: fileSystem, device: device, textures: textures)
        let builder = CellSceneBuilder(
            file: loadOrder.baseFile,
            meshes: meshes,
            textures: textures,
            fileSystem: fileSystem,
            plugins: loadOrder.files,
            terrainLODConfigurationStore: terrainLOD
        )
        builder.loadPhases = recorder
        return builder
    }

    nonisolated public static func terrainLODStore(
        root: GameDataRoot, settings: Data?
    ) -> TerrainLODConfigurationStore {
        TerrainLODConfigurationStore(snapshot: TerrainLODSettings.load(
            root: root,
            settings: settings
        ))
    }
}
