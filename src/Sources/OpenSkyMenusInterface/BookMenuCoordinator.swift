import Foundation
public import OpenSkyFormatsESM
import OpenSkyFormatsSWF

/// A book read where it lies: the bar offers to take it.
public struct BookTakeOffer {
    public var isTheft: Bool
    /// The placed book, so its scripts get `OnRead`.
    public var reference: FormID?
    public var take: () -> Void

    public init(isTheft: Bool, reference: FormID? = nil, take: @escaping () -> Void) {
        self.isTheft = isTheft
        self.reference = reference
        self.take = take
    }
}
