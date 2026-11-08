/// What the world adapters use of `CellAttachment`.
public protocol CellAttachmentPort {
    associatedtype CellScene: CellScenePort
    var isFirstIntegration: Bool { get }

    var scene: CellScene { get }
}
