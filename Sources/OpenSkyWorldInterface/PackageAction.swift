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

    /// How long a spoken line lasts when its voice file gives no length.
    public static let unvoicedLineSeconds: Float = 3
    /// How long DialogueActivate turns the actor's head to its target.
    public static let lookSeconds: Float = 3
}
