import OpenSkyConditions
import OpenSkyFormatsCore
import OpenSkyFormatsESM
import OpenSkyWorldState

/// Where an actor's current package came from, in the order selection tries them.
nonisolated public enum PackageSource: Equatable, Sendable {
    case scene
    case script
    case situation(PackageSituation)
    case alias
    case own
    case defaults
}
