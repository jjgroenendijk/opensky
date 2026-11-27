import OpenSkyFormatsESM

nonisolated extension Land {
    /// The land as the game reads it: a field group whose DATA bit is clear is
    /// ignored even when its fields are present (docs/formats/land.md).
    var applyingDataFlags: Land {
        dropping(
            heightsAndNormals: !flags.contains(.heightsAndNormals),
            vertexColours: !flags.contains(.vertexColours),
            textureLayers: !flags.contains(.textureLayers)
        )
    }
}
