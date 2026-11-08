public import OpenSkyFormatsESM
public import OpenSkyWorldInterface

/// What the world adapters use of `MountWorldAdapter`.
public protocol MountWorldPort: AnyObject {
    func dismount(_ actor: ReferenceKey) -> Bool
    var flyingMounts: Set<ReferenceKey> { get }
    func mountOnActivation(_ key: ReferenceKey) -> Bool
    func promptLabel(for key: ReferenceKey) -> String?
    func run(_ commands: [MountCommand])
}
