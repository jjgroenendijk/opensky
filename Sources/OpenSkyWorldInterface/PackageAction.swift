public import OpenSkyFormatsESM
import OpenSkyPhysics
import simd

nonisolated public enum PackageActionResult: Equatable, Sendable {
    case done
    /// The world cannot do it, or it went wrong; the procedure fails.
    case failed
    /// It takes this many real seconds, such as a spoken line.
    case lasts(seconds: Float)
    /// What a find found, nearest first.
    case found([ReferenceKey])
}
