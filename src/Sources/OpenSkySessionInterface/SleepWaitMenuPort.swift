public import OpenSkyFormatsESM

/// What the world adapters use of `SleepWaitMenuCoordinator`.
public protocol SleepWaitMenuPort: AnyObject {
    @discardableResult func open(sleeping: Bool, bed: FormID?) -> Bool
}

/// The default arguments a protocol requirement cannot carry.
extension SleepWaitMenuPort {
    @discardableResult public func open(sleeping: Bool) -> Bool {
        open(sleeping: sleeping, bed: nil)
    }
}
