public import OpenSkyFormatsESM
public import OpenSkyMenusInterface

/// What the world adapters use of `BookMenuCoordinator`.
public protocol BookMenuPort: AnyObject {
    func isBook(_ item: FormID) -> Bool
    @discardableResult func open(item: FormID, takeOffer: BookTakeOffer?) -> Bool
}

/// The default arguments a protocol requirement cannot carry.
extension BookMenuPort {
    @discardableResult public func open(item: FormID) -> Bool {
        open(item: item, takeOffer: nil)
    }
}
