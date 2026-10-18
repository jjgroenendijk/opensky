// The seam World > Asset Cache reads: the running session's cache reader, for
// the on/off toggle, the hit counts, and one asset's entries, and the fast
// texture loading switch with its counters.

import OpenSkyAssetCache
import OpenSkyRendering

public protocol AssetCacheControlProviding: AnyObject {
    /// Nil when the session started without game data or the cache folder was refused.
    var assetCache: AssetCacheReader? { get }
    /// Nil whenever `assetCache` is nil.
    var fastTextureLoad: FastTextureLoadControl? { get }
}
