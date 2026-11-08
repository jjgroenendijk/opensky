public import OpenSkyMenusInterface

/// What the world adapters use of `CameraInputState`.
public protocol CameraInputStatePort: AnyObject, CameraInputReceiving {
    func addLook(right: Float, up: Float)
    var invertLook: Bool { get set }
    var lookScale: Float { get set }
}
