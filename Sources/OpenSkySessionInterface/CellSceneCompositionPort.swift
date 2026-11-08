public import OpenSkyFormatsCore

/// What the world adapters use of `CellSceneComposition`.
public protocol CellSceneCompositionPort {
    associatedtype CellScene: CellScenePort
    var cells: [CellCoordinate: CellScene] { get }
}
